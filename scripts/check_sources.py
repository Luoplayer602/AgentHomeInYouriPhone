#!/usr/bin/env python3
"""Kiểm tra tính nhất quán tĩnh của repo, chạy được trên mọi host.

Không cần Theos/Xcode. Bắt các lỗi hay gặp khi thêm file hoặc đổi asset:

  1. Mọi file trong *_FILES của app/, daemon/, tests/ Makefile đều tồn tại.
  2. Mọi .m/.mm/.c(pp) trong app/ và daemon/ đều được khai báo để build.
  3. Mọi #import "..." / #include "..." cục bộ trỏ tới file có thật.
  4. control, app/Resources/Info.plist cùng một version.
  5. Asset đi kèm (model-limits.json, index.html, LaunchDaemons plist) hợp lệ.

Thoát mã 1 nếu có lỗi; cảnh báo (WARN) không làm fail.
"""
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = (".m", ".mm", ".c", ".cpp")
MAKEFILES = {
    "app/Makefile": "app",
    "daemon/Makefile": "daemon",
    "tests/Makefile": "tests",
}

errors: list[str] = []
warnings: list[str] = []


def listed_files(makefile: Path) -> list[str]:
    text = makefile.read_text(encoding="utf-8")
    names: list[str] = []
    for _, value in re.findall(r"^(\w+_FILES)\s*=\s*(.+)$", text, re.M):
        names += value.split()
    return names


def check_makefile_files() -> None:
    compiled: set[Path] = set()
    for rel, folder in MAKEFILES.items():
        makefile = ROOT / rel
        if not makefile.exists():
            errors.append(f"{rel}: không tồn tại")
            continue
        names = listed_files(makefile)
        if not names:
            errors.append(f"{rel}: không tìm thấy biến *_FILES")
            continue
        for name in names:
            target = (makefile.parent / name).resolve()
            if not target.exists():
                errors.append(f"{rel}: khai báo {name} nhưng file không tồn tại")
            compiled.add(target)
    # app/ chứa cả source dùng chung cho daemon (AHProvider, AHPrompt, ...),
    # nên chỉ báo lỗi khi một file không được build ở bất kỳ target nào.
    for folder in ("app", "daemon"):
        for source in sorted((ROOT / folder).iterdir()):
            if source.suffix in SOURCES and source.resolve() not in compiled:
                errors.append(
                    f"{folder}/{source.name}: không có trong Makefile nào (dead code?)"
                )


def check_local_imports() -> None:
    pattern = re.compile(r'^\s*#(?:import|include)\s+"([^"]+)"', re.M)
    for folder in ("app", "daemon", "shared", "core", "tests"):
        base = ROOT / folder
        if not base.exists():
            continue
        for source in base.rglob("*"):
            if source.suffix not in (*SOURCES, ".h", ".hpp"):
                continue
            text = source.read_text(encoding="utf-8", errors="replace")
            for target in pattern.findall(text):
                if not (source.parent / target).exists():
                    errors.append(
                        f"{source.relative_to(ROOT)}: import {target} không tồn tại"
                    )


def read_versions() -> None:
    control = (ROOT / "control").read_text(encoding="utf-8")
    version = re.search(r"^Version:\s*(\S+)", control, re.M)
    if not version:
        errors.append("control: thiếu trường Version")
    info = ROOT / "app/Resources/Info.plist"
    try:
        bundle = plistlib.loads(info.read_bytes()).get("CFBundleShortVersionString")
    except Exception as exc:  # noqa: BLE001 - báo lỗi rõ ràng là đủ
        errors.append(f"app/Resources/Info.plist: không đọc được ({exc})")
        return
    if version and bundle != version.group(1):
        errors.append(
            f"version lệch: control={version.group(1)} Info.plist={bundle}"
        )
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    headline = re.search(r"^# .*?v(\d+\.\d+\.\d+)", readme, re.M)
    if version and headline and headline.group(1) != version.group(1):
        warnings.append(
            f"README.md ghi v{headline.group(1)} nhưng control là {version.group(1)} "
            "(cập nhật mục mới nhất ở đầu README)"
        )


def check_assets() -> None:
    limits = ROOT / "layout/usr/share/agenthome/model-limits.json"
    try:
        data = json.loads(limits.read_text(encoding="utf-8"))
        if not isinstance(data, (dict, list)):
            errors.append(f"{limits.relative_to(ROOT)}: JSON gốc phải là object/array")
    except Exception as exc:  # noqa: BLE001
        errors.append(f"{limits.relative_to(ROOT)}: JSON không hợp lệ ({exc})")
    page = ROOT / "layout/usr/share/agenthome/index.html"
    if not page.exists() or page.stat().st_size == 0:
        errors.append("layout/usr/share/agenthome/index.html: thiếu hoặc rỗng")
    plist = ROOT / "layout/Library/LaunchDaemons/dev.agenthome.daemon.plist"
    try:
        job = plistlib.loads(plist.read_bytes())
        if job.get("Label") != "dev.agenthome.daemon":
            errors.append(f"{plist.relative_to(ROOT)}: Label không khớp tên file")
        if not job.get("ProgramArguments"):
            errors.append(f"{plist.relative_to(ROOT)}: thiếu ProgramArguments")
    except Exception as exc:  # noqa: BLE001
        errors.append(f"{plist.relative_to(ROOT)}: plist không hợp lệ ({exc})")
    socket_path = re.search(
        r'#define\s+AHSocketPath\s+"([^"]+)"',
        (ROOT / "shared/AHProtocol.h").read_text(encoding="utf-8"),
    )
    if not socket_path:
        errors.append("shared/AHProtocol.h: thiếu #define AHSocketPath")
    elif not socket_path.group(1).startswith("/var/mobile/"):
        warnings.append(
            f"AHSocketPath={socket_path.group(1)} nằm ngoài /var/mobile (kiểm tra quyền)"
        )


def main() -> int:
    check_makefile_files()
    check_local_imports()
    read_versions()
    check_assets()
    for message in warnings:
        print(f"WARN  {message}")
    for message in errors:
        print(f"FAIL  {message}")
    if errors:
        print(f"\n{len(errors)} lỗi, {len(warnings)} cảnh báo")
        return 1
    print(f"PASS  repo nhất quán: Makefile, import cục bộ, version, asset ({len(warnings)} cảnh báo)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
