include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = FireflyLitePrefs
FireflyLitePrefs_FILES = FLRootController.m ../Shared/FLPreferences.m
FireflyLitePrefs_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/..
FireflyLitePrefs_FRAMEWORKS = UIKit CoreFoundation
FireflyLitePrefs_PRIVATE_FRAMEWORKS = Preferences
FireflyLitePrefs_INSTALL_PATH = /Library/PreferenceBundles
include $(THEOS_MAKE_PATH)/bundle.mk
