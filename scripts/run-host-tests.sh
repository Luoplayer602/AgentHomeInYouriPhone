#!/usr/bin/env bash
# Chạy toàn bộ kiểm thử chạy được trên host (không cần Theos, không cần iPhone):
#   - C++  : parser/HTTP/SSE/Markdown, migration SQLite, task queue, ngân sách context
#   - Python: các test chạy SQL thật của compaction/runtime/usage
#   - JS   : tests/web_ui_test.js (nếu có node)
#   - Repo : scripts/check_sources.py (Makefile, header, asset, version)
#
#   ./scripts/run-host-tests.sh [-v|--verbose]
#
# Test cần thiết bị (tests/ipc_smoke.py, tests/ipc_smoke.pl) chỉ chạy khi
# AH_DEVICE=1 và được bỏ qua mặc định.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"
OUT="$BUILD/tests"
ENV_MK="$BUILD/env.mk"
VERBOSE=0

for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'Tham số không hỗ trợ: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

cd "$ROOT" || exit 1
if [ ! -f "$ENV_MK" ]; then
    ./scripts/dev-env.sh || exit 1
fi
# shellcheck disable=SC1090
. "$ENV_MK"

CXX="${CXX:-g++}"
PYTHON="${PYTHON:-python3}"
mkdir -p "$OUT"

# Bash 3.2 (macOS) không an toàn với mảng rỗng dưới `set -u`, dùng hàm thay thế.
if command -v timeout >/dev/null 2>&1; then
    run_limited() { timeout 300 "$@"; }
else
    run_limited() { "$@"; }
fi

PASS=0 FAIL=0 SKIP=0
FAILED=()
SKIPPED=()

pass() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILED+=("$1"); printf 'FAIL  %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); SKIPPED+=("$1 — $2"); printf 'SKIP  %s (%s)\n' "$1" "$2"; }

show_log() { # logfile, label
    [ "$VERBOSE" = 1 ] && cat "$1" && return 0
    printf '      %s\n' "$2"
    sed -n '1,24p' "$1" | sed 's/^/      /'
    printf '      … log đầy đủ: %s\n' "$1"
}

# Tách cờ thành mảng, bỏ phần tử rỗng (bash 3.2 trên macOS không an toàn
# với mảng rỗng dưới `set -u`, nên luôn dùng dạng ${arr[@]+"${arr[@]}"}).
SQLITE_CFLAGS=()
SQLITE_LDFLAGS=()
set -f
for flag in ${AH_SQLITE_CFLAGS:-}; do SQLITE_CFLAGS+=("$flag"); done
for flag in ${AH_SQLITE_LDFLAGS:-}; do SQLITE_LDFLAGS+=("$flag"); done
set +f

printf 'Agent Home — kiểm thử host (SQLite: %s)\n\n' "${AH_SQLITE_MODE:-unknown}"

# ------------------------------------------------------------ repo sanity
log="$OUT/repo-checks.log"
if run_limited "$PYTHON" scripts/check_sources.py >"$log" 2>&1; then
    pass "repo-checks"
    [ "$VERBOSE" = 1 ] && sed 's/^/      /' "$log"
else
    fail "repo-checks"
    show_log "$log" "scripts/check_sources.py thất bại"
fi

# ----------------------------------------------------------------- C++ tests
for src in tests/*.cpp; do
    [ -e "$src" ] || continue
    name="$(basename "$src" .cpp)"
    bin="$OUT/$name"
    log="$OUT/$name.log"
    if ! run_limited "$CXX" -std=c++17 -Wall -Wextra -Werror -I"$ROOT" \
        ${SQLITE_CFLAGS[@]+"${SQLITE_CFLAGS[@]}"} "$src" ${SQLITE_LDFLAGS[@]+"${SQLITE_LDFLAGS[@]}"} -o "$bin" >"$log" 2>&1; then
        fail "$name (biên dịch)"
        show_log "$log" "Biên dịch thất bại"
        continue
    fi
    if run_limited "$bin" >>"$log" 2>&1; then
        pass "$name"
        [ "$VERBOSE" = 1 ] && sed 's/^/      /' "$log"
    else
        status=$?
        fail "$name"
        show_log "$log" "Chạy test thất bại (exit $status)"
    fi
done

# -------------------------------------------------------------- Python tests
for src in tests/*.py; do
    [ -e "$src" ] || continue
    name="$(basename "$src" .py)"
    if [ "$name" = "ipc_smoke" ] && [ "${AH_DEVICE:-0}" != "1" ]; then
        skip "$name" "cần daemon chạy trên iPhone — đặt AH_DEVICE=1 để bật"
        continue
    fi
    log="$OUT/$name.log"
    if run_limited "$PYTHON" "$src" >"$log" 2>&1; then
        pass "$name"
        [ "$VERBOSE" = 1 ] && sed 's/^/      /' "$log"
    else
        status=$?
        fail "$name"
        show_log "$log" "Chạy test thất bại (exit $status)"
    fi
done

# ------------------------------------------------------------------ web UI JS
if [ -f tests/web_ui_test.js ]; then
    if command -v node >/dev/null 2>&1; then
        log="$OUT/web_ui_test.log"
        if run_limited node tests/web_ui_test.js >"$log" 2>&1; then
            pass "web_ui_test"
            [ "$VERBOSE" = 1 ] && sed 's/^/      /' "$log"
        else
            status=$?
            fail "web_ui_test"
            show_log "$log" "Chạy test thất bại (exit $status)"
        fi
    else
        skip "web_ui_test" "không có node"
    fi
fi

# -------------------------------------------------------------------- summary
printf '\nKết quả: %d pass, %d skip, %d fail\n' "$PASS" "$SKIP" "$FAIL"
if [ "$SKIP" -gt 0 ]; then
    printf 'Bỏ qua:\n'
    printf '  - %s\n' "${SKIPPED[@]}"
fi
if [ "$FAIL" -gt 0 ]; then
    printf 'Thất bại:\n'
    printf '  - %s\n' "${FAILED[@]}"
    exit 1
fi
printf 'Tất cả kiểm thử host đều đạt.\n'
