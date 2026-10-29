# Kiến trúc và bước kế tiếp

```text
UIKit app (mobile, ngoài container)
  ├─ Preferences + Keychain → cấu hình provider
  └─ Unix socket → agenthomed (mobile, launchd)
                    ├─ AHAgentRuntime → AHProvider → HTTPS (SSE/JSON)
                    │                    └─ Keychain access group chung
                    ├─ system.info (allowlist read-only)
                    └─ SQLite → conversations/messages/tasks/events/ai_runs
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

0.6.0 bổ sung task queue đọc-only trong daemon: AHTasks.h chứa schema, transition có điều kiện và audit transaction dùng chung với test host. Task được thực thi sau khi gửi phản hồi nhận hàng và xử lý khi daemon restart, không phụ thuộc vòng đời app. Runtime này chưa chạy model. AHContextSnapshot là nguồn duy nhất cho ngân sách tin nhắn gửi đi và chỉ báo ◉; compact được ghi thành yêu cầu riêng trong context-compaction.md.

0.7.0: AHAgentRuntime chạy trên main queue daemon; socket accept/read trên một queue nền và dispatch request về main để SQLite không bị truy cập đồng thời. NSURLSession callbacks cùng main queue, có run loop dispatch_main. ai_runs lưu metadata/context/partial/round; Keychain dùng access group dev.agenthome.app được ký vào daemon. App không còn chứa vòng gọi provider, chỉ submit/poll/cancel. Các chat.ai running không thuộc recovery tự retry của system.info. Recovery thất bại AI + transcript partial dùng transaction; kiểm tra SQL thực trong runtime_db_test.py.
