ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = roothide

ifeq ($(wildcard $(THEOS)/vendor/mod/roothide/package/deb.mk),)
$(error RootHide Theos required)
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DateInfoTapFix
DateInfoTapFix_FILES = DateInfoTapFix.x
DateInfoTapFix_CFLAGS = -fobjc-arc -fblocks -Wall
DateInfoTapFix_FRAMEWORKS = UIKit Foundation CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
