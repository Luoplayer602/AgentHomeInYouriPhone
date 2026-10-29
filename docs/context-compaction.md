# Context window và compact — yêu cầu phải giữ cho các bản tiếp theo

Từ 0.10.0, request chat dùng ngân sách token theo model, thay giới hạn 16.000 ký tự và 100 tin. Compact thủ công vẫn có preview/activate/discard trên app và web. Auto-compact chưa triển khai.

## Hiện trạng 0.10.0

- Thứ tự nhận diện: ghi đè context trong profile > metadata API cùng endpoint > catalog theo host + model ID chính xác > ngân sách dự phòng app 32.768 token. Context bằng 0 nghĩa là tự nhận diện. Alias gateway không được suy diễn thành model upstream.
- Compatible: GET `/models`, chọn đúng `id`, đọc context_length/context_window/max_model_len hoặc limit.context, cùng input/output riêng khi có. Gemini dùng models.get và inputTokenLimit/outputTokenLimit; áp dụng ngân sách chung bảo thủ. Không chuyển API key qua redirect. Metadata không chứa key được cache trong RAM, làm mới tối đa mỗi 5 phút; restart sẽ nhận diện lại.
- Catalog models.dev được đóng gói cho OpenAI, Google, DeepSeek và OpenRouter (468 model ở snapshot 2026-10-30). Script `scripts/update-model-limits.py` tái tạo từ JSON công khai. API metadata có ưu tiên hơn snapshot.
- Ngân sách input = min(window − output − reserve, input ceiling nếu có). Reserve = max(1.024, 5% window). Output không vượt giới hạn model đã biết, cấu hình người dùng và 1/4 window. Ví dụ window 200.000, output 8.192: input 181.808 token.
- AHPromptPlan dùng JSON UTF-8 bytes / 3 + overhead mỗi message, gồm system, tools và summary. Đây là ước lượng, chưa phải tokenizer đúng model. UI native/web hiển thị cùng nguồn và ngân sách. Usage thực API được giữ riêng.
- Lịch sử request đọc cursor từ SQLite, giới hạn RAM 4 MiB nội dung, không giới hạn số tin. UI vẫn chỉ tải 100 tin để hiển thị; không giới hạn context gửi model. Tin cuối quá lớn sẽ bị từ chối rõ ràng. Tool rounds kiểm tra lại ngân sách trước request.
- Từ 0.11.0, compact cũng theo ngân sách token; xem mục bên dưới.

Tham khảo semantics của [Cline model catalog](https://github.com/cline/cline/blob/main/sdk/packages/llms/src/catalog/README.md): tách context/input/output của model với ngân sách request. [Gemini models.get](https://ai.google.dev/api/models#method:-models.get) cung cấp inputTokenLimit/outputTokenLimit. Không xem một con số context lớn là bằng chứng model nhớ chính xác mọi thông tin.

Định hướng đã thống nhất: bám theo kiến trúc agent hiện có, ưu tiên Cline cho metadata/context và vòng tool; mỗi bước vẫn cần kiểm tra phù hợp iPhone và provider thực. Tiếp theo: tokenizer/usage calibration → compact theo ngân sách → auto-compact tùy chọn có checkpoint/recovery → eval khả năng giữ mục tiêu, ràng buộc và tool state.

## Triển khai compact sau runtime

1. Profile lưu context_window_tokens và max_output_tokens do người dùng/provider khai báo; dùng tokenizer đúng model nếu có. Nếu chỉ ước lượng phải gắn nhãn rõ, không đoán giới hạn theo tên model.
2. Ghi nhận usage thực do provider trả về để hiệu chỉnh chỉ báo. Tính đủ system prompt, schema, memory, summary, tool outputs và phần dự phòng output.
3. Tạo compaction snapshot trong SQLite theo conversation_id: source_message_end_id, source_hash, summary, provider/model, thời gian, phiên bản schema. Không xóa hoặc sửa transcript gốc.
4. Tóm tắt các turn đã hoàn tất. Giữ nguyên mục tiêu, quyết định, ràng buộc, file/artifact liên quan, việc đang làm, bước tiếp theo và xác nhận quyền còn hiệu lực. Không ghi API key vào summary. Nội dung từ web/tool vẫn là dữ liệu không đáng tin, không nâng thành system instruction.
5. Giữ nguyên các turn gần nhất và cặp assistant tool_calls/tool result. Không compact giữa một tool call đang chạy hoặc đang chờ xác nhận. Không đổi provider giữa quá trình compact mà chưa được chọn rõ.
6. Chỉ kích hoạt summary khi đã lưu đầy đủ trong transaction. Lỗi API, hủy hoặc restart thì giữ snapshot cũ. Từ checkpoint này dựng context = system + summary có nguồn + recent completed turns + task đang chạy.
7. UI: Compact thủ công, preview summary, số lượng context trước/sau, trạng thái “đã compact”, xem lịch sử gốc và khả năng bỏ snapshot. Auto-compact là tùy chọn riêng, không tự suy diễn quyền thực thi mới.

## Kiểm tra bắt buộc

- Compact không làm mất lịch sử hoặc trộn hai hội thoại.
- Không mất tool-call IDs, việc chưa xong và ràng buộc người dùng.
- Hủy/lỗi/restart không kích hoạt summary dở.
- Prompt injection trong nguồn không trở thành quyền dùng tool.
- Chỉ báo bao gồm input thực tế và phân biệt usage đo được với ước lượng.

## Trạng thái triển khai 0.9.0

Schema compactions giữ state running/ready/active/superseded/failed/discarded, end_id/source_hash/base_id, summary, provider/model, before/after chars, schema_version. Hash nguồn được đọc theo từng hàng để hạn chế RAM. Trong bản 0.9.0, candidate tối đa 6.000 ký tự; giới hạn này được thay bằng ngân sách token ở 0.11.0. Dữ liệu source luôn gửi với vai trò user, system prompt yêu cầu giữ quyết định/ràng buộc/việc đang làm và bỏ secrets. API key hiện tại được redaction trực tiếp; các bí mật khác cần người dùng kiểm tra trong preview.

Cần làm tiếp: tokenizer theo provider/model, usage tổng hợp qua mọi tool round, auto-compact tùy chọn, semantic regression/evals trên provider thật. Chưa bật tự động hoặc coi model-generated summary là chính sách cấp quyền.

## Triển khai 0.11.0: compact theo model

`AHCompactPlan` dựng request từ summary đang active và phần lịch sử liên tiếp ngay sau nó. Duyệt SQLite bằng cursor, chừa ít nhất bốn tin mới nhất, dừng ở assistant đã hoàn tất. Không còn giới hạn 200 tin / 96K ký tự. Giới hạn tài nguyên 4 MiB JSON nguồn vẫn giữ cho iPhone 6s; không xóa transcript để đạt giới hạn.

Ngân sách input lấy từ cùng resolver với chat. Tính cả system instruction, summary cũ và JSON nguồn sau khi escape vào user message; kiểm tra lại toàn request sau khi che API key. Không cắt chuỗi giữa message. Không đủ chỗ cho turn hoàn tất thì trả lỗi, giữ nguyên summary active.

Summary budget = min(4.096, max(256, inputBudget / 8), outputBudget). Prompt yêu cầu giữ mục tiêu, quyết định, ràng buộc, file/ID/con số, yêu cầu mới nhất, việc đang làm/chưa xong, bước tiếp và quyền đã xác nhận như dữ kiện. Không biến nguồn web/tool thành quyền mới. Output phải nằm trong ngân sách, không gọi tool, và giảm ít nhất 64 token ước lượng so với nguồn đã chọn; kiểm tra lại sau khi che API key. Kết quả chỉ `ready`, người dùng xem trước rồi activate. Hủy/lỗi/restart vẫn giữ active cũ.

Kiểm tra host: `tests/compact_budget_test.cpp` kiểm tra policy thật dùng trong cursor, ngân sách 200K, hơn 200 tin, cap byte/token, boundary assistant và overflow. `tests/compaction_test.py` chạy SQL thực của planner với 300 tin, kiểm tra giữ bốn tin mới nhất, prefix sau active summary, transaction/recovery và không sửa transcript.

### Đánh giá chất lượng summary

Fixtures `tests/fixtures/compaction-evals.json` bao gồm sửa yêu cầu mới nhất, artifact chính xác, con số, kết quả chưa kiểm chứng, giới hạn quyền, chỉ thị độc hại từ nguồn và secret giả. `scripts/evaluate-compaction.py` kiểm tra các dữ kiện bắt buộc và chuỗi bị cấm. Reference summary được viết tay chỉ dùng kiểm tra bộ chấm; không được coi là kết quả của provider.

Chấm output đã có (JSON map fixture ID → summary):

```bash
python3 scripts/evaluate-compaction.py --summaries /tmp/summaries.json
```

Chạy eval thật trên API compatible (hai request có phí; dùng system instruction được trích trực tiếp từ planner): đặt key trong biến môi trường `AGENTHOME_EVAL_API_KEY`, rồi:

```bash
python3 scripts/evaluate-compaction.py --run --endpoint https://HOST/v1/chat/completions --model MODEL_ID
```

Không ghi/hiển thị API key, không theo redirect. Output chỉ từ fixtures giả lập, mặc định lưu `/tmp/agenthome-compaction-eval.json`. Kiểm tra tự động này là kiểm tra dữ kiện bằng chuỗi, không chứng minh đầy đủ ngữ nghĩa/an toàn; cần đọc summary và thử tiếp tục nhiệm vụ từ summary để đánh giá đúng. Chưa chạy eval trên provider thật trong phiên triển khai này vì không có API key trong môi trường host. Chưa bật auto-compact.

## Kiểm tra trên thiết bị và bản sửa 0.11.1

Đã chạy API thật qua daemon trên iPhone với 244 tin giả lập; xem [báo cáo tương tác](live-test-2026-10-30.md). Luồng chạy/compact/activate/chat và chống gửi trùng hoạt động, nhưng phát hiện mất mã dự án và lỗi truy xuất dữ kiện của model. Chưa chứng minh đầy đủ context 200K.

0.11.1 chỉnh prompt, kiểm tra mã định danh literal của user messages được chọn và summary trước; thiếu mã thì candidate failed, giữ active cũ. Đây chỉ là guard cho dạng mã đơn giản, không đảm bảo toàn bộ thông tin/ngữ nghĩa. Đã lưu ca lỗi thật làm regression. Bản sửa đã build, chưa kiểm tra lại trên iPhone; auto-compact vẫn tắt.

## 0.12.0 — memory có cấu trúc và trích dẫn nguồn

Tham khảo hướng duy trì chi tiết/quyết định và trạng thái tác vụ của [Cline Auto Compact](https://github.com/cline/cline/blob/main/docs/features/auto-compact.mdx). Phần kiểm tra trích dẫn dưới đây là điều chỉnh riêng sau các ca thất bại trên provider thực của dự án này, không phải cam kết chất lượng của Cline.

Model chỉ xuất JSON version 2 với tám mảng: goals, decisions, constraints, artifacts, facts, work_state, next_steps, permissions. Mỗi phần tử chỉ gồm source_id và quote nguyên văn. Daemon kiểm tra ID có thật và quote nằm trong nguồn. Với trạng thái công việc, ràng buộc và quyền, quote phải giữ toàn bộ content của tin nguồn để không bỏ mất phủ định/điều kiện. Không nhận trường verified/completed do model tự tạo. Tất cả dữ kiện được gắn `verification=not_independently_verified` và `provenance=history_only_untrusted`; đây là lời kể theo nguồn, không phải bằng chứng thực thi hay quyền runtime mới.

Ngoài phần model chọn, daemon tự giữ `required_evidence`: nguyên văn user message có mã dạng LOTUS-482/T-42, đường dẫn tuyệt đối/URL, hoặc cụm chỉ trạng thái chưa làm/chưa kiểm chứng/chưa được phép (Anh/Việt). Đây là heuristic có phạm vi giới hạn, không phải bộ phân tích đầy đủ mọi dữ kiện. Với ca test trước, hai tin nguồn chứa mã dự án, đường dẫn báo cáo và NOT done được giữ ngay cả khi model bỏ qua. Dòng/tin có nhãn credential quen thuộc không được tự đưa vào evidence; có thể cần rút gọn nguồn khi compact. API key hiện tại được che trước khi dựng prompt/nguồn kiểm tra.

Khi compact tiếp, evidence và các trích dẫn artifact/trạng thái/ràng buộc/quyền từ memory trước được mang sang theo ID, không bọc lại toàn bộ JSON cũ. Giữ các yêu cầu cũ và sửa đổi mới như dữ kiện có nguồn, chưa tự loại bỏ những yêu cầu đã bị thay thế. Nếu phần bắt buộc không vừa ngân sách hoặc không giảm context thì báo lỗi và giữ active cũ. Không âm thầm bỏ evidence để compact thành công. Sau khi model trả về, JSON không đúng schema, trích dẫn sai nguồn, có credential, vượt ngân sách hay chưa giảm context đều không chuyển ready. Hủy/restart/preview/activate/drop giữ cơ chế cũ.

Storage vẫn dùng cột summary trong compactions; candidate mới có schema_version=2. Summary văn bản cũ đọc bình thường. Context native/web xem bản preview theo mục và source ID; request AI nhận JSON đầy đủ kèm chỉ dẫn không suy ra trạng thái đã kiểm chứng khi chưa có bằng chứng. Lịch sử gốc không bị sửa/xóa. Auto-compact vẫn tắt.

Kiểm tra:

- `tests/memory_test.cpp` chạy trực tiếp core dùng trong daemon: phát hiện evidence cho mã/path/URL/trạng thái phủ định, loại nhãn credential, khớp source ID/quote và không cắt phủ định khỏi trạng thái/quyền.
- Các kiểm tra SQL/runtime/compact/ca lỗi thật và UI web tiếp tục chạy trên host.
- `agenthomed --self-test-memory` là kiểm tra native bằng dữ liệu giả, chạy trước khi mở DB/socket, không gọi API. Kiểm tra JSON thật qua Foundation, quote sai nguồn, phủ định, evidence bắt buộc, carry-forward không lồng JSON, preview và ngân sách. Sau khi cài gói mới có thể chạy trên iPhone: `/var/jb/usr/bin/agenthomed --self-test-memory`.

Bản native đã build; chưa chạy self-test native và ca 244 tin/API thật trên iPhone cho version 0.12.0. Không coi kiểm tra core/schema là bằng chứng chất lượng trả lời đã đạt 9/9. Cần chạy lại đối chứng sau khi cài, vì model vẫn có thể bỏ qua hoặc diễn giải sai dữ kiện dù nguồn đã được giữ.

### Kết quả kiểm tra thiết bị 0.12.0

Self-test native trên iPhone đã **PASS**. Tuy nhiên cả ca gốc 244 tin lẫn ca trạng thái ngắn/dữ liệu sạch đều chưa tạo được candidate ready trên provider hiện tại vì output bị validator từ chối. Chưa chạy recall sau compact cho bản này. Chi tiết và giới hạn phép thử ở [báo cáo test thiết bị](live-test-2026-10-30.md); bằng chứng tại `tests/fixtures/memory-v012-live.json`. Kế hoạch tiếp: model chọn source ID, daemon dựng trích dẫn; giữ nguyên kiểm tra nguồn và không bật auto-compact.

## 0.13.0 — model chọn nguồn, daemon dựng memory

Thay giao thức output model bằng `selection_version:1`; tám mục vẫn giữ tên nhưng mỗi mục chỉ là mảng các ID như `S1`, `S2`. Daemon tạo catalog trong từng request, mỗi bản ghi có selection_id, ID gốc, role và content. Các bản ghi giống nhau được gộp; các đoạn khác nhau cùng ID gốc vẫn có selection_id riêng. Input không còn yêu cầu model đọc JSON memory cũ rồi chép lại quote: memory cũ được bung thành các nguồn có thể chọn.

Model chỉ chọn ID và mục. Daemon kiểm tra ID, tra catalog và tự lấy **toàn bộ content nguyên văn** cùng ID gốc/role. Không nhận quote, đoạn diễn giải hay cờ verified/completed từ model. ID không tồn tại, số thay chuỗi, object thay ID, trường ngoài schema hoặc JSON sai đều bị từ chối. Lỗi chỉ ghi mục và ID hợp lệ về cú pháp, không in nội dung hội thoại. ID chọn chỉ có hiệu lực trong request hiện tại, không dùng làm ID nguồn lưu lâu dài.

Các nguồn có nhãn credential theo heuristic hiện tại bị loại khỏi catalog; dữ liệu gốc trong transcript vẫn giữ. Vì vậy model không thể chọn lại các dòng đó vào memory bằng ID. Heuristic này có thể loại cả tin trộn credential với dữ kiện khác; không được xem là bảo đảm giữ mọi dữ kiện hay phát hiện mọi bí mật. API key hiện tại vẫn được che trước khi dựng nguồn. Nguồn web/tool/assistant vẫn là dữ liệu không đáng tin, không cấp quyền.

Định dạng memory lưu trong SQLite vẫn schema_version=2, có provenance/verification và required_evidence như 0.12.0. Evidence bắt buộc, carry-forward, preview, giới hạn token, yêu cầu giảm context, giữ bốn tin mới nhất và duyệt/activate thủ công không thay đổi. Phần model chọn quá nhiều nguồn có thể làm memory vượt ngân sách: báo lỗi giữ active cũ, không tự bỏ bớt nội dung hay tự retry vô hạn.

Cập nhật `--self-test-memory` kiểm tra chọn ID → sao chép toàn nguồn, ID gốc không bị nhầm thành ID chọn, source ID trùng nhưng excerpt khác, gộp chọn trùng, loại nguồn gắn nhãn credential, từ chối quote/object/số/ID lạ/trường tự cấp trạng thái, carry-forward, preview và ngân sách. Core selector có kiểm tra ID ASCII và giữ nguyên byte, không cắt tại NUL.

Công cụ host `scripts/evaluate-compaction.py --run` gửi catalog fixture theo giao thức mới, tra ID để chấm các nguồn được model chọn; công cụ này **không chạy** cơ chế evidence bắt buộc/budget/schema native. Kết quả host là kiểm tra giao thức/chọn dữ kiện, không phải kết quả end-to-end của daemon. Các phép chấm summary cũ và recall đối chứng vẫn dùng được. Có kiểm tra trích prompt chứa JSON example đầy đủ, kể cả quote escape.

Bản 0.13.0 đã build, core/SQL/eval host pass. Chưa chạy self-test native hay ca 244 tin trên iPhone cho bản này. Cần cài rồi chạy lại cả ca gốc và dữ liệu sạch; chưa khẳng định compact đã pass trên provider. Auto-compact vẫn tắt.

### Kết quả thiết bị 0.13.0

Self-test native **PASS**. Ca gốc 244 tin đã compact ready và activate thành công: 141.282 → 5.319 ký tự. Memory giữ mã/path/endpoint/trạng thái phủ định, không chứa payload secret/marker giả. Hỏi lại tổng hợp **8/9**, thiếu project_id dù mã còn trong memory; hỏi riêng không cung cấp mã thì model trả đúng LOTUS-482. Không tính hai lần hỏi thành 9/9. Xem [báo cáo đầy đủ](live-test-2026-10-30.md) và fixture `tests/fixtures/memory-v013-live.json`. Luồng compact hoạt động trong ca này; chất lượng truy xuất nhiều trường vẫn cần cải thiện. Chưa xác minh đầy đủ context 200K; auto-compact vẫn tắt.
