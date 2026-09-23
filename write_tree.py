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
CODMCheat_FILES = CODMCheat.mm Src/Hooks.mm Src/fishhook.c Src/Bypass.mm Src/Cheat.mm Src/Overlay.mm
CODMCheat_CFLAGS = -fobjc-arc -I./Src -std=c++17 -Wno-unused-function -Wno-deprecated-declarations
CODMCheat_CCFLAGS = -fobjc-arc -I./Src -std=c++17
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
        LOGI("CODMCheat entry (non-JB, fishhook)");
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

w("Src/fishhook.h", r"""
#ifndef fishhook_h
#define fishhook_h
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
struct rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};
int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel);
int rebind_symbols_image(void *header, intptr_t slide,
                         struct rebinding rebindings[], size_t rebindings_nel);
#ifdef __cplusplus
}
#endif
#endif
""")

w("Src/fishhook.c", r"""
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include "fishhook.h"

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
typedef struct nlist_64 nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT_64
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
typedef struct nlist nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT
#endif

struct rebindings_entry {
    struct rebinding *rebindings;
    size_t rebindings_nel;
    struct rebindings_entry *next;
};

static struct rebindings_entry *_rebindings_head;

static int prepend_rebindings(struct rebindings_entry **rebindings_head,
                              struct rebinding rebindings[], size_t nel) {
    struct rebindings_entry *new_entry = (struct rebindings_entry *)malloc(sizeof(struct rebindings_entry));
    if (!new_entry) return -1;
    new_entry->rebindings = (struct rebinding *)malloc(sizeof(struct rebinding) * nel);
    if (!new_entry->rebindings) { free(new_entry); return -1; }
    memcpy(new_entry->rebindings, rebindings, sizeof(struct rebinding) * nel);
    new_entry->rebindings_nel = nel;
    new_entry->next = *rebindings_head;
    *rebindings_head = new_entry;
    return 0;
}

static void perform_rebinding_with_section(struct rebindings_entry *rebindings,
                                            section_t *section, intptr_t slide,
                                            nlist_t *symtab, char *strtab,
                                            uint32_t *indirect_symtab) {
    uint32_t *indirect_symbol_indices = indirect_symtab + section->reserved1;
    void **indirect_symbol_bindings = (void **)((uintptr_t)slide + section->addr);
    for (uint i = 0; i < section->size / sizeof(void *); i++) {
        uint32_t symtab_index = indirect_symbol_indices[i];
        if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL ||
            symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        char *symbol_name = strtab + strtab_offset;
        int symbol_name_longer_than_1 = symbol_name[0] && symbol_name[1];
        struct rebindings_entry *cur = rebindings;
        while (cur) {
            for (uint j = 0; j < cur->rebindings_nel; j++) {
                if (symbol_name_longer_than_1 &&
                    strcmp(&symbol_name[1], cur->rebindings[j].name) == 0) {
                    if (cur->rebindings[j].replaced != NULL &&
                        indirect_symbol_bindings[i] != cur->rebindings[j].replacement) {
                        *(cur->rebindings[j].replaced) = indirect_symbol_bindings[i];
                    }
                    indirect_symbol_bindings[i] = cur->rebindings[j].replacement;
                    goto symbol_loop;
                }
            }
            cur = cur->next;
        }
    symbol_loop:;
    }
}

static void rebind_symbols_for_image(struct rebindings_entry *rebindings,
                                      const struct mach_header *header, intptr_t slide) {
    Dl_info info;
    if (dladdr(header, &info) == 0) return;
    segment_command_t *cur_seg_cmd;
    segment_command_t *linkedit_segment = NULL;
    struct symtab_command *symtab_cmd = NULL;
    struct dysymtab_command *dysymtab_cmd = NULL;
    uintptr_t cur = (uintptr_t)header + sizeof(mach_header_t);
    for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (segment_command_t *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) linkedit_segment = cur_seg_cmd;
        } else if (cur_seg_cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command *)cur_seg_cmd;
        } else if (cur_seg_cmd->cmd == LC_DYSYMTAB) {
            dysymtab_cmd = (struct dysymtab_command *)cur_seg_cmd;
        }
    }
    if (!symtab_cmd || !dysymtab_cmd || !linkedit_segment || !dysymtab_cmd->nindirectsyms) return;
    uintptr_t linkedit_base = (uintptr_t)slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
    nlist_t *symtab = (nlist_t *)(linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);
    uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);
    cur = (uintptr_t)header + sizeof(mach_header_t);
    for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (segment_command_t *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_DATA) != 0 &&
                strcmp(cur_seg_cmd->segname, "__DATA_CONST") != 0 &&
                strcmp(cur_seg_cmd->segname, "__AUTH_CONST") != 0 &&
                strcmp(cur_seg_cmd->segname, "__DATA_DIRTY") != 0) continue;
            for (uint j = 0; j < cur_seg_cmd->nsects; j++) {
                section_t *sect = (section_t *)(cur + sizeof(segment_command_t)) + j;
                if ((sect->flags & SECTION_TYPE) == S_LAZY_SYMBOL_POINTERS) {
                    perform_rebinding_with_section(rebindings, sect, slide, symtab, strtab, indirect_symtab);
                }
                if ((sect->flags & SECTION_TYPE) == S_NON_LAZY_SYMBOL_POINTERS) {
                    perform_rebinding_with_section(rebindings, sect, slide, symtab, strtab, indirect_symtab);
                }
            }
        }
    }
}

static void _rebind_symbols_for_image(const struct mach_header *header, intptr_t slide) {
    rebind_symbols_for_image(_rebindings_head, header, slide);
}

int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel) {
    int retval = prepend_rebindings(&_rebindings_head, rebindings, rebindings_nel);
    if (retval < 0) return retval;
    if (!_rebindings_head->next) {
        _dyld_register_func_for_add_image(_rebind_symbols_for_image);
    } else {
        uint32_t c = _dyld_image_count();
        for (uint32_t i = 0; i < c; i++) {
            _rebind_symbols_for_image(_dyld_get_image_header(i),
                                      _dyld_get_image_vmaddr_slide(i));
        }
    }
    return retval;
}
""")

w("Src/Hooks.h", r"""
#ifndef HOOKS_H
#define HOOKS_H
#include <stdint.h>
#include <objc/runtime.h>
namespace HK {
void rebind(const char *name, void *replacement, void **orig);
bool swizzleClass(Class cls, SEL sel, IMP replacement, IMP *original);
}
#endif
""")

w("Src/Hooks.mm", r"""
#import "Hooks.h"
#import <objc/runtime.h>
extern "C" {
#include "fishhook.h"
}
namespace HK {
void rebind(const char *name, void *replacement, void **orig) {
    struct rebinding rb;
    rb.name = name;
    rb.replacement = replacement;
    rb.replaced = orig;
    rebind_symbols(&rb, 1);
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
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 0x1f
#endif
#ifndef KERN_PROC_PROC
#define KERN_PROC_PROC 2
#endif
extern "C" int ptrace(int request, pid_t pid, caddr_t addr, int data);
typedef int32_t SecStatus;

static const char *kSuspect[] = {
    "CODMCheat", "frida", "Frida", "gum-js", "gadget", "cycript",
    "CydiaSubstrate", "MobileSubstrate", "Substrate_name", "libhooker",
    "ElleKit",)( "ellekit", "substitute", "Subuintstitute", "TweakInject",
    "cynject", ".mahi", NULL32
};
static inline bool isSuspect(const char *p) {
_t    if (!p) return false;
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

// --- libc ---
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

// --- dyld virtualization ---
static uint32_t (*o_dyld_count)(void);
static uint32_t h_dyld_count(void) {
    uint32_t real = o_dyld_count();
    uint32_t hide = 0;
    for (uint32_t i = 0; i < real; i++)
        if (isSuspect(_dyld_get_image_name(i))) hide++;
    return real - hide;
}
static const char *(*o_dyld);
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
statico int h_dladdr(const void *addr, Dl_info *info) {
    int r = o_dladdr(addr, info);
    if (r && info && info->dli_fname && isSuspect(info->dli_fname)) {
        info->dli_fname = "/usr/lib/system/libsystem_kernel.dylib";
        info->dli_fbase = (void *)0x1;
        info->dli_sname = NULL;
        info->dli_saddr = NULL;
    }
    return r;
}

// --- Security ---
static SecStatus (*o_SecCV)(void *, uint32_t, void *);
static SecStatus h_SecCV(void *c, uint32_t f, void *r) { return 0; }
static SecStatus (*o_SecCVWE)(void *, uint32_t, void *, CFErrorRef *);
static SecStatus h_SecCVWE(void *c, uint32_t f, void *r, CFErrorRef *e) {
    if (e) *e = NULL; return 0;
}
static SecStatus (*o_SecSCV)(void *, uint32_t, void *);
static SecStatus h_SecSCV(void *c, uint32_t f, void *r) { return 0; }
static SecStatus (*o_S_fecSCVWE)(void *,E uint32_t, void *, CFErrorRef *);
static SecStatus h_SecSCVWE(void *c, uint32_t f, void *r, CFErrorRef *e) {
    if (e) *e = NULL; return 0;
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

// --- Obj-C ---
static BOOL (*)(NSFileManager *, SEL, NSString *);
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
    LOGI("Bypass installing (fishhook)");
    HK::rebind("fopen",   (void *)h_fopen,   (void **)&o_fopen);
    HK::rebind("stat",    (void *)h_stat,    (void **)&o_stat);
    HK::rebind("lstat",   (void *)h_lstat,   (void **)&o_lstat);
    HK::rebind("access",  (void *)h_access,  (void **)&o_access);
    HK::rebind("opendir", (void *)h_opendir, (void **)&o_opendir);
    HK::rebind("getenv",  (void *)h_getenv,  (void **)&o_getenv);
    HK::rebind("ptrace",  (void *)h_ptrace,  (void **)&o_ptrace);
    HK::rebind("sysctl",  (void *)h_sysctl,  (void **)&o_sysctl);

    HK::swizzleClass([NSFileManager class], @selector(fileExistsAtPath:),
                     (IMP)h_fE, (IMP *)&o_fE);
    HK::swizzleClass([NSFileManager class], @selector(fileExistsAtPath:isDirectory:),
                     (IMP)h_fED, (IMP *)&o_fED);
    HK::swizzleClass([UIApplication class], @selector(canOpenURL:),
                     (IMP)h_cOU, (IMP *)&o_cOU);

    HK::rebind("_dyld_image_count",             (void *)h_dyld_count, (void **)&o_dyld_count);
    HK::rebind("_dyld_get_image_name",          (void *)h_dyld_name,  (void **)&o_dyld_name);
    HK::rebind("_dyld_get_image_header",        (void *)h_dyld_hdr,   (void **)&o_dyld_hdr);
    HK::rebind("_dyld_get_image_vmaddr_slide",  (void *)h_dyld_slide, (void **)&o_dyld_slide);
    HK::rebind("dladdr",                        (void *)h_dladdr,     (void **)&o_dladdr);

    HK::rebind("SecCodeCheckValidity",                 (void *)h_SecCV,   (void **)&o_SecCV);
    HK::rebind("SecCodeCheckValidityWithErrors",       (void *)h_SecCVWE, (void **)&o_SecCVWE);
    HK::rebind("SecStaticCodeCheckValidity",           (void *)h_SecSCV,  (void **)&o_SecSCV);
    HK::rebind("SecStaticCodeCheckValidityWithErrors", (void *)h_SecSCVWE,(void **)&o_SecSCVWE);
    HK::rebind("SecCodeCopySigningInformation",        (void *)h_SecCSI,  (void **)&o_SecCSI);

    LOGI("Bypass installed");
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
        [[CheatOverlay shared] setInfoText:@"CODM (non-JB)\nfishhook bypass active"];
    });
}
- (void)stop {}
@end
""")

print("wrote fishhook-based tree")
