# Agent Home — build gói Theos và các mục tiêu phát triển trên host.
#
#   make env                     # chuẩn bị toolchain host (không cần Theos)
#   make test                    # chạy toàn bộ kiểm thử host (C++/Python/JS)
#   make check                   # kiểm tra tính nhất quán của repo
#   make clean-host              # xoá .build/ (giữ .deps/)
#   make package FINALPACKAGE=1  # build .deb (cần Theos trên macOS/WSL2)
#
# Các mục tiêu host không cần Theos nên vẫn chạy được trên Linux CI.
export THEOS ?= /home/luoplayer/theos
export ARCHS = arm64
export TARGET = iphone:clang:15.6:15.0
export THEOS_PACKAGE_SCHEME = rootless

HOST_GOALS := env test check clean-host
# Chỉ include Theos khi có mục tiêu build gói (hoặc gọi make không tham số).
ifneq ($(filter-out $(HOST_GOALS),$(MAKECMDGOALS))$(if $(MAKECMDGOALS),,theos),)
include $(THEOS)/makefiles/common.mk
SUBPROJECTS += daemon app
include $(THEOS_MAKE_PATH)/aggregate.mk
endif

.PHONY: env test check clean-host

# .build/env.mk do scripts/dev-env.sh sinh ra; chỉ chạy một lần cho tới khi
# `make clean-host` hoặc `make env` được gọi lại.
.build/env.mk:
	@./scripts/dev-env.sh

env:
	@./scripts/dev-env.sh

test: .build/env.mk
	@./scripts/run-host-tests.sh

check:
	@python3 scripts/check_sources.py

clean-host:
	@rm -rf .build
	@printf 'Đã xoá .build/ (giữ .deps/ để không tải lại SQLite).\n'

