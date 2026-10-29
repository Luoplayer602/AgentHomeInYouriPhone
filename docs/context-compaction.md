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
