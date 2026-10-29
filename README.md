# Agent Home — nền tảng v0.8.0

App iOS và daemon độc lập dành cho iPhone jailbreak rootless. Đích hiện tại: iPhone 6s, iOS 15, Dopamine; build bằng Theos trong WSL2.

## Bản 0.8.0 — Webview và reasoning từ provider

**Cài đặt → Webview**: Bật Webview (mặc định tắt), port 1024–65535 (mặc định 8765), password và Cho phép tương tác (mặc định tắt). Lưu sẽ áp dụng ngay, không cần restart. Port lỗi được hiển thị; không tự mở port Internet/NAT.

- Mật khẩu trống: chế độ công cộng, ai kết nối được port đều đọc được hội thoại/reasoning. Tương tác bật cho phép họ tạo chat, gửi và dừng AI. UI có cảnh báo rõ. Không có xác nhận phụ.
- Mật khẩu có giá trị: PBKDF2-HMAC-SHA256 salt ngẫu nhiên, 120.000 vòng; chỉ verifier được lưu SQLite. Login có giới hạn lần thử, cookie HttpOnly/SameSite=Strict hết hạn sau một giờ. Đổi cấu hình hủy session/luồng cũ.
- HTTP thuần: dùng mạng tin cậy/Tailscale hoặc SSH tunnel. Không nhập mật khẩu này trên mạng công cộng không mã hóa. Web không trả API key và không có endpoint cấu hình server/provider/shell.
- Cần nhập lại mật khẩu khi mở lại màn hình cấu hình nếu muốn giữ chế độ có mật khẩu; để trống khi Lưu sẽ chuyển công cộng.

Sau khi cài/restart daemon, bật Webview trong app, lưu và mở:

```text
http://100.65.210.88:8765
```

Web có danh sách chat, Markdown/code Copy/bảng, EventSource SSE cập nhật snapshot khi thay đổi, khung Thinking thu gọn, gửi/dừng/tạo chat nếu bật tương tác. Reasoning là nội dung provider thực sự phát qua `reasoning_content` hoặc chuỗi `reasoning`; không truy cập được suy nghĩ nội bộ không có trong API. Non-streaming chỉ hiện reasoning sau khi provider trả xong. Không tự bật thinking mode bằng tham số đặc thù của model. Tham khảo [DeepSeek Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode/).

**Output dài hơn:** mỗi provider có Max output tokens, mặc định 8.192, cho phép 256–32.768 tùy model. App giới hạn output và reasoning mỗi phần 64.000 ký tự, response mạng 2 MB; timeout chờ dữ liệu 180 giây/request tổng 600 giây, watchdog lượt 15 phút. Đây là mức trần, không ép model chạy đủ một phút hoặc tự gửi “tiếp tục”. Chạm giới hạn vẫn báo rõ. Context hiện vẫn dùng ngân sách ký tự riêng như các bản trước; reasoning không tự đưa vào transcript trả lời.

**Kiểm tra thiết bị:** đăng nhập sai/đúng, đổi password thì session cũ bị hủy; tắt tương tác rồi thử gửi bằng web phải bị từ chối; bật tương tác và thử gửi/dừng; để password trống kiểm tra nhãn CÔNG CỘNG; tắt Webview thì port và SSE phải đóng; kiểm tra stream reasoning trên model có cung cấp field tương ứng. Bắt đầu lượt mới qua web vẫn cần Keychain đọc được (thường cần mở khóa máy lúc bắt đầu); lượt đã bắt đầu tiếp tục dùng key trong RAM.

Các API giới hạn: GET /api/status, /api/conversations, /api/messages?conversation_id=..., /api/events?conversation_id=...; POST /api/login, /api/create, /api/submit, /api/cancel. POST tương tác cần JSON + cookie (nếu có mật khẩu) + header X-AH-CSRF lấy từ /api/status. Host phải là IP trực tiếp/localhost với đúng port; không cung cấp CORS, kiểm tra Origin/CSRF, giới hạn framing và số kết nối. Mỗi SSE stream kết thúc sau khoảng 30 giây rồi EventSource tự nối lại.

Kiểm tra host: tests/http_test.cpp kiểm tra parser và các gate Host/Origin/cookie/CSRF; tests/web_ui_test.js chạy JavaScript thực với DOM tối giản để kiểm tra rendering và chế độ chỉ xem; không thay thế test browser/iPhone thực. Runtime SQL và migration test tiếp tục áp dụng.

## Bản 0.7.1 — chẩn đoán khóa màn hình và phản hồi bị cắt

- Giới hạn output mặc định tăng từ 1.024 lên 4.096 token. Provider `finish_reason=length` hoặc content_filter được báo là phản hồi gián đoạn, không đánh dấu completed âm thầm; nhật ký ghi finish_reason. Không tự gọi tiếp làm phát sinh request ngoài ý muốn.
- Key của lượt đang chạy được giữ trong RAM qua các vòng tool và bỏ tham chiếu khi kết thúc. Không thay đổi mức bảo vệ Keychain và không ghi key vào SQLite. Lượt mới bắt đầu khi đã khóa vẫn có thể cần mở khóa để lấy key.
- Một power assertion `PreventUserIdleSystemSleep` được yêu cầu chỉ trong lượt AI; không yêu cầu giữ sáng màn hình, được nhả khi xong/lỗi/hủy và có timeout 900 giây. Mã trả về được ghi trong Tác vụ (0 = API chấp nhận); iOS có thể không đáp ứng yêu cầu trong một số trạng thái. Tham khảo [IOKit IOPMLib của Apple](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h).
- Cả lượt có watchdog 15 phút. Không giữ máy thức khi idle.

Chẩn đoán trước sửa trên thiết bị: lượt gần nhất có state completed, partial 3.823 ký tự, không có lỗi. Vì bản cũ bỏ qua finish_reason nên chưa kết luận nó dừng do khóa màn hình hay chạm max_tokens. Đã dừng daemon thủ công cũ PID 11205, còn lại daemon hiện tại. Cần kiểm tra lại với yêu cầu dài rồi khóa máy 30–60 giây; xem finish_reason và power assertion trong nhật ký nếu vẫn bị cắt.

## Bản 0.7.0 — AI chạy trong daemon

App gửi `ai.submit` gồm request ID, text và metadata provider; daemon đọc API key từ access group Keychain chung, dựng context và chạy streaming/tool loop. API key không truyền qua IPC hoặc ghi SQLite. App chỉ poll tiến độ và lịch sử; socket đọc theo chunk để giảm syscall khi poll.

- Mỗi hội thoại tối đa một lượt đang queued/running; toàn thiết bị chạy một request AI tại một thời điểm để hạn chế RAM. Hội thoại khác có thể chờ trong queue.
- Submit có ID ổn định và thử lại cùng ID khi mất phản hồi, tránh lưu trùng tin user. User message, config snapshot và job được lưu cùng transaction.
- Partial response/context/tool round được checkpoint trong SQLite. Final assistant message và trạng thái kết thúc lưu cùng transaction, không có app ghi thêm lần nữa.
- Nút Dừng gọi daemon. Quay về danh sách được khi đang trả lời; trở lại chat hoặc mở lại app sẽ nối lại tiến độ. Chat tắt không hủy provider request.
- Restart daemon: task read-only được retry; request AI đang chạy đánh dấu failed và giữ partial kèm nhãn gián đoạn. Không tự phát lại request có thể đã tính phí. Queued job chưa gọi mạng vẫn được chạy.
- Cần thiết bị mở khóa khi daemon lấy key từ Keychain (`WhenUnlockedThisDeviceOnly`). Từ 0.7.1, các tool round của cùng lượt dùng key đã giữ trong RAM. Khả năng Keychain trên Dopamine thực tế cần kiểm chứng sau khi cài; nếu lỗi UI sẽ báo rõ. Không đảm bảo tiếp tục khi jailbreak bị tắt hoặc daemon bị hệ thống dừng.

Kiểm tra thiết bị sau khi cài và restart daemon:

1. Giữ máy mở khóa. Gửi yêu cầu trả lời dài, xem chữ hiện dần.
2. Đóng/force-quit app khi đang trả lời, chờ rồi mở lại: câu trả lời phải còn và không có tin trùng.
3. Quay về danh sách, mở chat khác để gửi lượt chờ; kiểm tra mỗi hội thoại riêng.
4. Nhấn Dừng giữa phản hồi, kiểm tra partial được lưu có nhãn.
5. Yêu cầu dùng tool kiểm tra dung lượng; xem nhật ký trong Tác vụ.
6. Restart daemon giữa request: UI báo gián đoạn, không tự gọi API lại. Queued read-only task vẫn phục hồi.

Host checks: `python3 tests/runtime_db_test.py` kiểm tra SQL thực của runtime cho enqueue/complete nguyên tử, duplicate rollback, checkpoint và recovery không replay. Các test C++ database/tasks vẫn áp dụng. Build và entitlement đã kiểm tra trên WSL; request nền và Keychain cần chạy thử trên iPhone thật.

## Bản 0.6.0 — hàng đợi tác vụ và context

- Preset chữ thêm **12 pt**, giữ nguyên số pt đang chọn từ bản cũ.
- Nút **Tác vụ** trong thanh dưới hội thoại → **Kiểm tra** tạo task `system.info` trong daemon. Task ID, trạng thái queued/running/completed/failed và nhật ký từng bước lưu SQLite. Mở lại app vẫn xem kết quả. Khi daemon khởi động lại, task read-only đang running được đưa lại queued; không tự chạy lại hành động có tác dụng phụ.
- Chỉ cho phép tool đọc trạng thái mức rủi ro 0. Chat model/API và vòng gọi tool AI **vẫn chạy trong app**, chưa được chuyển sang daemon; task mới là phần nền độc lập đầu tiên. Chưa có scheduler hay thực thi shell.
- **◉ %** hiển thị phần ngân sách 16.000 ký tự tin nhắn được dùng cho lần gửi tiếp. Nhấn xem số tin được đưa vào/ngoài lượt gửi. Đây không phải token hoặc giới hạn context thật của model, chưa tính system prompt và tool schemas. Lịch sử gốc giữ trong SQLite. Thiết kế compact ở [docs/context-compaction.md](docs/context-compaction.md).

Sau khi cài phải restart daemon. Kiểm tra: tạo task, đóng app, mở lại Tác vụ để đọc kết quả/nhật ký. Task đọc nhanh có thể xong trước khi đóng app. Kiểm thử host bao gồm mở lại file SQLite và phục hồi task đang running. Chưa kiểm chứng tự động trên iPhone mới nâng cấp.

## Bản 0.5.1

Tin nhắn người dùng đo chiều rộng theo nội dung, giữ căn phải và giới hạn 86% chiều rộng hàng; tin dài xuống dòng. Tin AI giữ vùng rộng để hiển thị code/bảng.

**Cài đặt → Hiển thị** có slider 5 mốc snap: Nhỏ 14 pt, Vừa 16 pt (mặc định), Lớn 18 pt, Rất lớn 20 pt, Tối đa 22 pt. Kéo để chọn và xem trước, lưu ngay. Áp dụng cho hội thoại, ô nhập, tiêu đề danh sách chat, code và bảng khi quay lại; không đổi font toàn hệ thống. Cache Markdown phân biệt cỡ chữ để lịch sử cũ cũng cập nhật đúng.

Kiểm tra thiết bị: tin ngắn/emoji phải ôm nội dung, tin nhiều dòng vẫn căn phải; kéo slider qua từng mốc, quay lại chat kiểm tra cả lịch sử và code/bảng, đóng/mở app kiểm tra lựa chọn được giữ. Bản này không đổi schema daemon.

## Bản 0.5.0

Cài đặt dùng các hàng và nhóm riêng:

```text
API PROVIDER
  Saved providers          tên đang chọn
  Streaming                [switch]
DEVICE INFO
  Device info
```

Nhấn **Saved providers**: dòng **＋ Add provider** ở trên, dưới là tên từng provider và loại bằng chữ nhạt. Nhấn hàng để chọn ngay; nhấn **Sửa** để chỉnh sửa. Add provider mở danh sách loại:

- **OpenAI compatible**: tên, base URL, model ID, API key.
- **Gemini**: tên, model ID, Google AI Studio API key; endpoint có sẵn. Dùng [OpenAI compatibility endpoint chính thức của Google](https://ai.google.dev/gemini-api/docs/openai/), chưa dùng native GenerateContent/Interactions. Các khả năng riêng như grounding chưa được triển khai.

Mỗi provider giữ key riêng trong Keychain. Để trống key khi sửa sẽ giữ key cũ. Streaming áp dụng cho provider đang chọn. Profile cũ thiếu type được xem là OpenAI compatible.

Chat dùng renderer block native:

- Code có box, header **Code** hoặc ngôn ngữ do model ghi, nút **Copy** sao chép nội dung không kèm fence/header. Không bắt buộc có language tag. Cuộn ngang với dòng dài.
- Bảng Markdown có header, viền từng ô, căn trái/giữa/phải theo delimiter và cuộn ngang khi rộng.
- Đậm/nghiêng, tiêu đề, danh sách, trích dẫn và liên kết vẫn hiển thị trong phần text. Không dùng WebView, không chạy HTML/JS hoặc tự tải ảnh. Chưa hỗ trợ LaTeX và tô màu syntax code.
- Hỗ trợ block đang nhận dở trong streaming. Nội dung Markdown gốc vẫn lưu vào SQLite.

Các chức năng ghim, thứ tự truy cập, vuốt xóa và lịch sử riêng từ 0.4.0 được giữ lại.

Kiểm tra parser trên WSL:

```bash
g++ -std=c++17 -Wall -Wextra -Werror tests/markdown_test.cpp -o /tmp/agenthome-markdown-test
/tmp/agenthome-markdown-test
```

Sau khi cài trên iPhone: kiểm tra chuyển provider, form theo type và Streaming; yêu cầu AI trả về code fence không language tag, code Python và một bảng có ít nhất 3 cột. Kiểm tra Copy bằng cách dán vào ô nhập, cuộn ngang code/bảng, cả chế độ streaming và không streaming. Gemini cần key hợp lệ của người dùng để kiểm thử mạng.

## Đã triển khai

- Nút **Cài đặt** chứa cấu hình API và mục **Device info**. Nút **Quay lại** mở danh sách hội thoại; nút **Mới** tạo hội thoại trống với context riêng. Hội thoại cũ được giữ trong **Hội thoại cũ**, tiêu đề chat mới lấy từ tin đầu tiên.
- App UIKit có icon riêng, bong bóng chat (bạn bên phải, AI bên trái), ô nhập bo góc, nền mờ và nút Dán riêng tránh menu hệ thống gây crash trên thiết bị thử nghiệm.
- Streaming SSE, nút Dừng, trạng thái chờ/trả lời/gọi công cụ; có thể tắt Streaming trong API nếu provider không hỗ trợ. Phần văn bản nhận được trước khi dừng hoặc lỗi mạng được lưu kèm nhãn gián đoạn.
- API tương thích OpenAI Chat Completions, hỗ trợ endpoint tùy chỉnh qua HTTPS và tool calling; model cần hỗ trợ trường `tools`.
- AI được gọi duy nhất công cụ `system_info`, tối đa 3 vòng và 4 lời gọi mỗi vòng. Nút **Thiết bị** gọi cùng công cụ qua IPC.
- Daemon `agenthomed` chạy với UID `mobile`, nhận JSON qua Unix socket, kiểm tra UID đầu bên kia và chỉ cho phép các phương thức định nghĩa sẵn.
- SQLite lưu riêng từng hội thoại, tải tối đa 100 tin gần nhất trong giới hạn khung IPC; giới hạn context gửi API khoảng 16.000 ký tự. API key lưu Keychain, không lưu trong SQLite.
- IPC có giới hạn kích thước và timeout. Không có cổng TCP lắng nghe.

**Chưa triển khai:** scheduler, compact context, memory ngữ nghĩa, phê duyệt quyền tương tác, tool đặc quyền, adapter native Anthropic/Gemini, UI Automation, MCP, Live2D và multi-agent. Runtime dùng allowlist cố định cho tool read-only, chưa phải Risk Engine đầy đủ. Từ 0.7.0 yêu cầu AI và checkpoint chạy trong daemon.

## Build

```bash
export THEOS=/home/luoplayer/theos
make package FINALPACKAGE=1
```

Cần SDK iPhoneOS15.6 và toolchain arm64 trong Theos. Nếu Theos ở vị trí khác, đặt `THEOS` tương ứng. Gói `.deb` xuất hiện trong `packages/`. Không cần Xcode để build bản này.

## Cài và chạy trên iPhone

Thay `PHONE_IP` bằng IP máy. Thiết bị cần đang jailbreak, đã cài OpenSSH. Chép gói mới nhất bằng tên thực tế ở `packages/`:

```bash
scp -O -i ~/.ssh/ulp_iphone packages/dev.agenthome.iphone_0.8.0_iphoneos-arm64.deb mobile@PHONE_IP:/var/mobile/
ssh -i ~/.ssh/ulp_iphone mobile@PHONE_IP
```

Trong shell iPhone, dùng quyền quản trị để cài gói (ví dụ `sudo`, nếu đã cấu hình):

```bash
sudo dpkg -i /var/mobile/dev.agenthome.iphone_0.8.0_iphoneos-arm64.deb
sudo launchctl bootstrap system /var/jb/Library/LaunchDaemons/dev.agenthome.daemon.plist
sudo launchctl kickstart -k system/dev.agenthome.daemon
sudo uicache -p /var/jb/Applications/AgentHome.app
```

Nếu service đã được bootstrap, bỏ qua thông báo “already loaded” và dùng `kickstart`. Gói chưa có script tự bootstrap; các lệnh này là bước cài lần đầu. Đường dẫn `/var/jb` phụ thuộc bootstrap rootless trên thiết bị và cần được xác minh. Sau reboot, kích hoạt lại jailbreak trước khi sử dụng.

Mở **Agent Home**, chọn **API**, nhập base URL (ví dụ `https://host/v1`) hoặc URL đầy đủ đến `/v1/chat/completions`, model ID và API key. Mục **Cài đặt → Device info** kiểm tra daemon mà chưa cần API. Sau đó hỏi AI “Máy còn bao nhiêu dung lượng?” để thử vòng gọi công cụ.

## Nâng cấp 0.3.0 và kiểm tra hội thoại

Sau khi cài gói, khởi động lại daemon để nâng cấp SQLite:

```bash
sudo launchctl kickstart -k system/dev.agenthome.daemon
```

Nếu daemon đang chạy thủ công và chưa được đăng ký với launchd, dừng tiến trình bằng `pkill -x agenthomed`, sau đó chạy `bootstrap` và `kickstart` như bước cài lần đầu. Nếu không restart, app mới sẽ không gọi được `chat.create` / `chat.conversations`.

Kiểm tra: **Quay lại** hiển thị lịch sử cũ; **Mới** mở chat trống; gửi một tin rồi quay lại để thấy tiêu đề; mở hai chat khác nhau để xác nhận nội dung riêng; đóng/mở app để tiếp tục chat đang chọn. **Cài đặt → Device info** hiển thị thông tin thiết bị. Khi đang trả lời hoặc lưu dữ liệu, nút điều hướng tạm khóa; nhấn **Dừng** trước khi đổi chat.

Migration được kiểm tra trên cả database rỗng và schema v0.2 có dữ liệu, bao gồm chạy lại migration và tách lịch sử. `shared/AHDatabase.h` chứa migration và SQL dùng chung với daemon. Bộ kiểm tra host: `tests/database_test.cpp` (cần header SQLite và thư viện SQLite hệ thống).

## Kiểm tra streaming và giao diện

Kiểm tra parser SSE trên WSL, không gọi API:

```bash
g++ -std=c++17 -Wall -Wextra -Werror tests/sse_test.cpp -o /tmp/agenthome-sse-test
/tmp/agenthome-sse-test
```

Trên iPhone sau khi nâng cấp:

1. Mở lại app: lịch sử cũ vẫn còn, tin của bạn căn phải và AI căn trái.
2. Gửi “Viết một đoạn văn tiếng Việt khoảng 200 từ”: kiểm tra chữ hiện dần, dấu và emoji không lỗi.
3. Nhấn Dừng giữa câu trả lời: phần nhận được được đánh dấu `[Đã dừng]`, có thể gửi tin tiếp. Mở lại app để kiểm tra phần đã lưu.
4. Hỏi “Dùng công cụ kiểm tra máy còn bao nhiêu dung lượng”: kiểm tra trạng thái gọi công cụ và kết quả.
5. Tắt Streaming trong API rồi thử lại để kiểm tra chế độ JSON thông thường.

Giới hạn: Dừng hủy request trên thiết bị; provider có thể vẫn tính phí phần đã xử lý. Streaming có thể tới theo cụm nếu proxy buffer dữ liệu. Checkpoint khoảng 0,2 giây, không bảo đảm lưu từng token ngay trước khi daemon bị kill. Reasoning riêng của provider không được hiển thị/lưu.

## Kiểm tra IPC trên thiết bị

Build công cụ kiểm tra trực tiếp bằng cùng UID `mobile` với daemon:

```bash
make -C tests all
scp -i ~/.ssh/ulp_iphone tests/.theos/obj/ahcheck mobile@PHONE_IP:/var/mobile/
ssh -i ~/.ssh/ulp_iphone mobile@PHONE_IP 'chmod 700 /var/mobile/ahcheck; /var/mobile/ahcheck'
```

Binary chép trực tiếp có thể bị Dopamine chặn thực thi (đã gặp mã thoát 137); khi đó cần cài công cụ bằng gói được bootstrap tin cậy trước khi chạy, hoặc kiểm tra qua Cài đặt → Device info trong app. Công cụ kiểm tra đọc thông tin hệ thống, đọc lịch sử và từ chối method ngoài allowlist. Không dùng SSH socket forwarding để kiểm tra xác thực UID: tiến trình sshd kết nối socket có thể mang UID khác `mobile` và bị từ chối.

`tests/ipc_smoke.py` dùng được khi Python chạy trực tiếp cùng UID trên thiết bị. `--write-test` thêm một tin thử vào lịch sử. Kiểm tra thêm: gửi chat, đóng/mở app để kiểm tra lịch sử; thử key sai và daemon dừng để kiểm tra hiển thị lỗi; khởi động lại daemon để kiểm tra SQLite vẫn còn dữ liệu.

## Dữ liệu và phạm vi quyền

Dữ liệu nằm trong `/var/mobile/Library/AgentHome/`, thư mục 0700 và socket 0600. SQLite chưa mã hóa riêng. App chạy ngoài container để dùng socket của daemon; entitlement này cần kiểm chứng trên Dopamine thực tế. Tiến trình khác cùng UID mobile cũng có thể kết nối socket: kiểm tra UID không phải cơ chế cô lập giữa các app jailbreak. Vì vậy bản này chỉ cung cấp tool đọc trạng thái và đọc/ghi hội thoại, tuyệt đối chưa đưa shell/root vào giao thức.

Khi chat, context gửi tới endpoint đã cấu hình; thông tin thiết bị chỉ gửi khi model yêu cầu tool. Keychain dùng `WhenUnlockedThisDeviceOnly`; đây chưa phải hệ thống AI nền khi máy khóa. Không ghi key vào log. Lịch sử tool call trung gian chưa được lưu để replay/audit; chỉ tin user/assistant được lưu.

0.5.2 thêm mốc 12 pt và giữ nguyên cỡ chữ đã chọn khi nâng cấp.
