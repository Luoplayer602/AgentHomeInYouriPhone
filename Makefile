export THEOS ?= /home/luoplayer/theos
export ARCHS = arm64
export TARGET = iphone:clang:15.6:15.0
export THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
SUBPROJECTS += daemon app
include $(THEOS_MAKE_PATH)/aggregate.mk
