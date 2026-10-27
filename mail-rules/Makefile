export THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.6
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MailRules
MailRules_FILES = Rules.m RuleCore.m
MailRules_CFLAGS = -fno-objc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations
MailRules_FRAMEWORKS = UIKit Foundation CoreFoundation
include $(THEOS_MAKE_PATH)/tweak.mk
