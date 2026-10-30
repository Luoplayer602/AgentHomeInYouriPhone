#!/usr/bin/env bash
# Kiểm tra môi trường BUILD GÓI (Theos) — dùng trên máy build thật:
# WSL2/Linux/macOS. Không cần thiết để chạy `make test` (test host không dùng Theos).
#
#   make doctor            # hoặc ./scripts/check-toolchain.sh
#   THEOS=/duong/dan/theos make doctor
#
# Thoát 0 khi đủ điều kiện `make package FINALPACKAGE=1`, ngược lại liệt kê
# chính xác thứ còn thiếu.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
missing=0
warnings=0

ok()   { printf '  ok     %s\n' "$*"; }
warn() { printf '  warn   %s\n' "$*"; warnings=$((warnings + 1)); }
bad()  { printf '  THIẾU  %s\n' "$*"; missing=$((missing + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

printf 'Agent Home — kiểm tra môi trường build gói\n\n'

case "$(uname -s)" in
    Darwin) platform="macOS" ;;
    Linux)  platform="Linux" ;;
    *)      platform="$(uname -s)" ;;
esac
ok "nền tảng $platform ($(uname -m))"

# ------------------------------------------------------------------- Theos
THEOS="${THEOS:-}"
if [ -z "$THEOS" ]; then
    for candidate in /home/luoplayer/theos "$HOME/theos" /opt/theos /usr/local/theos; do
        if [ -f "$candidate/makefiles/common.mk" ]; then THEOS="$candidate"; break; fi
    done
fi
if [ -z "$THEOS" ]; then
    bad "Theos: chưa cài hoặc chưa export THEOS"
    printf '         cài: git clone --recursive https://github.com/theos/theos.git ~/theos\n'
    printf '         rồi: export THEOS=$HOME/theos  (Makefile mặc định /home/luoplayer/theos)\n'
elif [ ! -f "$THEOS/makefiles/common.mk" ]; then
    bad "THEOS=$THEOS nhưng thiếu makefiles/common.mk (clone thiếu --recursive?)"
else
    ok "Theos: $THEOS"
    if [ -f "$THEOS/makefiles/package/deb.mk" ] || have dpkg-deb; then
        ok "đóng gói .deb: makefiles + dpkg-deb"
    fi
fi

# ------------------------------------------------------------------ clang
if have clang; then
    ok "clang: $(clang --version | head -1)"
    if clang --print-targets 2>/dev/null | grep -qi 'aarch64'; then
        ok "clang hỗ trợ target arm64 (aarch64)"
    else
        warn "clang không liệt kê target aarch64 — kiểm tra bản LLVM"
    fi
elif [ -n "$THEOS" ] && [ -x "$THEOS/toolchain/linux/iphone/bin/clang" ]; then
    ok "clang: $THEOS/toolchain/linux/iphone/bin/clang"
else
    bad "clang: không có trong PATH (cài llvm/clang; trên Linux cần bản cross-compile)"
fi

# ---------------------------------------------------------------- iOS SDK
if [ -n "$THEOS" ] && [ -d "$THEOS/sdks" ]; then
    sdk_count=$(find "$THEOS/sdks" -maxdepth 1 -name 'iPhoneOS*.sdk' -type d 2>/dev/null | wc -l | tr -d ' ')
    if [ "$sdk_count" -gt 0 ]; then
        newest=$(find "$THEOS/sdks" -maxdepth 1 -name 'iPhoneOS*.sdk' -type d 2>/dev/null | sort -V | tail -1 | xargs -r basename)
        ok "iOS SDK: $newest ($sdk_count bản trong $THEOS/sdks)"
    else
        bad "iOS SDK: $THEOS/sdks không có iPhoneOS*.sdk (lấy từ theos/sdks)"
    fi
else
    bad "iOS SDK: chưa có thư mục \$THEOS/sdks"
fi

# --------------------------------------------------------------- ký binary
if have ldid; then
    ok "ldid: $(command -v ldid)"
elif [ -n "$THEOS" ] && { [ -x "$THEOS/bin/ldid" ] || [ -x "$THEOS/bin/ldid2" ]; }; then
    ok "ldid: $THEOS/bin"
else
    bad "ldid: không có (cần để ký agenthomed/AgentHome khi cài)"
fi

# ------------------------------------------------------------- dpkg/fakeroot
if have dpkg-deb; then
    ok "dpkg-deb: $(command -v dpkg-deb)"
else
    bad "dpkg-deb: không có (Linux: apt install dpkg-dev; macOS: brew install dpkg)"
fi
if [ "$platform" = "Linux" ]; then
    if have fakeroot; then ok "fakeroot: có"; else warn "fakeroot: không có (một số bản Theos cần cho make package)"; fi
fi

# ------------------------------------------------------------------ make/git
have make && ok "make: $(make --version | head -1)" || bad "make: không có"
have git  && ok "git: $(git --version)" || bad "git: không có"

# ------------------------------------------------------- kiểm tra target repo
if [ -f "$ROOT/Makefile" ] && grep -q 'THEOS_PACKAGE_SCHEME' "$ROOT/Makefile"; then
    ok "repo: Makefile có THEOS_PACKAGE_SCHEME (gói rootless)"
else
    warn "repo: không thấy cấu hình Theos trong $ROOT/Makefile"
fi

printf '\n'
if [ "$missing" -gt 0 ]; then
    printf 'Chưa build gói được: %d mục còn thiếu, %d cảnh báo.\n' "$missing" "$warnings"
    printf 'Ghi chú: `make test`/`make check` vẫn chạy được mà không cần Theos.\n'
    exit 1
fi
printf 'Sẵn sàng build gói: make package FINALPACKAGE=1 (%d cảnh báo).\n' "$warnings"
