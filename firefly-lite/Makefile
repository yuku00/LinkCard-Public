export THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = FireflyLite
FireflyLite_FILES = Tweak.mm Shared/FLPreferences.m
FireflyLite_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)
FireflyLite_FRAMEWORKS = UIKit QuartzCore CoreFoundation
FireflyLite_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences Cleanup
include $(THEOS_MAKE_PATH)/aggregate.mk
