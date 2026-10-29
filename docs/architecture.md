# Kiến trúc và bước kế tiếp

```text
UIKit app (mobile, ngoài container)
  ├─ AHProvider → HTTPS → API tương thích OpenAI (SSE hoặc JSON, tool calling)
  │    └─ core/stream/SSEDecoder.hpp → framing dữ liệu theo byte, giới hạn kích thước
  ├─ Keychain → API key
  └─ Unix socket → agenthomed (mobile, launchd)
                    ├─ allowlist: system.info / chat.list / chat.append / chat.create / chat.conversations
                    ├─ statvfs + NSProcessInfo
                    └─ SQLite → conversations + messages (conversation_id)
```

`shared/AHProtocol.h` xác định framing và đường dẫn. Mỗi kết nối có một JSON request/response kết thúc bằng newline; `id` phải khớp. Params phải là object. Method chưa đăng ký bị từ chối. `system.info` là tool rủi ro 0; tool ghi duy nhất là lưu tin user/assistant và không nhận SQL tùy ý.

Lộ trình tiếp theo sau khi kiểm tra thiết bị:

1. Provider HTTP/SSE đã tách sang AHProvider; tiếp tục tách agent loop khỏi view controller. Streaming, hủy request và UI chat hai phía đã có từ 0.2.0.
2. Chuyển vòng thực thi sang runtime nền, thêm task ID, checkpoint, trạng thái lỗi/retry và giới hạn tài nguyên.
3. Bổ sung schema tool, policy engine độc lập, xác nhận gắn với tham số hành động, audit và chống thực thi lặp.
4. Chỉ thêm helper đặc quyền khi một tool thật sự cần, đồng thời thay xác thực cùng UID bằng cơ chế nhận diện client phù hợp.
5. Adapter nền theo từng app trước; UI Automation, MCP và pet sau.

Chưa kết luận khả năng hoạt động khi khóa máy, tương thích entitlement và RAM trước khi đo trên iPhone thật. Không sử dụng dữ liệu nội bộ ứng dụng khác trong bản foundation này.

Từ 0.3.0, app có navigation stack: danh sách hội thoại → chat; Cài đặt chứa cấu hình API và Device info. Daemon migrate schema cũ trong transaction, gắn tin cũ vào `legacy`, tạo index theo conversation_id và bật foreign keys. App truyền conversation_id trong IPC; field này không gửi vào message cho provider. chat.list thiếu ID vẫn đọc legacy để tương thích công cụ kiểm tra cũ. Nâng cấp daemon cần restart.

Từ 0.4.0: AHProfiles giữ metadata provider trong preferences, API key theo account riêng trong Keychain (profile legacy tiếp tục dùng account api-key). Request chụp cấu hình active lúc gửi để tránh đổi provider giữa vòng tool call. AHMarkdown dùng parser inline của Foundation và style block native; không dùng WebView. Schema v2 thêm pinned/accessed_at; chat.touch, chat.pin và chat.delete chỉ do UI gọi, không cung cấp cho model.

Từ 0.5.0: AHSettings (grouped table) → AHSavedProviders → AHProviderTypes/AHProviderEditor; AHInput tách riêng để dùng lại trong form. Type `compatible` cho endpoint tùy chỉnh; type `gemini` preset Google compatibility endpoint. AHChatContent dựng các block text/code/table từ core/format/MarkdownBlocks.hpp, code Copy chỉ ghi UIPasteboard theo thao tác người dùng. Bảng dùng UILabel thay vì nhiều UITextView để giảm bộ nhớ. Parser được kiểm tra độc lập trên Linux.
