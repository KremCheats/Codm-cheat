import os, pathlib

files = {}

files["Makefile"] = r"""
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
"""

files["CODMCheat.mm"] = r"""
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import "Src/Common.h"
#import "Src/Bypass.h"
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
        LOGI("CODMCheat loading");
        Bypass::install();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            Cheat::shared()->start();
        });
    }
}
"""

files["Src/Common.h"] = r"""
#ifndef COMMON_H
#define COMMON_H
#import <Foundation/Foundation.h>
#import <os/log.h>
#ifdef DEBUG
    #define LOGI(fmt, ...) os_log(OS_LOG_DEFAULT, "[CODMCheat] " fmt, ##__VA_ARGS__)
#else
    #define LOGI(fmt, ...) ((void)0)
#endif
#define KERN_PROC_PID 1
struct Matrix4x4 { float m[16]; };
struct Vec3 { float x, y, z; };
static inline Vec3 vec3_sub(Vec3 a, Vec3 b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
static inline float vec3_len(Vec3 v) { return sqrtf(v.x*v.x + v.y*v.y + v.z*v.z); }
#endif
"""

files["Src/Hooks.h"] = r"""
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
"""

files["Src/Hooks.mm"] = r"""
#import "Hooks.h"
#import "Common.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#include <dobby.h>
namespace HK {
bool install(void *target, void *replacement, void **orig) {
    if (!target) return false;
    int r = DobbyHook(target, replacement, orig);
    if (r != 0) return false;
    return true;
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
"""

files["Src/PatternScanner.h"] = r"""
#ifndef PATTERN_SCANNER_H
#define PATTERN_SCANNER_H
#include <stdint.h>
#include <stddef.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
namespace PS {
uintptr_t scanMain(const char *sig);
uintptr_t scanAll(const char *sig);
}
#endif
"""

files["Src/PatternScanner.mm"] = r"""
#import "PatternScanner.h"
#include <mach/mach.h>
#include <string.h>
namespace PS {
static inline int hexc(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}
static bool compile(const char *sig, uint8_t *bytes, uint8_t *mask, size_t *len) {
    size_t n = 0; const char *p = sig;
    while (*p) {
        while (*p == ' ') p++;
        if (!*p) break;
        if (*p == '?' || *p == 'x' || *p == 'X') {
            bytes[n] = 0; mask[n] = 0; n++;
            while (*p && *p != ' ') p++;
        } else {
            int hi = hexc(p[0]); int lo = hexc(p[1]);
            if (hi < 0 || lo < 0) return false;
            bytes[n] = (hi << 4) | lo; mask[n] = 0xFF; n++;
            p += 2;
        }
    }
    *len = n; return n > 0;
}
static uintptr_t scanRange(const uint8_t *base, size_t size,
                           const uint8_t *bytes, const uint8_t *mask, size_t len) {
    if (size < len) return 0;
    for (size_t i = 0; i <= size - len; i++) {
        bool ok = true;
        for (size_t j = 0; j < len; j++) if (mask[j] && base[i + j] != bytes[j]) { ok = false; break; }
        if (ok) return (uintptr_t)(base + i);
    }
    return 0;
}
static uintptr_t scanImage(const struct mach_header_64 *hdr, intptr_t slide, const char *sig) {
    uint8_t bytes[512]; uint8_t mask[512]; size_t len;
    if (!compile(sig, bytes, mask, &len)) return 0;
    if (len > sizeof(bytes)) return 0;
    const uint8_t *base = (const uint8_t *)hdr;
    const struct load_command *lc = (const struct load_command *)(base + sizeof(struct mach_header_64));
    for (uint32_t i = 0; i < hdr->ncmds && lc; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strcmp(seg->segname, "__TEXT") == 0) {
                uintptr_t segAddr = (uintptr_t)seg->vmaddr + slide;
                uintptr_t r = scanRange((const uint8_t *)segAddr, seg->vmsize, bytes, mask, len);
                if (r) return r;
            }
        }
        lc = (const struct load_command *)((uint8_t *)lc + lc->cmdsize);
    }
    return 0;
}
uintptr_t scanMain(const char *sig) {
    const struct mach_header_64 *hdr = (const struct mach_header_64 *)_dyld_get_image_header(0);
    return scanImage(hdr, _dyld_get_image_vmaddr_slide(0), sig);
}
uintptr_t scanAll(const char *sig) {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const struct mach_header_64 *hdr = (const struct mach_header_64 *)_dyld_get_image_header(i);
        uintptr_t r = scanImage(hdr, _dyld_get_image_vmaddr_slide(i), sig);
        if (r) return r;
    }
    return 0;
}
}
"""

files["Src/Unity.h"] = r"""
#ifndef UNITY_H
#define UNITY_H
#include <stdint.h>
namespace Unity {
typedef void* (*t_dg)();
typedef void* (*t_dao)(void*,const char*);
typedef void* (*t_agi)(void*);
typedef void* (*t_cfn)(void*,const char*,const char*);
typedef void* (*t_cgm)(void*,const char*,int);
typedef void* (*t_cgf)(void*,const char*);
typedef void* (*t_ri)(void*,void*,void**,void**);
bool init();
void* domain();
void* klass(const char*,const char*);
void* method(void*,const char*,int);
void* field(void*,const char*);
void readFieldRaw(void*,void*,const char*,void*,size_t);
void writeFieldRaw(void*,void*,const char*,const void*,size_t);
extern t_dg p_domain_get;
extern t_dao p_domain_assembly_open;
extern t_agi p_assembly_get_image;
extern t_cfn p_class_from_name;
extern t_cgm p_class_get_method_from_name;
extern t_cgf p_class_get_field_from_name;
extern t_ri p_runtime_invoke;
}
#endif
"""

files["Src/Unity.mm"] = r"""
#import "Unity.h"
#import "Common.h"
#import <dlfcn.h>
#import <string.h>
#import <mach-o/dyld.h>
namespace Unity {
t_dg p_domain_get = nullptr;
t_dao p_domain_assembly_open = nullptr;
t_agi p_assembly_get_image = nullptr;
t_cfn p_class_from_name = nullptr;
t_cgm p_class_get_method_from_name = nullptr;
t_cgf p_class_get_field_from_name = nullptr;
t_ri p_runtime_invoke = nullptr;
static void *g_domain = nullptr;
static void *g_img = nullptr;
static void *rs(const char *n) { return dlsym(RTLD_DEFAULT, n); }
bool init() {
    p_domain_get = (t_dg)rs("il2cpp_domain_get");
    p_domain_assembly_open = (t_dao)rs("il2cpp_domain_assembly_open");
    p_assembly_get_image = (t_agi)rs("il2cpp_assembly_get_image");
    p_class_from_name = (t_cfn)rs("il2cpp_class_from_name");
    p_class_get_method_from_name = (t_cgm)rs("il2cpp_class_get_method_from_name");
    p_class_get_field_from_name = (t_cgf)rs("il2cpp_class_get_field_from_name");
    p_runtime_invoke = (t_ri)rs("il2cpp_runtime_invoke");
    if (!p_domain_get || !p_domain_assembly_open || !p_assembly_get_image) return false;
    g_domain = p_domain_get();
    return g_domain != nullptr;
}
void* domain() { return g_domain; }
void* klass(const char *ns, const char *n) {
    if (!g_img) {
        if (!g_domain) return nullptr;
        void *asm_ = p_domain_assembly_open(g_domain, "Assembly-CSharp");
        if (!asm_) return nullptr;
        g_img = p_assembly_get_image(asm_);
    }
    if (!g_img || !p_class_from_name) return nullptr;
    return p_class_from_name(g_img, ns, n);
}
void* method(void *k, const char *n, int a) {
    if (!k || !p_class_get_method_from_name) return nullptr;
    return p_class_get_method_from_name(k, n, a);
}
void* field(void *k, const char *n) {
    if (!k || !p_class_get_field_from_name) return nullptr;
    return p_class_get_field_from_name(k, n);
}
void readFieldRaw(void *o, void *k, const char *n, void *out, size_t sz) {
    void *f = field(k, n);
    if (!f) return;
    // il2cpp_field_get_value would be called here; stub for build
}
void writeFieldRaw(void *o, void *k, const char *n, const void *in, size_t sz) {
    void *f = field(k, n);
    if (!f) return;
}
}
"""

files["Src/Overlay.h"] = r"""
#ifndef OVERLAY_H
#define OVERLAY_H
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include "Common.h"
@interface CheatOverlay : UIWindow
@property (nonatomic, strong) CAShapeLayer *boxes;
@property (nonatomic, strong) CAShapeLayer *lines;
@property (nonatomic, strong) CAShapeLayer *fov;
@property (nonatomic, strong) CATextLayer *info;
+ (instancetype)shared;
- (void)attach;
- (void)begin;
- (void)setFovRadius:(CGFloat)r;
- (void)setInfoText:(NSString *)t;
- (void)clear;
- (void)drawBoxAt:(CGRect)r color:(UIColor *)c;
- (void)drawLineFrom:(CGPoint)a to:(CGPoint)b color:(UIColor *)c;
@end
#endif
"""

files["Src/Overlay.mm"] = r"""
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
        self.lines = [CAShapeLayer layer];
        self.lines.frame = self.bounds;
        self.lines.fillColor = [UIColor clearColor].CGColor;
        self.lines.lineWidth = 1.0;
        self.lines.strokeColor = [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.8].CGColor;
        self.fov = [CAShapeLayer layer];
        self.fov.frame = self.bounds;
        self.fov.fillColor = [UIColor clearColor].CGColor;
        self.fov.lineWidth = 1.0;
        self.fov.strokeColor = [UIColor colorWithRed:1 green:1 blue:1 alpha:0.35].CGColor;
        self.info = [CATextLayer layer];
        self.info.frame = CGRectMake(12, 60, frame.size.width - 24, 220);
        self.info.foregroundColor = [UIColor colorWithRed:0 green:1 blue:0.5 alpha:1].CGColor;
        self.info.font = (__bridge CFTypeRef)[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        self.info.fontSize = 11;
        self.info.contentsScale = [UIScreen mainScreen].scale;
        self.info.alignmentMode = kCAAlignmentLeft;
        self.info.wrapped = YES;
        [self.layer addSublayer:self.boxes];
        [self.layer addSublayer:self.lines];
        [self.layer addSublayer:self.fov];
        [self.layer addSublayer:self.info];
    }
    return self;
}
- (void)attach {
    self.hidden = NO;
    [self makeKeyAndVisible];
}
- (void)begin { self.boxes.path = NULL; self.lines.path = NULL; self.fov.path = NULL; }
- (void)setFovRadius:(CGFloat)r {
    CGPoint c = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0);
    UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:0 endAngle:M_PI * 2 clockwise:YES];
    self.fov.path = p.CGPath;
}
- (void)setInfoText:(NSString *)t { self.info.string = t; }
- (void)drawBoxAt:(CGRect)r color:(UIColor *)c {
    UIBezierPath *p = [UIBezierPath bezierPathWithRect:r];
    CGMutablePathRef cur = CGPathCreateMutableCopy(self.boxes.path ?: CGPathCreateMutable());
    CGPathAddPath(cur, NULL, p.CGPath);
    self.boxes.path = cur;
    CGPathRelease(cur);
}
- (void)drawLineFrom:(CGPoint)a to:(CGPoint)b color:(UIColor *)c {
    CGMutablePathRef cur = CGPathCreateMutableCopy(self.lines.path ?: CGPathCreateMutable());
    CGPathMoveToPoint(cur, NULL, a.x, a.y);
    CGPathAddLineToPoint(cur, NULL, b.x, b.y);
    self.lines.path = cur;
    CGPathRelease(cur);
}
- (void)clear { self.boxes.path = NULL; self.lines.path = NULL; }
@end
"""

files["Src/Cheat.h"] = r"""
#ifndef CHEAT_H
#define CHEAT_H
#import <Foundation/Foundation.h>
@interface Cheat : NSObject
+ (instancetype)shared;
- (void)start;
- (void)stop;
@end
#endif
"""

files["Src/Cheat.mm"] = r"""
#import "Cheat.h"
#import "Common.h"
#import "Overlay.h"
#import "Unity.h"
#import <QuartzCore/QuartzCore.h>

struct CheatCfg {
    bool espEnabled = true, espBoxes = true, espLines = true;
    bool fovEnabled = true; float fovRadius = 220.0f;
    bool aimEnabled = true, silentAim = false, aimVisibleOnly = true;
    float aimFov = 90.0f, aimSmooth = 4.0f; int aimBone = 0;
    bool noRecoil = true, noSpread = true;
    float maxDistance = 400.0f;
};
static CheatCfg g_cfg;

@interface Cheat ()
@property (nonatomic, strong) CADisplayLink *tick;
@end

@implementation Cheat
+ (instancetype)shared {
    static Cheat *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [Cheat new]; });
    return s;
}
- (void)start {
    [[CheatOverlay shared] attach];
    [[CheatOverlay shared] setFovRadius:g_cfg.fovRadius];
    if (Unity::init()) {
        [[CheatOverlay shared] setInfoText:@"CODM (non-JB) | il2cpp ok\nwaiting for match..."];
    } else {
        [[CheatOverlay shared] setInfoText:@"CODM (non-JB) | il2cpp exports missing"];
    }
    self.tick = [CADisplayLink displayLinkWithTarget:self selector:@selector(onTick:)];
    [self.tick addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)stop {
    [self.tick invalidate];
    self.tick = nil;
    [[CheatOverlay shared] clear];
}
- (void)onTick:(CADisplayLink *)dl {
    if (!Unity::domain()) return;
    CheatOverlay *ov = [CheatOverlay shared];
    [ov begin];
    [ov setFovRadius:g_cfg.fovEnabled ? g_cfg.fovRadius : 0.0f];
    [ov setInfoText:@"CODM (non-JB) | running"];
}
@end
"""

files["Src/Bypass.h"] = r"""
#ifndef BYPASS_H
#define BYPASS_H
namespace Bypass {
void install();
void applyAceHooks();
}
#endif
"""

files["Src/Bypass.mm"] = r"""
#import "Bypass.h"
#import "Common.h"
#import "Hooks.h"
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/ptrace.h>
#import <dlfcn.h>
#import <dirent.h>
#import <errno.h>
#import <string.h>
#import <unistd.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static const char *kSus[] = {"CODMCheat","frida","Frida","gum-js","gadget","cycript",
    "CydiaSubstrate","MobileSubstrate","Substrate","libhooker","ElleKit","ellekit",
    "substitute","Substitute","TweakInject","cynject",NULL};
static inline bool isSus(const char *p) {
    if (!p) return false;
    for (int i = 0; kSus[i]; i++) if (strstr(p, kSus[i])) return true;
    return false;
}
static const char *kJb[] = {"/Applications/Cydia.app","/Applications/Sileo.app",
    "/Applications/Zebra.app","/Applications/Filza.app","/Library/MobileSubstrate",
    "/Library/Substrate","/bin/bash","/bin/sh","/bin/zsh","/usr/sbin/sshd",
    "/usr/bin/ssh","/etc/apt","/etc/ssh/sshd_config","/private/var/lib/apt",
    "/private/var/lib/cydia","/var/jb","/var/jb/usr/bin/ssh","/var/jb/Library/MobileSubstrate",NULL};
static inline bool isJb(const char *p) {
    if (!p) return false;
    for (int i = 0; kJb[i]; i++) if (strcmp(p, kJb[i]) == 0) return true;
    if (isSus(p)) return true;
    return false;
}

static FILE *(*o_fopen)(const char *, const char *);
static FILE *h_fopen(const char *p, const char *m) { if (isJb(p)) { errno = ENOENT; return NULL; } return o_fopen(p, m); }
static int (*o_stat)(const char *, struct stat *);
static int h_stat(const char *p, struct stat *b) { if (isJb(p)) { errno = ENOENT; return -1; } return o_stat(p, b); }
static int (*o_lstat)(const char *, struct stat *);
static int h_lstat(const char *p, struct stat *b) { if (isJb(p)) { errno = ENOENT; return -1; } return o_lstat(p, b); }
static int (*o_access)(const char *, int);
static int h_access(const char *p, int m) { if (isJb(p)) { errno = ENOENT; return -1; } return o_access(p, m); }
static DIR *(*o_opendir)(const char *);
static DIR *h_opendir(const char *p) { if (isJb(p)) { errno = ENOENT; return NULL; } return o_opendir(p); }
static char *(*o_getenv)(const char *);
static char *h_getenv(const char *n) {
    if (!n) return NULL;
    if (strncmp(n, "DYLD_", 5) == 0) return NULL;
    if (strstr(n, "FRIDA")) return NULL;
    if (strstr(n, "SUBSTRATE")) return NULL;
    return o_getenv(n);
}
static int (*o_ptrace)(int, pid_t, caddr_t, int);
static int h_ptrace(int req, pid_t pid, caddr_t a, int d) {
    if (req == PT_DENY_ATTACH) return 0;
    return o_ptrace(req, pid, a, d);
}
static uint32_t (*o_dyld_count)(void);
static uint32_t h_dyld_count(void) {
    uint32_t real = o_dyld_count(); uint32_t hide = 0;
    for (uint32_t i = 0; i < real; i++) if (isSus(_dyld_get_image_name(i))) hide++;
    return real - hide;
}
static const char *(*o_dyld_name)(uint32_t);
static const char *h_dyld_name(uint32_t idx) {
    uint32_t real = o_dyld_count(); uint32_t seen = 0;
    for (uint32_t i = 0; i < real; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (isSus(nm)) continue;
        if (seen == idx) return o_dyld_name(i);
        seen++;
    }
    return o_dyld_name(idx);
}
static int (*o_dladdr)(const void *, Dl_info *);
static int h_dladdr(const void *a, Dl_info *info) {
    int r = o_dladdr(a, info);
    if (r && info && info->dli_fname && isSus(info->dli_fname)) {
        info->dli_fname = "/usr/lib/system/libsystem_kernel.dylib";
        info->dli_fbase = (void *)0x1;
        info->dli_sname = NULL;
        info->dli_saddr = NULL;
    }
    return r;
}
static OSStatus (*o_SecCV)(SecCodeRef, SecCSFlags, SecRequirementRef);
static OSStatus h_SecCV(SecCodeRef c, SecCSFlags f, SecRequirementRef r) { return errSecSuccess; }
static OSStatus (*o_SecCVWE)(SecCodeRef, SecCSFlags, SecRequirementRef, CFErrorRef *);
static OSStatus h_SecCVWE(SecCodeRef c, SecCSFlags f, SecRequirementRef r, CFErrorRef *e) { if (e) *e = NULL; return errSecSuccess; }
static OSStatus (*o_SecSCV)(SecStaticCodeRef, SecCSFlags, SecRequirementRef);
static OSStatus h_SecSCV(SecStaticCodeRef c, SecCSFlags f, SecRequirementRef r) { return errSecSuccess; }
static OSStatus (*o_SecSCVWE)(SecStaticCodeRef, SecCSFlags, SecRequirementRef, CFErrorRef *);
static OSStatus h_SecSCVWE(SecStaticCodeRef c, SecCSFlags f, SecRequirementRef r, CFErrorRef *e) { if (e) *e = NULL; return errSecSuccess; }
static OSStatus (*o_SecCSI)(SecCodeRef, SecCSFlags, CFDictionaryRef *);
static OSStatus h_SecCSI(SecCodeRef code, SecCSFlags flags, CFDictionaryRef *info) {
    OSStatus r = o_SecCSI(code, flags, info);
    if (r == errSecSuccess && info && *info) {
        CFMutableDictionaryRef m = CFDictionaryCreateMutableCopy(NULL, 0, *info);
        CFDictionarySetValue(m, CFSTR("identifier"), CFSTR("com.activision.callofduty.shooter"));
        CFDictionarySetValue(m, CFSTR("flags"), CFSTR("0"));
        CFDictionarySetValue(m, CFSTR("teamid"), CFSTR(""));
        if (*info) CFRelease(*info);
        *info = m;
    }
    return r;
}
static BOOL (*o_fE)(NSFileManager *, SEL, NSString *);
static BOOL h_fE(NSFileManager *s, SEL c, NSString *p) { if (isJb([p UTF8String])) return NO; return o_fE(s, c, p); }
static BOOL (*o_fED)(NSFileManager *, SEL, NSString *, BOOL *);
static BOOL h_fED(NSFileManager *s, SEL c, NSString *p, BOOL *d) { if (isJb([p UTF8String])) { if (d) *d = NO; return NO; } return o_fED(s, c, p, d); }
static BOOL (*o_cOU)(UIApplication *, SEL, NSURL *);
static BOOL h_cOU(UIApplication *s, SEL c, NSURL *u) {
    NSString *sc = [[u scheme] lowercaseString];
    if ([sc isEqualToString:@"cydia"] || [sc isEqualToString:@"sileo"] ||
        [sc isEqualToString:@"zbra"] || [sc isEqualToString:@"filza"]) return NO;
    return o_cOU(s, c, u);
}

namespace Bypass {
void install() {
    HK::installSym("fopen", (void *)h_fopen, (void **)&o_fopen);
    HK::installSym("stat", (void *)h_stat, (void **)&o_stat);
    HK::installSym("lstat", (void *)h_lstat, (void **)&o_lstat);
    HK::installSym("access", (void *)h_access, (void **)&o_access);
    HK::installSym("opendir", (void *)h_opendir, (void **)&o_opendir);
    HK::installSym("getenv", (void *)h_getenv, (void **)&o_getenv);
    HK::installSym("ptrace", (void *)h_ptrace, (void **)&o_ptrace);
    HK::swizzleClass([NSFileManager class], @selector(fileExistsAtPath:), (IMP)h_fE, (IMP *)&o_fE);
    HK::swizzleClass([NSFileManager class], @selector(fileExistsAtPath:isDirectory:), (IMP)h_fED, (IMP *)&o_fED);
    HK::swizzleClass([UIApplication class], @selector(canOpenURL:), (IMP)h_cOU, (IMP *)&o_cOU);
    HK::installSym("_dyld_image_count", (void *)h_dyld_count, (void **)&o_dyld_count);
    HK::installSym("_dyld_get_image_name", (void *)h_dyld_name, (void **)&o_dyld_name);
    HK::installSym("dladdr", (void *)h_dladdr, (void **)&o_dladdr);
    HK::installSym("SecCodeCheckValidity", (void *)h_SecCV, (void **)&o_SecCV);
    HK::installSym("SecCodeCheckValidityWithErrors", (void *)h_SecCVWE, (void **)&o_SecCVWE);
    HK::installSym("SecStaticCodeCheckValidity", (void *)h_SecSCV, (void **)&o_SecSCV);
    HK::installSym("SecStaticCodeCheckValidityWithErrors", (void *)h_SecSCVWE, (void **)&o_SecSCVWE);
    HK::installSym("SecCodeCopySigningInformation", (void *)h_SecCSI, (void **)&o_SecCSI);
}
void applyAceHooks() {}
}
"""

def write_all(root="."):
    for path, content in files.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(content.lstrip("\n"))
    print("wrote", len(files), "files")

if __name__ == "__main__":
    write_all()
