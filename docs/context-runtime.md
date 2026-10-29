# Context & Memory runtime — 0.14.0

## Phần đã triển khai

- `memory_search` là tool read-only của agent. Query/category/limit được kiểm tra; conversation ID do runtime gắn, model không được chọn hội thoại khác. Tìm trong memory active và prefix lịch sử đã compact, trả nguồn/role/trích dẫn/truncated và nhãn untrusted. Quét tối đa 10.000 tin / 8 MiB, tối đa 8 kết quả, mỗi quote 4.096 ký tự. Khi bằng điểm, nguồn mới hơn đứng trước. Không coi lời kể là bằng chứng thực thi hoặc quyền mới. RPC cùng chức năng: `memory.search`.
- Usage lưu **từng request/tool round**, tách theo provider ID + endpoint chuẩn hóa + model. Hiển thị tổng input/output, peak input, peak input+output và hệ số hiệu chỉnh. Không có usage từ provider thì không tự điền token đo được; benchmark dùng nonstream để lấy usage. Peak là mức API báo đã xử lý, không phải metadata xác nhận giới hạn tối đa.
- Ước lượng JSON bytes/3 dùng hệ số `max(1, max(observed_input / raw_estimate) * 1.1)` theo profile/model. Dùng ngân sách đã hiệu chỉnh khi chọn chat history và nguồn compact. Đây là cách bảo thủ, có thể để trống nhiều context với văn bản khác mẫu đã đo; chưa có tokenizer chính xác cho mọi alias.
- Auto-compact chạy ở bước chuẩn bị **trước request AI**, sau khi user message/task đã lưu. Ngưỡng 50–95% input budget; mặc định 80%, **mặc định tắt**. Hai lựa chọn: tạo candidate để duyệt, hoặc tự áp dụng candidate đã qua kiểm tra rồi tiếp tục lượt AI. Nếu cần duyệt/lỗi/hủy, không gửi request AI và giữ tin nhắn trong lịch sử.
- Auto lưu ý định theo conversation/task trước request compact. Restart không tự phát lại ý định chưa rõ kết quả; job đang running chuyển failed, active cũ giữ nguyên. Cooldown 60 giây, mỗi lượt chỉ thử một lần, không loop retry. Keychain được đọc khi bắt đầu lượt; key chỉ giữ trong RAM qua compact → chat, không lưu vào config/SQLite/log. Chỉ có thể bắt đầu khi mở khóa; khóa sau khi request đã bắt đầu dùng key đang giữ và power lease.
- Checkpoint active/superseded giữ raw transcript. Có RPC list/preview/restore, swap trong transaction và kiểm hash prefix. Native Context và web có nút khôi phục checkpoint trước. Không restore trong khi AI/compact đang hoạt động.
- Memory tránh lặp nguyên văn giữa required evidence/các mục: một bản ghi có thể có nhiều `categories`. Khi compact tiếp, tag artifact/work/constraint/permission vẫn giữ vai trò sticky evidence. Đọc được memory schema 2 cũ.

## Cài đặt

App: Cài đặt → Context & Memory: bật auto-compact, tự áp dụng hoặc duyệt, ngưỡng snap 5%. Đây là mặc định chung. Web Context đặt override cho hội thoại hiện tại. RPC `context.settings`/`context.configure` không có conversation_id dùng scope chung; có conversation_id dùng override riêng. Tool của model không thể gọi cấu hình hoặc restore.

Web giữ auth/CSRF/interactive gate cho cấu hình/restore. Các endpoint GET `/api/memory-search`, `/api/checkpoints`, `/api/checkpoint` chỉ đọc; POST `/api/context-config`, `/api/restore` cần quyền tương tác.

## Kiểm tra offline/native

Host: core memory/search, SQL migration/usage/auto intent/scoped settings, SQL multi-compact/restore, runtime dedupe/recovery, eval scorer và UI web. Native:

```bash
/var/jb/usr/bin/agenthomed --self-test-memory
/var/jb/usr/bin/agenthomed --self-test-context
```

Lệnh thứ hai dùng SQLite `:memory:` và endpoint trống, không gọi API. Kiểm tra archive search/cross-conversation isolation, activate/restore/hash, busy guard, usage từng round/provider isolation/calibration, callback auto thất bại đúng một lần, recovery từ ý định cũ và giữ memory active.

## Bộ test thiết bị nhiều vòng

`tests/iphone_context_e2e.pl` chạy bằng Perl trên iPhone. Profile JSON **chỉ chứa metadata**, không đưa API key vào file. Các khóa hợp lệ: id, endpoint, model, disableStreaming, context_window_tokens, max_output_tokens. ID phải khớp profile đã có key trong Keychain. Script không sửa profile đã lưu; context test mặc định 200K nếu metadata chưa khai báo.

Chép script và metadata profile lên `/var/mobile/`, rồi ví dụ:

```bash
perl /var/mobile/iphone_context_e2e.pl begin /var/mobile/profile-a.json /var/mobile/Library/AgentHome/eval-cycle.json
perl /var/mobile/iphone_context_e2e.pl seed /var/mobile/profile-a.json /var/mobile/Library/AgentHome/eval-cycle.json
perl /var/mobile/iphone_context_e2e.pl compact /var/mobile/profile-a.json /var/mobile/Library/AgentHome/eval-cycle.json
perl /var/mobile/iphone_context_e2e.pl poll /var/mobile/profile-a.json /var/mobile/Library/AgentHome/eval-cycle.json
```

Chỉ `activate` khi poll có candidate ready. Sau đó `recall`, poll tới terminal, `search` để tìm LOTUS-482. Lặp seed/compact/poll/activate/recall đủ ba vòng: font mong đợi lần lượt 14/15/16, giữ cùng mã/path/trạng thái chưa kiểm chứng. Dùng phase `switch` với profile-b.json có provider/model **thực sự khác** giữa các vòng để kiểm tra chuyển provider. Script từ chối coi cùng profile là phép thử chuyển provider.

Phase `auto` chỉ bật auto cho **hội thoại giả lập** (ngưỡng 50%, tự áp dụng). Sau seed đủ gần ngân sách, dùng recall để kích hoạt. Kiểm tra poll có active mới và AI hoàn tất; phase `cancel` kiểm tra dừng lúc queued/running. Phase `restore` khôi phục checkpoint trước và tự kiểm tổng số raw messages không đổi. Nếu phần required evidence không vừa ngân sách, lỗi và giữ checkpoint là kết quả đúng về an toàn, nhưng phải ghi riêng là chưa compact thành công.

Phase `long-answer`: chờ poll thấy AI running rồi **người dùng khóa máy**, đợi mở lại và poll để kiểm trả lời không bỏ dở. Script không tự thao tác khóa/mở khóa hay biết mật khẩu thiết bị. Không được ghi “lock test pass” nếu chưa thực hiện bước này. Phase `probe N` tạo N byte hex giả lập trong hội thoại mới, nonstream, max output 256; poll lấy usage báo cáo. Hiệu chỉnh bằng mẫu nhỏ trước mẫu lớn. Không dùng số byte làm số token. Dùng state mới cho mỗi probe để không cộng dồn payload cũ.

Phase `cleanup` chỉ xóa conversation do state file test ghi nhận; từ chối nếu task đang queued/running. Cấu hình auto scope hội thoại test cũng được dọn. Chạy cleanup sau khi lưu bằng chứng; không xóa hội thoại người dùng để lấy điểm pass.

## Trạng thái xác minh

Phần triển khai 0.14.0 đã build và kiểm tra host. Self-test/đa vòng/auto/đổi provider/khóa máy cho **bản 0.14.0** cần chạy sau khi cài. Chưa xem chúng là pass chỉ vì có script. Có hai profile metadata cấu hình trên thiết bị (compatible và Gemini) để chạy phép thử chuyển provider mà không đưa key ra host.

Đo API thật ngay trong lượt triển khai bằng bản đang cài 0.13.0, endpoint/model hiện tại: input được báo 21.643, 178.778 và **196.641 token**. Mẫu nhỏ trả PROBE_OK; hai mẫu lớn không làm đúng yêu cầu trả marker dù request không lỗi. Kết quả này xác nhận mức API đã chấp nhận gần 200K, **không** xác nhận trí nhớ/chất lượng toàn bộ 200K hay metadata max window. Profile thật không bị đổi khỏi context=0. Bằng chứng: `tests/fixtures/context-capacity-live.json`.
