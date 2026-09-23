TARGET = iphone:clang:latest:14.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = CODMCheat
CODMCheat_FILES = CODMCheat.mm Src/Hooks.mm Src/PatternScanner.mm Src/Bypass.mm Src/Unity.mm Src/Overlay.mm Src/Cheat.mm vendor/fishhook/fishhook.c
CODMCheat_CFLAGS = -fobjc-arc -I./Src -I./vendor/dobby/include -I./vendor/fishhook -std=c++17 -Wno-unused-function -Wno-deprecated-declarations -Wno-comment
CODMCheat_CCFLAGS = -fobjc-arc -I./Src -I./vendor/dobby/include -I./vendor/fishhook -std=c++17
CODMCheat_LDFLAGS = -L./vendor/dobby/build -ldobby
CODMCheat_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics Security
include $(THEOS_MAKE_PATH)/tweak.mk
after-all::
	@mkdir -p ./dist
	@cp .theos/obj/arm64/CODMCheat.dylib ./dist/CODMCheat.dylib 2>/dev/null || true
