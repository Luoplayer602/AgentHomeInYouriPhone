#!/usr/bin/env bash
# Chuẩn bị môi trường phát triển/kiểm thử trên host (Linux, macOS, WSL2).
#
#   ./scripts/dev-env.sh            # kiểm tra toolchain + tải SQLite nếu cần
#   ./scripts/dev-env.sh --check    # chỉ kiểm tra, không tải/biên dịch gì
#   ./scripts/dev-env.sh --force    # tải lại và biên dịch lại SQLite
#   ./scripts/dev-env.sh --quiet    # chỉ in cảnh báo/lỗi
#
# Không cần quyền root: nếu máy chưa có header SQLite (libsqlite3-dev),
# script tải SQLite amalgamation bản ghim vào .deps/ và dùng cho test C++.
# Kết quả ghi vào .build/env.mk để run-host-tests.sh đọc lại.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"
DEPS="$ROOT/.deps"
ENV_MK="$BUILD/env.mk"

# SQLite 3.45.3 (2024-04-15), bản amalgamation chính thức của sqlite.org.
SQLITE_VERSION=3450300
SQLITE_ZIP="sqlite-amalgamation-$SQLITE_VERSION.zip"
SQLITE_URL="${AH_SQLITE_URL:-https://www.sqlite.org/2024/$SQLITE_ZIP}"
SQLITE_SHA256="${AH_SQLITE_SHA256:-ea170e73e447703e8359308ca2e4366a3ae0c4304a8665896f068c736781c651}"
SQLITE_SRC="$DEPS/sqlite-amalgamation-$SQLITE_VERSION"

QUIET=0 FORCE=0 CHECK_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=1 ;;
        --force) FORCE=1 ;;
        --check) CHECK_ONLY=1 ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'Tham số không hỗ trợ: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*" >&2; }
die()  { printf '  fail  %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

say "Agent Home — môi trường host ($ROOT)"

# ---------------------------------------------------------------- toolchain
CXX="${CXX:-}"
if [ -z "$CXX" ]; then
    for candidate in g++ clang++; do
        if have "$candidate"; then CXX="$candidate"; break; fi
    done
fi
[ -n "$CXX" ] && have "$CXX" || die "Thiếu trình biên dịch C++ (cài g++ hoặc clang++)."
ok "C++      $CXX — $("$CXX" --version 2>/dev/null | head -1)"

CC="${CC:-}"
if [ -z "$CC" ]; then
    for candidate in cc gcc clang; do
        if have "$candidate"; then CC="$candidate"; break; fi
    done
fi
[ -n "$CC" ] && have "$CC" || die "Thiếu trình biên dịch C (cài gcc hoặc clang)."
ok "C        $CC — $("$CC" --version 2>/dev/null | head -1)"

have make || die "Thiếu make."
ok "make     $(make --version 2>/dev/null | head -1)"

have python3 || die "Thiếu python3 (>= 3.8)."
python3 -c 'import sqlite3, json, zipfile' 2>/dev/null \
    || die "python3 thiếu module sqlite3/json/zipfile."
ok "python3  $(python3 --version 2>&1) — module sqlite3 sẵn sàng"

if have node; then
    ok "node     $(node --version 2>&1) — dùng cho test web UI"
else
    warn "Không có node: test web UI (tests/web_ui_test.js) sẽ bị bỏ qua."
fi

if have perl; then
    ok "perl     $(perl -e 'print $^V' 2>/dev/null) — chỉ cần cho smoke test trên thiết bị"

# ------------------------------------------------------------------- sqlite
# Ưu tiên SQLite của hệ thống; nếu thiếu header/thư viện thì dùng amalgamation.
probe_system_sqlite() {
    local dir probe
    dir="$(mktemp -d 2>/dev/null || mktemp -d -t ahprobe)"
    probe="$dir/probe.c"
    printf '#include <sqlite3.h>\nint main(void){return sqlite3_libversion_number()>0?0:1;}\n' >"$probe"
    # Chỉ cần biên dịch + link được; không chạy thử để tránh phụ thuộc LD_LIBRARY_PATH.
    if "$CC" "$probe" -lsqlite3 -o "$dir/probe" >/dev/null 2>&1; then
        rm -rf "$dir"; return 0
    fi
    rm -rf "$dir"; return 1
}

download() { # url, destination
    local url="$1" dest="$2"
    if have curl; then
        curl -fsSL --retry 3 --connect-timeout 20 -o "$dest" "$url" && return 0
    elif have wget; then
        wget -q -O "$dest" "$url" && return 0
    fi
    python3 - "$url" "$dest" <<'PY'
import sys, urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=60) as response, open(sys.argv[2], 'wb') as handle:
    handle.write(response.read())
PY
}

sha256_of() {
    if have sha256sum; then sha256sum "$1" | cut -d' ' -f1
    elif have shasum; then shasum -a 256 "$1" | cut -d' ' -f1
    else python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
    fi
}

ensure_sqlite_source() {
    if [ -f "$SQLITE_SRC/sqlite3.c" ] && [ -f "$SQLITE_SRC/sqlite3.h" ] && [ "$FORCE" = 0 ]; then
        ok "sqlite   amalgamation $SQLITE_VERSION (đã có trong .deps/)"
        return 0
    fi
    [ "$CHECK_ONLY" = 1 ] && die "Thiếu SQLite: chạy ./scripts/dev-env.sh để tải (hoặc cài libsqlite3-dev)."
    mkdir -p "$DEPS"
    local zip="$DEPS/$SQLITE_ZIP"
    say "  ..    tải $SQLITE_URL"
    if [ "$FORCE" = 1 ] || [ ! -f "$zip" ]; then
        download "$SQLITE_URL" "$zip" || die "Không tải được SQLite. Kiểm tra mạng hoặc đặt AH_SQLITE_URL."
    fi
    local actual
    actual="$(sha256_of "$zip")"
    if [ "$actual" != "$SQLITE_SHA256" ]; then
        rm -f "$zip"
        die "SHA-256 của $SQLITE_ZIP không khớp (nhận $actual). Đã xoá tệp tải về."
    fi
    python3 -m zipfile -e "$zip" "$DEPS" 2>/dev/null \
        || { have unzip && unzip -q -o "$zip" -d "$DEPS"; } \
        || die "Không giải nén được $SQLITE_ZIP."
    [ -f "$SQLITE_SRC/sqlite3.c" ] || die "Giải nén SQLite không tạo ra $SQLITE_SRC/sqlite3.c."
    ok "sqlite   amalgamation $SQLITE_VERSION → .deps/"
}

build_sqlite_object() {
    local src="$SQLITE_SRC/sqlite3.c" obj="$BUILD/obj/sqlite3.o"
    if [ -f "$obj" ] && [ "$obj" -nt "$src" ] && [ "$FORCE" = 0 ]; then
        ok "sqlite3.o đã có (cache .build/obj)"
        return 0
    fi
    [ "$CHECK_ONLY" = 1 ] && { ok "sqlite3.o sẽ được biên dịch khi chạy test"; return 0; }
    mkdir -p "$BUILD/obj"
    say "  ..    biên dịch SQLite amalgamation (một lần, ~10s)"
    "$CC" -O1 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_THREADSAFE=0 \
        -c "$src" -o "$obj" || die "Biên dịch SQLite thất bại."
    ok "sqlite3.o → .build/obj/sqlite3.o"
}

if [ "${AH_FORCE_BUNDLED_SQLITE:-0}" = "1" ]; then
    MODE=bundled
    ok "sqlite   ép dùng amalgamation (AH_FORCE_BUNDLED_SQLITE=1)"
    ensure_sqlite_source
    build_sqlite_object
elif probe_system_sqlite; then
    MODE=system
    ok "sqlite   dùng thư viện hệ thống (-lsqlite3)"
else
    MODE=bundled
    warn "Không thấy SQLite hệ thống dùng được: dùng amalgamation trong .deps/."
    ensure_sqlite_source
    build_sqlite_object
fi

if [ "$CHECK_ONLY" = 0 ]; then
    mkdir -p "$BUILD"
    if [ "$MODE" = system ]; then
        cat >"$ENV_MK" <<EOF
# Sinh bởi scripts/dev-env.sh — không sửa tay, không commit.
AH_SQLITE_MODE=system
AH_SQLITE_CFLAGS=""
AH_SQLITE_LDFLAGS="-lsqlite3"
EOF
    else
        cat >"$ENV_MK" <<EOF
# Sinh bởi scripts/dev-env.sh — không sửa tay, không commit.
AH_SQLITE_MODE=bundled
AH_SQLITE_CFLAGS="-I$SQLITE_SRC"
AH_SQLITE_LDFLAGS="$BUILD/obj/sqlite3.o -lm"
AH_SQLITE_SOURCE="$SQLITE_SRC/sqlite3.c"
EOF
    fi
    ok "cấu hình → .build/env.mk (SQLite: $MODE)"
fi

say ""
say "Sẵn sàng. Bước tiếp theo:"
say "  make test     # chạy toàn bộ kiểm thử host (C++/Python/JS)"
say "  make check    # kiểm tra tính nhất quán của repo"
say "  make package FINALPACKAGE=1   # build gói Theos (cần THEOS, macOS/WSL2)"

else
    warn "Không có perl: tests/ipc_smoke.pl chỉ chạy được trên iPhone."
fi
