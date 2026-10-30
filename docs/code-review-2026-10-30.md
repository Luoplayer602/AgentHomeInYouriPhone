# Rà soát mã nguồn — 2026-10-30

Phạm vi: toàn bộ repo ở commit `d8f9d1d` (v0.14.0), nhánh rà soát `cline/39tr0zft`.

## 1. Phương pháp và mức độ tin cậy

| Việc đã làm | Kết quả |
| --- | --- |
| Đọc toàn bộ `daemon/`, `app/`, `shared/`, `core/` (3.0k dòng ObjC/C++/SQL) | Có |
| Chạy 16 test host (C++/Python/JS) + `scripts/check_sources.py` | 16 pass, 1 skip (test thiết bị) |
| Thử tải `std::regex` trong `core/context/Memory.hpp` bằng input 64 KB (lo ngại backtracking) | Không treo: 1–4 ms cho mọi mẫu |
| Grep SQL nối chuỗi (`stringWithFormat:` + SELECT/INSERT/UPDATE/DELETE) | Không có; toàn bộ dùng bind tham số |
| Grep log lộ key (`NSLog`) | Chỉ 2 chỗ, chỉ log tên method/exception |

**Giới hạn quan trọng:** host không có Foundation/UIKit/IOKit nên **không biên
dịch được `.m/.mm`**. Các nhận định về ObjC dưới đây là đọc mã + suy luận luồng
chạy, không phải kết quả chạy thực tế trên thiết bị. Phần C++/SQL/JS đã được
kiểm chứng bằng test chạy thật.

## 2. Tóm tắt

| Mức | Số lượng | Ghi chú |
| --- | --- | --- |
| Cao | 2 | Bề mặt mạng của Webview, cạn slot SSE |
| Trung bình | 7 | Giao dịch xoá hội thoại, chẩn đoán khởi động, đường dẫn cứng, tài liệu lệch version, cấu trúc thư mục |
| Thấp | 5 | Hiệu năng IPC, giới hạn phiên, NULL column, hardcode THEOS, test phụ thuộc CWD |

Điểm tích cực đáng ghi nhận: ranh giới bảo mật của daemon (UID peer, allowlist
method, bind tham số, giới hạn kích thước ở mọi biên) được làm nhất quán và có
test; phần compaction/checkpoint dùng transaction + partial unique index đúng.

## 3. Phát hiện chi tiết

### F1 — Webview lắng nghe trên mọi interface (Cao)

`daemon/AHWebServer.mm:87` bind `INADDR_ANY`, nên khi bật Webview, port mở trên
Wi‑Fi/LAN/cellular chứ không chỉ loopback. Kết hợp với chế độ công khai (mật
khẩu trống → `AHWebServer authorized:` trả `YES`, `AHWebServer.mm:99-103`), bất
kỳ ai trong cùng mạng đọc được toàn bộ hội thoại, checkpoint memory và (nếu bật
tương tác) gửi tin làm tiêu tốn phí API.

README cảnh báo về mật khẩu trống nhưng **không** nói phạm vi bind. Đề xuất:

```objc
// Mặc định chỉ loopback; chỉ mở LAN khi người dùng chọn rõ trong Cài đặt.
address.sin_addr.s_addr = htonl(self.exposeToLAN ? INADDR_ANY : INADDR_LOOPBACK);
```

hoặc bắt buộc mật khẩu khi `enabled` và port != loopback.

### F2 — Kết nối SSE chiếm hết slot phục vụ (Cao)

`AHWebServer.mm:89` tạo đúng 8 slot; `serve:` với `/api/events` giữ slot trong
vòng lặp 60 tick × 500 ms = 30 s (`:174-182`). Tám client mở `/api/events` là
toàn bộ HTTP (kể cả `/api/login`, `/api/messages`) bị từ chối trong 30 s, lặp
lại được. Trong chế độ công khai đây là DoS tầm LAN.

Đề xuất: pool riêng cho SSE (ví dụ 2 slot), hoặc trả `503` + `Retry-After` thay
vì đóng socket im lặng (`:94`), và rút ngắn vòng đời stream.

### F3 — Khởi động thất bại không để lại dấu vết (Trung bình)

`daemon/main.m:198-215` trả mã 1/2/3/4/6 mà không `NSLog` gì; launchd chỉ
`KeepAlive` + `ThrottleInterval 10`, nên trên thiết bị biểu hiện chỉ là "app
không kết nối được daemon". Đây là loại lỗi đã từng gặp (crash đọc Context ở
0.9.1). Đề xuất log một dòng trước mỗi `return` (không log params/key), ví dụ
`NSLog(@"agenthomed: migrate failed rc=%d", rc)`.

### F4 — `chat.delete` commit trước khi kiểm tra kết quả (Trung bình)

`daemon/main.m:70-86`: DELETE messages + DELETE conversation nằm trong
transaction, nhưng `COMMIT` ở `:82` xảy ra **trước** khi `:85` kiểm tra
`!changed`. Nếu conversation không tồn tại, dữ liệu đã commit nhưng client nhận
lỗi. Thêm nữa, `DELETE FROM context_settings` ở `:86` chạy **sau** commit, nên
nếu bước này lỗi thì cấu hình context mồ côi (không còn conversation).

Đề xuất: đưa cả ba câu lệnh vào cùng transaction, kiểm tra `changed` trước
`COMMIT`, rollback nếu `changed == 0`.

### F5 — `AHClient` không kiểm tra `socket()` (Trung bình)

`app/AHClient.m:10-20`: nếu `socket()` trả `-1`, code vẫn gọi `setsockopt(-1,…)`,
`connect(-1,…)` rồi `close(-1)`; thông báo lỗi chỉ là "Không kết nối được
daemon". Đề xuất:

```objc
int fd = socket(AF_UNIX, SOCK_STREAM, 0);
if (fd < 0) { /* trả lỗi rõ ràng, không gọi setsockopt */ }
```


### F6 — Status line HTTP không chuẩn (Trung bình)

`AHWebServer.mm:18` sinh `HTTP/1.1 200 Response`. Reason phrase là tuỳ chọn theo
RFC 7230 nên trình duyệt/`curl` chấp nhận, nhưng client strict và log của người
dùng sẽ khó đọc. Đề xuất map mã → cụm chuẩn (`200 OK`, `401 Unauthorized`,
`429 Too Many Requests`, …).

### F7 — Đường dẫn `index.html` hardcode (Trung bình)

`AHWebServer.mm:123` đọc `/var/jb/usr/share/agenthome/index.html`. Đúng với
`THEOS_PACKAGE_SCHEME = rootless` hiện tại, nhưng nếu đổi scheme (layout
roothide/palera1n khác) hoặc chạy daemon ngoài gói, Webview trả 500 mà không nói
lý do. Đề xuất macro `AHSharePath` trong `shared/AHProtocol.h` (đã có
`AHDataPath`) hoặc dò lần lượt `/var/jb/...` → `/usr/share/...`.

### F8 — Tài liệu lệch phiên bản (Trung bình)

`README.md:3` ghi "nền tảng v0.9.1" và mục mới nhất là 0.9.1, trong khi
`control:3` và `app/Resources/Info.plist` là **0.14.0**. Người mới đọc README sẽ
không thấy Webview public mode, memory, compaction tự động. `make check` đã in
cảnh báo cho tình trạng này (không fail build).

### F9 — `THEOS` hardcode đường dẫn cá nhân (Trung bình)

`Makefile:10` `THEOS ?= /home/luoplayer/theos`. Máy khác phải export `THEOS`;
nếu quên, lỗi là "No such file or directory: /home/luoplayer/..." khó hiểu. Đề
xuất `THEOS ?= $(HOME)/theos` và thêm kiểm tra:

```make
ifeq ($(wildcard $(THEOS)/makefiles/common.mk),)
$(error Không thấy Theos tại $(THEOS); export THEOS=/duong/dan/theos)
endif
```

### F10 — `app/` chứa source chỉ dùng cho daemon (Trung bình)

`app/AHProvider.mm`, `app/AHPrompt.m`, `app/AHProfiles.m`, `app/AHContext.m`,
`app/AHProviderConfig.m` không có trong `app/Makefile` mà chỉ được
`daemon/Makefile` biên dịch. Nhìn cây thư mục rất dễ tưởng đây là code của app
và sửa sai chỗ. Đề xuất chuyển sang `shared/` (hoặc `agent/`) và giữ `app/` chỉ
cho UI. `scripts/check_sources.py` hiện chấp nhận tình trạng này (chỉ báo lỗi
khi file không được build ở bất kỳ target nào).

### F11 — Test Python phụ thuộc thư mục làm việc (Trung bình)

`tests/compaction_test.py:5`, `tests/context_pipeline_test.py:4`,
`tests/runtime_db_test.py` dùng `Path('daemon/AHCompaction.m')`, nên chỉ đúng khi
chạy từ repo root. Chạy `cd tests && python3 compaction_test.py` sẽ
`FileNotFoundError` khó hiểu. Đề xuất tính gốc repo từ `__file__`:

```python
ROOT = Path(__file__).resolve().parents[1]
```

(`run-host-tests.sh` đã `cd` về root nên CI không gặp lỗi này.)

### F12 — Code test nằm trong binary phát hành (Thấp)

`daemon/Makefile` biên dịch `../tests/AHMemoryChecks.m` và
`../tests/AHContextChecks.m` vào `agenthomed`. Đây là chủ ý (cờ
`--self-test-*`), nhưng code test đi theo gói và thêm bề mặt. Nếu giữ, nên ghi
rõ trong tài liệu (đã thêm) và không đặt dữ liệu nhạy cảm trong đó.

### F13 — IPC đọc từng byte (Thấp)

`daemon/main.m:152-156` đọc 1 byte/lần, tối đa `AHMaxFrame` = 2 MB → tối đa 2
triệu syscall cho một request. Chỉ tiến trình cùng UID mới kết nối được nên rủi
ro thực tế thấp, nhưng nên đọc theo buffer 4 KB + `memchr('\n')` giống
`app/AHClient.m`, hoặc hạ `AHMaxFrame` cho khớp mức dùng thật (`chat.list` đã bị
chặn 512 KB ở `main.m:113`).

### F14 — Giới hạn phiên và chống dò mật khẩu có thể reset (Thấp)

`AHWebServer.mm:136` xoá toàn bộ bộ đếm khi có hơn 256 địa chỉ; `:140` xoá toàn
bộ session khi đạt 64 (mọi người bị đăng xuất). Hợp lý cho thiết bị cá nhân,
nhưng kẻ tấn công nhiều IP có thể reset bộ đếm dò mật khẩu. Nếu Webview mở rộng,
nên dùng bộ đếm có TTL.

### F15 — `@((const char *)sqlite3_column_text(...))` với NULL (Thấp)

`daemon/main.m:45,61,111`, `AHMemorySearch.mm:46` tạo `NSString` từ con trỏ C có
thể là `NULL` → `NSException`. Hiện các cột liên quan đều `NOT NULL` nên chưa
xảy ra, nhưng một migration thêm cột nullable là đủ để crash vòng poll của app.
Nên thêm helper `AHText(stmt, i)` trả `@""` khi `NULL` (vài chỗ đã làm đúng, ví
dụ `AHHistory.h:12`).

## 4. Điểm mạnh đã kiểm chứng

- **Không có SQL injection**: toàn bộ truy vấn dùng `sqlite3_bind_*`; không có
  câu SQL nào ghép chuỗi từ input (grep `stringWithFormat:` + `SELECT/INSERT/UPDATE/DELETE`).
- **IPC**: `getpeereid` so UID (`main.m:148-149`), allowlist method, frame 2 MB,
  timeout 5 s, exception boundary chỉ log tên method (`:166`).
- **API key**: chỉ trong Keychain; không vào SQLite; `AHProvider` chặn redirect
  khác origin hoặc downgrade scheme (`app/AHProvider.mm:57-62`); key được redact
  khi ghi event và khi gửi cho summarizer (`AHCompaction.m:21,28`).
- **Giới hạn kích thước** nhất quán: HTTP 80 KB header / 64 KB body, SSE 256 KB,
  message 64 KB, response provider 2 MB, reasoning 64 KB, `chat.list` 512 KB.
- **Compaction**: hash nguồn SHA-256, `end_id`, base snapshot, transaction +
  `CREATE UNIQUE INDEX ... WHERE state='active'`, không tự activate khi lỗi.
- **Test**: 16 test host chạy SQL thật, phủ migration từ schema 0/1/2, recovery
  sau restart, partial output; test JS chạy trên `index.html` thật.

## 5. Đã làm trong lần rà soát này

Chỉ thêm hạ tầng phát triển, **không sửa logic sản phẩm**:

- `Makefile`: thêm `env`, `test`, `check`, `clean-host`; chỉ include Theos khi
  build gói.
- `scripts/dev-env.sh`: dò toolchain, tự tải SQLite amalgamation 3.45.3 (ghim
  SHA-256) khi máy thiếu header, sinh `.build/env.mk`.
- `scripts/run-host-tests.sh`: chạy toàn bộ test C++/Python/JS + repo check, log
  riêng từng test, skip test thiết bị.
- `scripts/check_sources.py`: bắt file thiếu trong `*_FILES`, source bị bỏ quên,
  `#import` sai, lệch version `control`/`Info.plist`, asset JSON/plist hỏng.
- `docs/ci-host-tests.yml`: cấu hình CI 2 job (SQLite hệ thống / amalgamation),
  copy sang `.github/workflows/` để bật.
- `scripts/check-toolchain.sh` + `make doctor`: kiểm tra Theos, clang/aarch64,
  iOS SDK, `ldid`, `dpkg-deb` trước khi `make package` (host này không có Theos).
- `docs/development.md`: hướng dẫn môi trường, ranh giới host, xử lý sự cố.
- `.gitignore`: thêm `.build/`, `.deps/`, `*.pyc`.

## 6. Đề xuất thứ tự xử lý

1. F1 + F2 (bề mặt mạng Webview) — trước khi phát hành bản có Webview bật.
2. F3 + F4 (chẩn đoán khởi động và tính nguyên tử của `chat.delete`).
3. F8 + F9 (tài liệu/version, đường dẫn Theos) — rẻ, ảnh hưởng người dùng mới.
4. F5, F10, F11 (chất lượng mã và test) khi có dịp sửa các file đó.
5. F6, F7, F12–F15 khi refactor gần khu vực liên quan.

