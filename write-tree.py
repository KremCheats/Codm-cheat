import os

def w(path, content):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w") as f:
        f.write(content.lstrip("\n"))

w("Makefile", r"""
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
""")

w("CODMCheat.mm", r"""
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import "Src/Common.h"
#import "Src/Cheat.h"

static BOOL isCODM(void) {
    NSString *b = [[NSBundle mainBundle] bundleIdentifier];
    return [b containsString:@"callofduty"]
        || [b containsString:@"garena.game.codm"]
        || [b containsString:@"tencent.tmgp.cod"];
}

__attribute__((constructor))
static void CODMCheatEntry(void) {
    @autoreleasepool {
        if (!isCODM()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[Cheat shared] start];
        });
    }
}
""")

w("Src/Common.h", r"""
#ifndef COMMON_H
#define COMMON_H
#import <Foundation/Foundation.h>
#import <os/log.h>
#define LOGI(fmt, ...) os_log(OS_LOG_DEFAULT, "[CODMCheat] " fmt, ##__VA_ARGS__)
#endif
""")

w("Src/Hooks.h", r"""
#ifndef HOOKS_H
#define HOOKS_H
#include <stdint.h>
#include <objc/runtime.h>
namespace HK {
bool install(void *target, void *replacement, void **orig);
bool installSym(const char *sym, void *replacement, void **orig);
bool swizzleClass(Class cls, SEL sel, IMP replacement, IMP *original);
}
#endif
""")

w("Src/Hooks.mm", r"""
#import "Hooks.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#include <dobby.h>
namespace HK {
bool install(void *target, void *replacement, void **orig) {
    if (!target) return false;
    return DobbyHook(target, replacement, orig) == 0;
}
bool installSym(const char *sym, void *replacement, void **orig) {
    void *p = dlsym(RTLD_DEFAULT, sym);
    if (!p) return false;
    return install(p, replacement, orig);
}
bool swizzleClass(Class cls, SEL sel, IMP replacement, IMP *original) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { m = class_getClassMethod(cls, sel); if (!m) return false; }
    IMP old = method_getImplementation(m);
    if (original) *original = old;
    method_setImplementation(m, replacement);
    return true;
}
}
""")

w("Src/Overlay.h", r"""
#ifndef OVERLAY_H
#define OVERLAY_H
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
@interface CheatOverlay : UIWindow
@property (nonatomic, strong) CAShapeLayer *boxes;
@property (nonatomic, strong) CATextLayer *info;
+ (instancetype)shared;
- (void)attach;
- (void)setInfoText:(NSString *)t;
@end
#endif
""")

w("Src/Overlay.mm", r"""
#import "Overlay.h"
@implementation CheatOverlay
+ (instancetype)shared {
    static CheatOverlay *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[CheatOverlay alloc] initWithFrame:[UIScreen mainScreen].bounds]; });
    return s;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.rootViewController = [UIViewController new];
        self.rootViewController.view.backgroundColor = [UIColor clearColor];
        self.hidden = YES;
        self.boxes = [CAShapeLayer layer];
        self.boxes.frame = self.bounds;
        self.boxes.fillColor = [UIColor clearColor].CGColor;
        self.boxes.lineWidth = 1.2;
        self.boxes.strokeColor = [UIColor colorWithRed:0 green:1 blue:0.3 alpha:1].CGColor;
        self.info = [CATextLayer layer];
        self.info.frame = CGRectMake(12, 60, frame.size.width - 24, 220);
        self.info.foregroundColor = [UIColor colorWithRed:0 green:1 blue:0.5 alpha:1].CGColor;
        self.info.fontSize = 11;
        self.info.contentsScale = [UIScreen mainScreen].scale;
        self.info.alignmentMode = kCAAlignmentLeft;
        self.info.wrapped = YES;
        [self.layer addSublayer:self.boxes];
        [self.layer addSublayer:self.info];
    }
    return self;
}
- (void)attach { self.hidden = NO; [self makeKeyAndVisible]; }
- (void)setInfoText:(NSString *)t { self.info.string = t; }
@end
""")

w("Src/Cheat.h", r"""
#ifndef CHEAT_H
#define CHEAT_H
#import <Foundation/Foundation.h>
@interface Cheat : NSObject
+ (instancetype)shared;
- (void)start;
- (void)stop;
@end
#endif
""")

w("Src/Cheat.mm", r"""
#import "Cheat.h"
#import "Common.h"
#import "Overlay.h"
#import <QuartzCore/QuartzCore.h>

@implementation Cheat
+ (instancetype)shared {
    static Cheat *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [Cheat new]; });
    return s;
}
- (void)start {
    LOGI("start");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CheatOverlay shared] attach];
        [[CheatOverlay shared] setInfoText:@"CODM (non-JB)\nloaded"];
    });
}
- (void)stop {}
@end
""")

print("wrote", len(["Makefile","CODMCheat.mm","Src/Common.h","Src/Hooks.h","Src/Hooks.mm","Src/Overlay.h","Src/Overlay.mm","Src/Cheat.h","Src/Cheat.mm"]), "files")
