ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = roothide

ifeq ($(strip $(THEOS)),)
$(error Set THEOS to an existing RootHide Theos checkout)
endif
ifeq ($(wildcard $(THEOS)/vendor/mod/roothide/package/deb.mk),)
$(error RootHide Theos support missing; do not substitute rootless)
endif

include $(THEOS)/makefiles/common.mk
TWEAK_NAME = NoLinesUnified
NoLinesUnified_FILES = NoLinesUnified.m
NoLinesUnified_CFLAGS = -fobjc-arc -fblocks
NoLinesUnified_FRAMEWORKS = UIKit Foundation QuartzCore
NoLinesUnified_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
