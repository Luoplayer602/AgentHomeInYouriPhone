THEOS ?= /home/luoplayer/theos
ARCHS = arm64
TARGET = iphone:clang:15.6:15.0
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
TOOL_NAME = ahcheck
ahcheck_FILES = main.m ../app/AHClient.m
ahcheck_CFLAGS = -fobjc-arc
ahcheck_FRAMEWORKS = Foundation
include $(THEOS_MAKE_PATH)/tool.mk
