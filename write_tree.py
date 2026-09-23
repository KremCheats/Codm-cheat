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
CODMCheat_FILES = CODMCheat.mm Src/Hooks.mm Src/Bypass.mm Src/Cheat.mm Src/Overlay.mm
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
        LOGI("CODMCheat entry (non-JB)");
        Bypass::install();
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

w("Src/Bypass.h", r"""
#ifndef BYPASS_H
#define BYPASS_H
namespace Bypass {
void install();
void scrubMainBinaryLoadCommands();
}
#endif
""")

w("Src/Bypass.mm", r"""
#import "Bypass.h"
#import "Common.h"
#import "Hooks.h"
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <dirent.h>
#import <errno.h>
#import <string.h>
#import <unistd.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <libkern/OSCacheControl.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 0x1f
#endif
#ifndef KERN_PROC_PROC
#define KERN_PROC_PROC 2
#endif

extern "C" int ptrace(int request, pid_t pid, caddr_t addr, int data);

// Use void* / uint32_t instead of Sec* types — no need to import Security headers.
typedef int32_t SecStatus;

static const char *kSuspect[] = {
    "CODMCheat", "frida", "Frida", "gum-js", "gadget", "cycript",
    "CydiaSubstrate", "MobileSubstrate", "Substrate", "libhooker",
    "ElleKit", "ellekit", "substitute", "Substitute", "TweakInject",
    "cynject", ".mahi", NULL
};

static inline bool isSuspect(const char *p) {
    if (!p) return false;
    for (int i = 0; kSuspect[i]; i++)
        if (strstr(p, kSuspect[i])) return true;
    return false;
}

static const char *kJbPaths[] = {
    "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
    "/Applications/Filza.app", "/Applications/Installer.app",
    "/Library/MobileSubstrate", "/Library/MobileSubstrate/MobileSubstrate.dylib",
    "/Library/MobileSubstrate/DynamicLibraries", "/Library/Substrate", "/Library/Themes",
    "/bin/bash", "/bin/sh", "/bin/zsh",
    "/usr/sbin/sshd", "/usr/bin/ssh", "/usr/bin/sshd",
    "/usr/libexec/sftp-server", "/usr/libexec/ssh-keysign",
    "/etc/apt", "/etc/ssh/sshd_config", "/private/etc/apt",
    "/private/var/lib/apt", "/private/var/lib/cydia", "/private/var/stash",
    "/private/var/tmp/cydia.log", "/private/var/mobile/Library/SBSettings/Themes",
    "/var/cache/apt", "/var/lib/dpkg", "/var/lib/cydia",
    "/var/jb", "/var/jb/usr/bin/ssh", "/var/jb/Library/MobileSubstrate",
    "/var/jb/Applications/Sileo.app", "/var/jb/Applications/Zebra.app",
    NULL
};

static inline bool isJbPath(const char *p) {
    if (!p) return false;
    for (int i = 0; kJbPaths[i]; i++)
        if (strcmp(p, kJbPaths[i]) == 0) return true;
    return isSuspect(p);
}

namespace Bypass {

void scrubMainBinaryLoadCommands() {
    const struct mach_header_64 *hdr =
        (const struct mach_header_64 *)_dyld_get_image_header(0);
    if (!hdr) return;
    uint8_t *base = (uint8_t *)hdr;
    struct load_command *lc =
        (struct load_command *)(base + sizeof(struct mach_header_64));
    for (uint32_t i = 0; i < hdr->ncmds && lc; i++) {
        uint32_t cmd = lc->cmd;
        if (cmd == LC_LOAD_DYLIB || cmd == LC_LOAD_WEAK_DYLIB || cmd == LC_REEXPORT_DYLIB) {
            struct dylib_command *dc = (struct dylib_command *)lc;
            const char *name = (const char *)((uint8_t *)dc + dc->dylib.name.offset);
            if (isSuspect(name)) {
                vm_protect(mach_task_self(), (uintptr_t)dc & ~0xFFF, 0x4000,
                           false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
                dc->cmd = LC_NOTE;
                sys_icache_invalidate((void *)dc, lc->cmdsize);
                LOGI("scrubbed LC_LOAD_DYLIB: %s", name);
            }
        }
        lc = (struct load_command *)((uint8_t *)lc + lc->cmdsize);
    }
}

}

static FILE *(*o_fopen)(const char *, const char *);
static FILE *h_fopen(const char *p, const char *m) {
    if (isJbPath(p)) { errno = ENOENT; return NULL; }
    return o_fopen(p, m);
}
static int (*o_stat)(const char *, struct stat *);
static int h_stat(const char *p, struct stat *b) {
    if (isJbPath(p)) { errno = ENOENT; return -1; }
    return o_stat(p, b);
}
static int (*o_lstat)(const char *, struct stat *);
static int h_lstat(const char *p, struct stat *b) {
    if (isJbPath(p)) { errno = ENOENT; return -1; }
    return o_lstat(p, b);
}
static int (*o_access)(const char *, int);
static int h_access(const char *p, int mode) {
    if (isJbPath(p)) { errno = ENOENT; return -1; }
    return o_access(p, mode);
}
static DIR *(*o_opendir)(const char *);
static DIR *h_opendir(const char *p) {
    if (isJbPath(p)) { errno = ENOENT; return NULL; }
    return o_opendir(p);
}
static char *(*o_getenv)(const char *);
static char *h_getenv(const char *name) {
    if (!name) return NULL;
    if (strncmp(name, "DYLD_", 5) == 0) return NULL;
    if (strstr(name, "FRIDA")) return NULL;
    if (strstr(name, "SUBSTRATE")) return NULL;
    return o_getenv(name);
}

static int (*o_ptrace)(int, pid_t, caddr_t, int);
static int h_ptrace(int req, pid_t pid, caddr_t a, int d) {
    if (req == PT_DENY_ATTACH) return 0;
    return o_ptrace(req, pid, a, d);
}

static int (*o_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int h_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp,
                    void *newp, size_t newlen) {
    int r = o_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (r != 0 || !name || !oldp) return r;
    if (namelen >= 4 && name[0] == CTL_KERN && name[1] == KERN_PROC &&
        (name[2] == KERN_PROC_PID || name[2] == KERN_PROC_PROC)) {
        struct kinfo_proc *kp = (struct kinfo_proc *)oldp;
        kp->kp_proc.p_flag &= ~P_TRACED;
    }
    return r;
}

static uint32_t (*o_dyld_count)(void);
static uint32_t h_dyld_count(void) {
    uint32_t real = o_dyld_count();
    uint32_t hide = 0;
    for (uint32_t i = 0; i < real; i++)
        if (isSuspect(_dyld_get_image_name(i))) hide++;
    return real - hide;
}
static const char *(*o_dyld_name)(uint32_t);
static const char *h_dyld_name(uint32_t idx) {
    uint32_t real = o_dyld_count();
    uint32_t seen = 0;
    for (uint32_t i = 0; i < real; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (isSuspect(nm)) continue;
        if (seen == idx) return o_dyld_name(i);
        seen++;
    }
    return o_dyld_name(idx);
}
static const struct mach_header *(*o_dyld_hdr)(uint32_t);
static const struct mach_header *h_dyld_hdr(uint32_t idx) {
    uint32_t real = o_dyld_count();
    uint32_t seen = 0;
    for (uint32_t i = 0; i < real; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (isSuspect(nm)) continue;
        if (seen == idx) return o_dyld_hdr(i);
        seen++;
    }
    return o_dyld_hdr(idx);
}
static intptr_t (*o_dyld_slide)(uint32_t);
static intptr_t h_dyld_slide(uint32_t idx) {
    uint32_t real = o_dyld_count();
    uint32_t seen = 0;
    for (uint32_t i = 0; i < real; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (isSuspect(nm)) continue;
        if (seen == idx) return o_dyld_slide(i);
        seen++;
    }
    return o_dyld_slide(idx);
}
static int (*o_dladdr)(const void *, Dl_info *);
static int h_dladdr(const void *addr, Dl_info *info) {
    int r = o_dladdr(addr, info);
    if (r && info && info->dli_fname && isSuspect(info->dli_fname)) {
        info->dli_fname = "/usr/lib/system/libsystem_kernel.dylib";
        info->dli_fbase = (void *)0x1;
        info->dli_sname = NULL;
        info->dli_saddr = NULL;
    }
    return r;
}

// Security — untyped refs, we don't need real headers.
static SecStatus (*o_SecCV)(void *, uint32_t, void *);
static SecStatus h_SecCV(void *c, uint32_t f, void *r) { return 0; }

static SecStatus (*o_SecCVWE)(void *, uint32_t, void *, CFErrorRef *);
static SecStatus h_SecCVWE(void *c, uint32_t f, void *r, CFErrorRef *e) {
    if (e) *e = NULL;
    return 0;
}
static SecStatus (*o_SecSCV)(void *, uint32_t, void *);
static SecStatus h_SecSCV(void *c, uint32_t f, void *r) { return 0; }

static SecStatus (*o_SecSCVWE)(void *, uint32_t, void *, CFErrorRef *);
static SecStatus h_SecSCVWE(void *c, uint32_t f, void *r, CFErrorRef *e) {
    if (e) *e = NULL;
    return 0;
}
static SecStatus (*o_SecCSI)(void *, uint32_t, CFDictionaryRef *);
static SecStatus h_SecCSI(void *code, uint32_t flags, CFDictionaryRef *info) {
    SecStatus r = o_SecCSI(code, flags, info);
    if (r == 0 && info && *info) {
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
static BOOL h_fE(NSFileManager *s, SEL c, NSString *p) {
    if (isJbPath([p UTF8String])) return NO;
    return o_fE(s, c, p);
}
static BOOL (*o_fED)(NSFileManager *, SEL, NSString *, BOOL *);
static BOOL h_fED(NSFileManager *s, SEL c, NSString *p, BOOL *d) {
    if (isJbPath([p UTF8String])) { if (d) *d = NO; return NO; }
    return o_fED(s, c, p, d);
}
static BOOL (*o_cOU)(UIApplication *, SEL, NSURL *);
static BOOL h_cOU(UIApplication *s, SEL c, NSURL *u) {
    NSString *sc = [[u scheme] lowercaseString];
    if ([sc isEqualToString:@"cydia"] || [sc isEqualToString:@"sileo"] ||
        [sc isEqualToString:@"zbra"]  || [sc isEqualToString:@"filza"] ||
        [sc isEqualToString:@"undecimus"] || [sc isEqualToString:@"checkra1n"])
        return NO;
    return o_cOU(s, c, u);
}

namespace Bypass {

void install() {
    LOGI("Bypass (non-JB) installing...");
    scrubMainBinaryLoadCommands();

    HK::installSym("fopen",   (void *)h_fopen,   (void **)&o_fopen);
    HK::installSym("stat",    (void *)h_stat,    (void **)&o_stat);
    HK::installSym("lstat",   (void *)h_lstat,   (void **)&o_lstat);
    HK::installSym("access",  (void *)h_access,  (void **)&o_access);
    HK::installSym("opendir", (void *)h_opendir, (void **)&o_opendir);
    HK::installSym("getenv",  (void *)h_getenv,  (void **)&o_getenv);

    HK::installSym("ptrace",  (void *)h_ptrace,  (void **)&o_ptrace);
    HK::installSym("sysctl",  (void *)h_sysctl,  (void **)&o_sysctl);

    HK::swizzleClass([NSFileManager class], @selector(fileExistsAtPath:),
                     (IMP)h_fE, (IMP *)&o_fE);
    HK::swizzleClass([NSFileManager class], @selector(fileExistsAtPath:isDirectory:),
                     (IMP)h_fED, (IMP *)&o_fED);
    HK::swizzleClass([UIApplication class], @selector(canOpenURL:),
                     (IMP)h_cOU, (IMP *)&o_cOU);

    HK::installSym("_dyld_image_count",             (void *)h_dyld_count, (void **)&o_dyld_count);
    HK::installSym("_dyld_get_image_name",          (void *)h_dyld_name,  (void **)&o_dyld_name);
    HK::installSym("_dyld_get_image_header",        (void *)h_dyld_hdr,   (void **)&o_dyld_hdr);
    HK::installSym("_dyld_get_image_vmaddr_slide",  (void *)h_dyld_slide, (void **)&o_dyld_slide);
    HK::installSym("dladdr",                        (void *)h_dladdr,     (void **)&o_dladdr);

    HK::installSym("SecCodeCheckValidity",                 (void *)h_SecCV,   (void **)&o_SecCV);
    HK::installSym("SecCodeCheckValidityWithErrors",       (void *)h_SecCVWE, (void **)&o_SecCVWE);
    HK::installSym("SecStaticCodeCheckValidity",           (void *)h_SecSCV,  (void **)&o_SecSCV);
    HK::installSym("SecStaticCodeCheckValidityWithErrors", (void *)h_SecSCVWE,(void **)&o_SecSCVWE);
    HK::installSym("SecCodeCopySigningInformation",        (void *)h_SecCSI,  (void **)&o_SecCSI);

    LOGI("Bypass (non-JB) installed");
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
    LOGI("Cheat::start");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CheatOverlay shared] attach];
        [[CheatOverlay shared] setInfoText:@"CODM (non-JB)\nbypass active\nloaded"];
    });
}
- (void)stop {}
@end
""")

print("wrote tree with bypass")
