# Context window và compact — yêu cầu phải giữ cho các bản tiếp theo

Người dùng yêu cầu chỉ báo context và khả năng compact. Bản 0.6.0 chỉ hiển thị ngân sách ký tự hiện hành; không có compact tự động và không khẳng định 16.000 ký tự là cửa sổ context của model.

## Hiện trạng

AHContextSnapshot là nguồn chung cho UI và request: chọn các tin gần nhất trong ngân sách 16.000 ký tự UTF-16. Daemon trả tổng số tin của hội thoại để hiển thị cả phần nằm ngoài số tin tải lên. System prompt, tool schemas, tool outputs và output reservation chưa được tính. Provider/model có thể có cửa sổ khác nhau; hiện chưa lưu cấu hình giới hạn token và chưa có tokenizer. Số % không phải token usage chính xác.

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
