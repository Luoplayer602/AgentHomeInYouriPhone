# Context window và compact — yêu cầu phải giữ cho các bản tiếp theo

Từ 0.9.0 đã có compact thủ công với preview/activate/discard trên app và web. Auto-compact chưa triển khai. 16.000 ký tự vẫn là ngân sách app, không phải window thực của model.

## Hiện trạng

AHContextSnapshot là nguồn chung cho UI và request: chọn các tin gần nhất trong ngân sách 16.000 ký tự UTF-16. Daemon trả tổng số tin của hội thoại để hiển thị cả phần nằm ngoài số tin tải lên. AHPromptContext dùng chung giữa dựng request và ước lượng. Có window do người dùng khai báo, output reservation và ước lượng UTF-8 bytes/4 gồm system/tool schema. Chưa có tokenizer đúng model. Usage thực được lưu khi provider trả về (API chat cuối). Tool outputs được thêm trong runtime nhưng ước lượng lượt tiếp chưa tính các output tương lai.

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

Schema compactions giữ state running/ready/active/superseded/failed/discarded, end_id/source_hash/base_id, summary, provider/model, before/after chars, schema_version. Hash nguồn được đọc theo từng hàng để hạn chế RAM. Candidate tối đa 6.000 ký tự và phải giảm chi phí nội dung trước khi ready. Dữ liệu source luôn gửi với vai trò user, system prompt yêu cầu giữ quyết định/ràng buộc/việc đang làm và bỏ secrets. API key hiện tại được redaction trực tiếp; các bí mật khác cần người dùng kiểm tra trong preview.

Cần làm tiếp: tokenizer theo provider/model, usage tổng hợp qua mọi tool round, cửa sổ compact điều chỉnh theo model thay vì cap ký tự, auto-compact tùy chọn, semantic regression/evals trên provider thật. Chưa bật tự động hoặc coi model-generated summary là chính sách cấp quyền.
