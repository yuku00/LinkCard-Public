export THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.6
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = FilesNativeProbe
FilesNativeProbe_FILES = Probe.m LifecycleTrace.m NativeExperiment.m
NativeExperiment.m_CFLAGS = -fobjc-arc
Probe.m_CFLAGS = -fobjc-arc
LifecycleTrace.m_CFLAGS = -fno-objc-arc
FilesNativeProbe_FRAMEWORKS = UIKit Foundation QuartzCore
include $(THEOS_MAKE_PATH)/tweak.mk
