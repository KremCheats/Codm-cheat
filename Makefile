TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CODMCheat
CODMCheat_FILES = CODMCheat.mm Src/Hooks.mm Src/Cheat.mm Src/Overlay.mm
CODMCheat_CFLAGS = -fobjc-arc -I./Src -I./vendor/dobby/include -std=c++17 -Wno-unused-function -Wno-deprecated-declarations
CODMCheat_CCFLAGS = -fobjc-arc -I./Src -I./vendor/dobby/include -std=c++17
CODMCheat_LDFLAGS = -L./vendor/dobby/build -ldobby
CODMCheat_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics Security

include $(THEOS_MAKE_PATH)/tweak.mk
