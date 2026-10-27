include $(THEOS)/makefiles/common.mk
TOOL_NAME = firefly-lite-cleanup
firefly-lite-cleanup_FILES = main.m ../Shared/FLPreferences.m
firefly-lite-cleanup_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/..
firefly-lite-cleanup_FRAMEWORKS = Foundation CoreFoundation
firefly-lite-cleanup_INSTALL_PATH = /usr/libexec
firefly-lite-cleanup_CODESIGN_FLAGS = -Sentitlements.plist
include $(THEOS_MAKE_PATH)/tool.mk
