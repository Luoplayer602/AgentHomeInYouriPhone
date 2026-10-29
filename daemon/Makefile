include $(THEOS)/makefiles/common.mk
TOOL_NAME = agenthomed
agenthomed_FILES = main.m AHAgentRuntime.m ../app/AHProvider.mm ../app/AHProfiles.m ../app/AHProviderConfig.m ../app/AHContext.m
agenthomed_CCFLAGS = -std=c++17
agenthomed_CODESIGN_FLAGS = -Sentitlements.plist
agenthomed_CFLAGS = -fobjc-arc -Wall -Wextra
agenthomed_FRAMEWORKS = Foundation Security
agenthomed_LIBRARIES = sqlite3
agenthomed_INSTALL_PATH = /usr/bin
include $(THEOS_MAKE_PATH)/tool.mk
