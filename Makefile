TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CODMCheat
CODMCheat_FILES = CODMCheat.mm Src/Hooks.mm Src/fishhook.c Src/Bypass.mm Src/Unity.mm Src/Cheat.mm Src/Overlay.mm
CODMCheat_CFLAGS = -fobjc-arc -I./Src -Wno-unused-function -Wno-deprecated-declarations
CODMCheat_CCFLAGS = -fobjc-arc -I./Src -std=c++17
CODMCheat_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics Security

include $(THEOS_MAKE_PATH)/tweak.mk
