export THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.6
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MailProbe
MailProbe_FILES = Probe.m Metadata.m
MailProbe_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter
MailProbe_FRAMEWORKS = UIKit Foundation
include $(THEOS_MAKE_PATH)/tweak.mk
