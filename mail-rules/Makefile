export THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.6
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MailRules
# Strict production allowlist: no legacy business or theme modules.
MailRules_FILES = readonly/Entry.m readonly/Session.m readonly/Graph.m readonly/Metadata.m readonly/Observer.m
MailRules_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations
MailRules_FRAMEWORKS = UIKit Foundation CoreFoundation
include $(THEOS_MAKE_PATH)/tweak.mk
