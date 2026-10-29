include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = AgentHome
AgentHome_FILES = main.m AHClient.m AHApp.m AHProviderConfig.m AHProfiles.m AHMarkdown.m AHInput.m AHSettings.m AHChatContent.mm AHDisplay.m AHWebSettings.m AHContext.m AHTaskList.m
AgentHome_CCFLAGS = -std=c++17
AgentHome_CFLAGS = -fobjc-arc -Wall -Wextra
AgentHome_FRAMEWORKS = UIKit Foundation Security OpenGLES CoreImage
AgentHome_RESOURCE_DIRS = Resources
AgentHome_CODESIGN_FLAGS = -Sentitlements.plist
include $(THEOS_MAKE_PATH)/application.mk
