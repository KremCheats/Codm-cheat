TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SupportRuntime
SupportRuntime_FILES = SupportRuntime.mm Src/Hooks.mm Src/fishhook.c Src/Bypass.mm Src/Unity.mm Src/Runtime.mm Src/Overlay.mm
SupportRuntime_CFLAGS = -fobjc-arc -I./Src -Wno-unused-function -Wno-deprecated-declarations
SupportRuntime_CCFLAGS = -fobjc-arc -I./Src -std=c++17
SupportRuntime_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics Security

include $(THEOS_MAKE_PATH)/tweak.mk
