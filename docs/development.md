# Môi trường phát triển và kiểm thử

Tài liệu này mô tả môi trường chạy được **trên host** (Linux, macOS, WSL2) — không
cần Theos, không cần iPhone. Mục tiêu: mọi thay đổi logic C++/SQL/JS đều có thể
kiểm chứng trước khi build gói và cài lên thiết bị.

## 1. Bắt đầu nhanh

```bash
git clone <repo> && cd AgentHomeInYouriPhone
make env     # kiểm tra toolchain, tải SQLite nếu máy chưa có header
make test    # chạy toàn bộ kiểm thử host
make check   # kiểm tra tính nhất quán của repo
```

Kết quả mong đợi ở lần chạy đầu:

```text
Agent Home — kiểm thử host (SQLite: bundled)

PASS  repo-checks
PASS  compact_budget_test
...
Kết quả: 16 pass, 1 skip, 0 fail
Tất cả kiểm thử host đều đạt.
```

`brew`/`apt` đều **không bắt buộc**: nếu thiếu header SQLite, `make env` tải
SQLite amalgamation bản ghim (3.45.3, kiểm tra SHA-256) vào `.deps/` và dùng thư
viện đó cho test C++.

## 2. Yêu cầu

| Thành phần | Bắt buộc | Dùng cho |
| --- | --- | --- |
| `g++` hoặc `clang++` (C++17) | có | toàn bộ test C++ trong `tests/*.cpp` |
| `gcc`/`clang` (C) | có | chỉ để dò/biên dịch SQLite amalgamation |
| `python3` >= 3.8 | có | test SQL (`tests/*.py`), `scripts/check_sources.py` |
| `make` | có | `make env/test/check` |
| `node` | không | `tests/web_ui_test.js` (bỏ qua nếu thiếu) |
| `perl` | không | `tests/ipc_smoke.pl` — chỉ chạy trên thiết bị |
| Theos + macOS/WSL2 | không | chỉ `make package` |

Không cần root. Mọi artifact nằm trong `.build/` và `.deps/` (đã gitignore).

## 3. Các lệnh

| Lệnh | Việc làm |
| --- | --- |
| `make env` | in toolchain, chọn SQLite hệ thống hoặc amalgamation, sinh `.build/env.mk` |
| `make test` | chạy toàn bộ test host, log từng test ở `.build/tests/*.log` |
| `./scripts/run-host-tests.sh -v` | như trên + in log của test đạt |
| `make check` | chạy riêng `scripts/check_sources.py` |
| `make doctor` | kiểm tra Theos, clang, iOS SDK, `ldid` trước khi build gói |
| `make clean-host` | xoá `.build/` (giữ `.deps/` để không tải lại SQLite) |
| `make package FINALPACKAGE=1` | build `.deb` bằng Theos (không dùng trên host thuần) |

Biến môi trường hữu ích:

| Biến | Ý nghĩa |
| --- | --- |
| `CXX`, `CC` | chọn trình biên dịch khác |
| `AH_FORCE_BUNDLED_SQLITE=1` | bỏ qua SQLite hệ thống, luôn dùng amalgamation |
| `AH_SQLITE_URL`, `AH_SQLITE_SHA256` | dùng mirror/nội bộ cho amalgamation |
| `AH_DEVICE=1` | bật `tests/ipc_smoke.py` (chỉ khi chạy trên iPhone) |
| `THEOS` | đường dẫn Theos khi build gói |


## 4. Kiểm thử host phủ những gì

| Test | Nội dung |
| --- | --- |
| `tests/sse_test.cpp` | `core/stream/SSEDecoder.hpp`: mọi ranh giới chunk, UTF-8, BOM, CR/LF/CRLF, comment, EOF, giới hạn 256 KB |
| `tests/http_test.cpp` | `core/web/HTTP.hpp`: framing, header trùng, chunked bị từ chối, Host/Origin, cookie, CSRF |
| `tests/markdown_test.cpp` | `core/format/MarkdownBlocks.hpp`: code fence (có/không language), bảng, căn cột, pipe escape, fence dở khi streaming |
| `tests/memory_test.cpp` | `core/context/Memory.hpp`: bằng chứng bắt buộc, nhãn credential, tra `selection_id` chính xác |
| `tests/search_test.cpp` | `core/context/Search.hpp`: chấm điểm truy vấn memory |
| `tests/context_budget_test.cpp`, `tests/compact_budget_test.cpp` | `core/context/Budget.h`, `Compaction.h`: ngân sách token/byte, chống tràn số |
| `tests/database_test.cpp` | `shared/AHDatabase.h`: migration từ schema cũ, idempotence, giữ lịch sử, cascade |
| `tests/tasks_test.cpp` | `shared/AHTasks.h`: enqueue, audit event, chuyển trạng thái có guard, recovery sau restart |
| `tests/compaction_test.py` | SQL thật của `daemon/AHCompaction.m`: activate/drop/cancel, rollback, giữ prefix |
| `tests/runtime_db_test.py` | SQL của runtime: enqueue/complete nguyên tử, dedupe usage, recovery không replay |
| `tests/context_pipeline_test.py` | usage theo round, cô lập provider, intent auto-compact bền vững, cascade xoá |
| `tests/compaction_eval_test.py`, `tests/compaction_identifiers_test.py` | scorer và regression chất lượng summary (offline, dùng fixture) |
| `tests/web_ui_test.js` | JavaScript thật của `layout/usr/share/agenthome/index.html` với DOM tối giản |
| `scripts/check_sources.py` | file trong `*_FILES` tồn tại, không có source bị bỏ quên, `#import` cục bộ đúng, version khớp, asset hợp lệ |

Test Python đọc mã nguồn `.m` để lấy đúng câu SQL rồi chạy trên SQLite — vì vậy
chúng bắt được lệch schema, nhưng **không** thay thế được build/biên dịch ObjC.

## 5. Ranh giới: những gì host KHÔNG kiểm tra được

Foundation/UIKit, Keychain, IOKit, quyền entitlements, launchd và entropy của
thiết bị chỉ có trên iOS. Trên host không biên dịch được `.m/.mm`, nên:

- Lỗi biên dịch ObjC (selector sai, thiếu framework) chỉ lộ khi `make package`.
- Hành vi Keychain/NSURLSession/UI phải kiểm tra trên iPhone theo README.
- Daemon có sẵn self-test chạy trên thiết bị:

```bash
agenthomed --self-test-memory    # tests/AHMemoryChecks.m
agenthomed --self-test-context   # tests/AHContextChecks.m
```

- Smoke test IPC (cần daemon thật):

```bash
AH_DEVICE=1 python3 tests/ipc_smoke.py        # chỉ đọc
ssh -i ~/.ssh/ulp_iphone mobile@PHONE_IP 'perl -' < tests/ipc_smoke.pl
```

## 6. Build gói (Theos)

Build gói **không** dùng target host: cần Theos + clang cross-compile + iOS SDK
+ `ldid`. Kiểm tra trước bằng một lệnh:

```bash
export THEOS=$HOME/theos          # hoặc đường dẫn Theos của bạn
make doctor                       # liệt kê chính xác thứ còn thiếu
make package FINALPACKAGE=1
```

`make doctor` kiểm tra: Theos (`makefiles/common.mk`), clang + target aarch64,
`$THEOS/sdks/iPhoneOS*.sdk`, `ldid`, `dpkg-deb`, `fakeroot` (Linux), `make`,
`git`, và cấu hình rootless của repo. Thoát mã 1 nếu chưa đủ điều kiện build.

`make` không tham số hoặc `make package` sẽ include Theos như cũ; `make env`,
`make test`, `make check`, `make doctor`, `make clean-host` **không** đụng tới
Theos, nên chạy được trên Linux CI và trong container.


## 7. CI

`.github/workflows/host-tests.yml` chạy 2 job trên `ubuntu-24.04`:

1. **SQLite hệ thống** — dùng `libsqlite3-dev` có sẵn của runner.
2. **SQLite amalgamation** — `AH_FORCE_BUNDLED_SQLITE=1`, kiểm tra nhánh không
   phụ thuộc gói hệ thống.

Cả hai chạy `make env`, `make check`, `make test`; test cần thiết bị tự động skip.

Cấu hình sẵn ở `docs/ci-host-tests.yml` (chưa đặt trong `.github/workflows/` để
tránh xung đột quyền của token tạo commit). Bật CI bằng một lệnh:

```bash
mkdir -p .github/workflows
cp docs/ci-host-tests.yml .github/workflows/host-tests.yml
git add .github/workflows/host-tests.yml && git commit -m "ci: host tests"
```

Lần đẩy đầu tiên cần token có quyền `workflows` (hoặc bật workflow trong
GitHub UI bằng tay).


## 8. Xử lý sự cố

| Hiện tượng | Nguyên nhân / cách xử lý |
| --- | --- |
| `fatal error: sqlite3.h: No such file` | Chạy `make env` (tự tải amalgamation) hoặc cài `libsqlite3-dev`/`brew install sqlite`. |
| `SHA-256 ... không khớp` | Proxy làm hỏng tệp tải; chạy lại hoặc đặt `AH_SQLITE_URL` nội bộ. |
| Test Python báo `FileNotFoundError: daemon/...` | Phải chạy từ repo root; `run-host-tests.sh` đã `cd` về root. |
| `SKIP web_ui_test` | Không có `node` trong PATH. |
| `FAIL repo-checks` | Đọc thông báo: thường là file mới chưa thêm vào `*_FILES`, hoặc `#import` sai đường dẫn. |
| `make package` báo thiếu Theos | Build gói cần Theos; các target host vẫn dùng được. |

## 9. Thêm test mới

1. Test C++ thuần (parser, budget, SQL không ObjC): thêm `tests/<ten>_test.cpp`
   với `int main()` trả 0 và in `PASS ...`; `make test` tự nhận (glob `tests/*.cpp`).
2. Test SQL của daemon: thêm `tests/<ten>_test.py`, đọc câu SQL từ file `.m`
   (giữ nguyên cách làm hiện tại) và chạy trên SQLite in-memory.
3. Test cần thiết bị: đặt tên có tiền tố `ipc_` và bỏ qua trừ khi `AH_DEVICE=1`.

Không commit `.build/`, `.deps/`, `__pycache__/`.
