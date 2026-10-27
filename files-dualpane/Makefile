export THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.6
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = FilesNativeProbe
FilesNativeProbe_FILES = Entry.m DualPane.m DiffableBridge.swift
FilesNativeProbe_CFLAGS = -fobjc-arc
FilesNativeProbe_FRAMEWORKS = UIKit Foundation QuartzCore QuickLook
include $(THEOS_MAKE_PATH)/tweak.mk
