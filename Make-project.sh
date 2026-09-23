#!/usr/bin/env bash
# Bootstraps the CODMCheat-NonJB project tree.
# Run:   bash make_project.sh
# Result: ./CODMCheat-NonJB/ with all source, scripts, and CI workflow.

set -euo pipefail
ROOT="CODMCheat-NonJB"

mkdir -p "$ROOT"/{Src,Recon,vendor/fishhook,vendor/dobby,.github/workflows}
cd "$ROOT"

# ─────────────────────────────────────────────────────────────
# Makefile
# ─────────────────────────────────────────────────────────────
cat > Makefile <<'FILE'
TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CODMCheat

CODMCheat_FILES = CODMCheat.mm \
    Src/Hooks.mm \
    Src/PatternScanner.mm \
    Src/Bypass.mm \
    Src/Unity.mm \
    Src/Overlay.mm \
    Src/Cheat.mm \
    vendor/fishhook/fishhook.c

CODMCheat_CFLAGS = -fobjc-arc -I./Src -I./vendor/dobby/include -I./vendor/fishhook \
                   -std=c++17 -Wno-unused-function -Wno-deprecated-declarations -Wno-comment
CODMCheat_CCFLAGS = -fobjc-arc -I./Src -I./vendor/dobby/include -I./vendor/fishhook -std=c++17
CODMCheat_LDFLAGS = -L./vendor/dobby/build -ldobby
CODMCheat_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics Security

include $(THEOS_MAKE_PATH)/tweak.mk

after-all::
	@mkdir -p ./dist
	@lipo -create \
	    .theos/obj/arm64/CODMCheat.dylib \
	    .theos/obj/arm64e/CODMCheat.dylib \
	    -output ./dist/CODMCheat.dylib 2>/dev/null || \
	 cp .theos/obj/arm64/CODMCheat.dylib ./dist/CODMCheat.dylib
	@echo "→ dist/CODMCheat.dylib ready"
FILE

# ─────────────────────────────────────────────────────────────
# CODMCheat.mm
# ─────────────────────────────────────────────────────────────
cat > CODMCheat.mm <<'FILE'
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
        LOGI("CODMCheat (non-JB) loading in %s",
             [[[NSBundle mainBundle] bundleIdentifier] UTF8String]);
        Bypass::install();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            Cheat::shared()->start();
        });
    }
}
FILE

# ─────────────────────────────────────────────────────────────
# Src/Common.h
# ─────────────────────────────────────────────────────────────
cat > Src/Common.h <<'FILE'
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
struct Vec2 { float x, y; };
struct Vec3 { float x, y, z; };

static inline Vec3 vec3_sub(Vec3 a, Vec3 b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
static inline float vec3_len(Vec3 v) { return sqrtf(v.x*v.x + v.y*v.y + v.z*v.z); }

#endif
FILE

# ─────────────────────────────────────────────────────────────
# Src/Hooks.h
# ─────────────────────────────────────────────────────────────
cat > Src/Hooks.h <<'FILE'
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
FILE

# ─────────────────────────────────────────────────────────────
# Src/Hooks.mm
# ─────────────────────────────────────────────────────────────
cat > Src/Hooks.mm <<'FILE'
#import "Hooks.h"
#import "Common.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#include <dobby.h>

namespace HK {

bool install(void *target, void *replacement, void **orig) {
    if (!target) return false;
    int r = DobbyHook(target, replacement, orig);
    if (r != 0) { LOGI("DobbyHook failed for %p (%d)", target, r); return false; }
    return true;
}

bool installSym(const char *sym, void *replacement, void **orig) {
    void *p = dlsym(RTLD_DEFAULT, sym);
    if (!p) { LOGI("dlsym miss: %s", sym); return false; }
    return install(p, replacement, orig);
}

bool swizzleClass(Class cls, SEL sel, IMP replacement, IMP *original) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        m = class_getClassMethod(cls, sel);
        if (!m) return false;
    }
    IMP old = method_getImplementation(m);
    if (original) *original = old;
    method_setImplementation(m, replacement);
    return true;
}

}
FILE

# ─────────────────────────────────────────────────────────────
# Src/PatternScanner.h
# ─────────────────────────────────────────────────────────────
cat > Src/PatternScanner.h <<'FILE'
#ifndef PATTERN_SCANNER_H
#define PATTERN_SCANNER_H

#include <stdint.h>
#include <stddef.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

namespace PS {
bool compile(const char *sig, uint8_t *bytes, uint8_t *mask, size_t *len);
uintptr_t scanMain(const char *sig);
uintptr_t scanAll(const char *sig);
uintptr_t scanFuncMain(const char *sig);
uintptr_t resolveRip(uintptr_t instr_addr, size_t instr_len, int32_t disp);
uintptr_t resolveAdrpAdd(uintptr_t adrp_addr, uintptr_t add_addr);
}

#endif
FILE

# ─────────────────────────────────────────────────────────────
# Src/PatternScanner.mm
# ─────────────────────────────────────────────────────────────
cat > Src/PatternScanner.mm <<'FILE'
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

bool compile(const char *sig, uint8_t *bytes, uint8_t *mask, size_t *len) {
    size_t n = 0;
    const char *p = sig;
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
    *len = n;
    return n > 0;
}

static uintptr_t scanRange(const uint8_t *base, size_t size,
                           const uint8_t *bytes, const uint8_t *mask, size_t len) {
    if (size < len) return 0;
    for (size_t i = 0; i <= size - len; i++) {
        bool ok = true;
        for (size_t j = 0; j < len; j++) {
            if (mask[j] && base[i + j] != bytes[j]) { ok = false; break; }
        }
        if (ok) return (uintptr_t)(base + i);
    }
    return 0;
}

static uintptr_t scanImage(const struct mach_header_64 *hdr, intptr_t slide, const char *sig) {
    uint8_t bytes[512]; uint8_t mask[512]; size_t len;
    if (!compile(sig, bytes, mask, &len)) return 0;
    if (len > sizeof(bytes)) return 0;

    const uint8_t *base = (const uint8_t *)hdr;
    const struct load_command *lc =
        (const struct load_command *)(base + sizeof(struct mach_header_64));

    for (uint32_t i = 0; i < hdr->ncmds && lc; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strcmp(seg->segname, "__TEXT") == 0) {
                uintptr_t segAddr = (uintptr_t)seg->vmaddr + slide;
                uintptr_t r = scanRange((const uint8_t *)segAddr, seg->vmsize,
                                        bytes, mask, len);
                if (r) return r;
            }
        }
        lc = (const struct load_command *)((uint8_t *)lc + lc->cmdsize);
    }
    return 0;
}

uintptr_t scanMain(const char *sig) {
    const struct mach_header_64 *hdr =
        (const struct mach_header_64 *)_dyld_get_image_header(0);
    return scanImage(hdr, _dyld_get_image_vmaddr_slide(0), sig);
}

uintptr_t scanAll(const char *sig) {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const struct mach_header_64 *hdr =
            (const struct mach_header_64 *)_dyld_get_image_header(i);
        uintptr_t r = scanImage(hdr, _dyld_get_image_vmaddr_slide(i), sig);
        if (r) return r;
    }
    return 0;
}

uintptr_t resolveRip(uintptr_t instr_addr, size_t instr_len, int32_t disp) {
    return instr_addr + instr_len + disp;
}

uintptr_t resolveAdrpAdd(uintptr_t adrp_addr, uintptr_t add_addr) {
    uint32_t adrp = *(uint32_t *)adrp_addr;
    uint32_t add  = *(uint32_t *)add_addr;
    int64_t immlo = (adrp >> 29) & 0x3;
    int64_t immhi = (adrp >> 5) & 0x7FFFF;
    int64_t imm = (immhi << 2) | immlo;
    if (imm & (1LL << 20)) imm -= (1LL << 21);
    uintptr_t page = (adrp_addr & ~0xFFFULL) + (imm << 12);
    uint32_t imm12 = (add >> 10) & 0xFFF;
    bool shift = (add >> 22) & 1;
    if (shift) imm12 <<= 12;
    return page + imm12;
}

uintptr_t scanFuncMain(const char *sig) { return scanMain(sig); }

}
FILE

# ─────────────────────────────────────────────────────────────
# Src/Bypass.h
# ─────────────────────────────────────────────────────────────
cat > Src/Bypass.h <<'FILE'
#ifndef BYPASS_H
#define BYPASS_H

namespace Bypass {
    void install();
    void applyAceHooks();
    void scrubMainBinaryLoadCommands();
}

#endif
FILE

# ─────────────────────────────────────────────────────────────
# Src/Bypass.mm
# ─────────────────────────────────────────────────────────────
cat > Src/Bypass.mm <<'FILE'
#import "Bypass.h"
#import "Common.h"
#import "Hooks.h"
#import "PatternScanner.h"
#include <dobby.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <sys/ptrace.h>
#import <dlfcn.h>
#import <dirent.h>
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static const char *kSuspectSubstrings[] = {
    "CODMCheat", "frida", "Frida", "gum-js", "gadget", "cycript",
    "CydiaSubstrate", "MobileSubstrate", "Substrate", "libhooker",
    "ElleKit", "ellekit", "substitute", "Substitute", "TweakInject",
    "cynject", ".mahi", NULL
};

static inline bool isSuspectImage(const char *p) {
    if (!p) return false;
    for (int i = 0; kSuspectSubstrings[i]; i++)
        if (strstr(p, kSuspectSubstrings[i])) return true;
    return false;
}

static const char *kJbPaths[] = {
    "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
    "/Applications/Filza.app", "/Library/MobileSubstrate", "/Library/Substrate",
    "/bin/bash", "/bin/sh", "/bin/zsh", "/usr/sbin/sshd", "/usr/bin/ssh",
    "/etc/apt", "/etc/ssh/sshd_config", "/private/var/lib/apt", "/private/var/lib/cydia",
    "/private/var/stash", "/var/cache/apt", "/var/lib/dpkg", "/var/lib/cydia",
    "/var/jb", "/var/jb/usr/bin/ssh", "/var/jb/Library/MobileSubstrate",
    "/var/jb/Applications/Sileo.app", "/var/jb/Applications/Zebra.app",
    NULL
};

static inline bool isJbPath(const char *p) {
    if (!p) return false;
    for (int i = 0; kJbPaths[i]; i++)
        if (strcmp(p, kJbPaths[i]) == 0) return true;
    if (isSuspectImage(p)) return true;
    return false;
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
            if (isSuspectImage(name)) {
                vm_protect(mach_task_self(), (uintptr_t)dc & ~0xFFF, 0x4000, false,
                           VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
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
static int h_ptrace(int req, pid_t pid, caddr_t addr, int data) {
    if (req == PT_DENY_ATTACH) return 0;
    return o_ptrace(req, pid, addr, data);
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

static int g_ourIdx = -1;

static uint32_t (*o_dyld_count)(void);
static uint32_t h_dyld_count(void) {
    uint32_t real = o_dyld_count();
    uint32_t hide = 0;
    for (uint32_t i = 0; i < real; i++)
        if (isSuspectImage(_dyld_get_image_name(i))) hide++;
    return real - hide;
}

static const char *(*o_dyld_name)(uint32_t);
static const char *h_dyld_name(uint32_t idx) {
    uint32_t real = o_dyld_count();
    uint32_t seen = 0;
    for (uint32_t i = 0; i < real; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (isSuspectImage(nm)) continue;
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
        if (isSuspectImage(nm)) continue;
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
        if (isSuspectImage(nm)) continue;
        if (seen == idx) return o_dyld_slide(i);
        seen++;
    }
    return o_dyld_slide(idx);
}

static int (*o_dladdr)(const void *, Dl_info *);
static int h_dladdr(const void *addr, Dl_info *info) {
    int r = o_dladdr(addr, info);
    if (r && info && info->dli_fname && isSuspectImage(info->dli_fname)) {
        info->dli_fname = "/usr/lib/system/libsystem_kernel.dylib";
        info->dli_fbase = (void *)0x1;
        info->dli_sname = NULL;
        info->dli_saddr = NULL;
    }
    return r;
}

static OSStatus (*o_SecCodeCheckValidity)(SecCodeRef, SecCSFlags, SecRequirementRef);
static OSStatus h_SecCodeCheckValidity(SecCodeRef c, SecCSFlags f, SecRequirementRef r) { return errSecSuccess; }

static OSStatus (*o_SecCodeCheckValidityWithErrors)(SecCodeRef, SecCSFlags, SecRequirementRef, CFErrorRef *);
static OSStatus h_SecCodeCheckValidityWithErrors(SecCodeRef c, SecCSFlags f, SecRequirementRef r, CFErrorRef *e) {
    if (e) *e = NULL; return errSecSuccess;
}

static OSStatus (*o_SecStaticCodeCheckValidity)(SecStaticCodeRef, SecCSFlags, SecRequirementRef);
static OSStatus h_SecStaticCodeCheckValidity(SecStaticCodeRef c, SecCSFlags f, SecRequirementRef r) { return errSecSuccess; }

static OSStatus (*o_SecStaticCodeCheckValidityWithErrors)(SecStaticCodeRef, SecCSFlags, SecRequirementRef, CFErrorRef *);
static OSStatus h_SecStaticCodeCheckValidityWithErrors(SecStaticCodeRef c, SecCSFlags f, SecRequirementRef r, CFErrorRef *e) {
    if (e) *e = NULL; return errSecSuccess;
}

static OSStatus (*o_SecCodeCopySigningInformation)(SecCodeRef, SecCSFlags, CFDictionaryRef *);
static OSStatus h_SecCodeCopySigningInformation(SecCodeRef code, SecCSFlags flags, CFDictionaryRef *info) {
    OSStatus r = o_SecCodeCopySigningInformation(code, flags, info);
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

static BOOL (*o_fileExists)(NSFileManager *, SEL, NSString *);
static BOOL h_fileExists(NSFileManager *self, SEL _cmd, NSString *path) {
    if (isJbPath([path UTF8String])) return NO;
    return o_fileExists(self, _cmd, path);
}

static BOOL (*o_fileExistsDir)(NSFileManager *, SEL, NSString *, BOOL *);
static BOOL h_fileExistsDir(NSFileManager *self, SEL _cmd, NSString *path, BOOL *isDir) {
    if (isJbPath([path UTF8String])) { if (isDir) *isDir = NO; return NO; }
    return o_fileExistsDir(self, _cmd, path, isDir);
}

static BOOL (*o_canOpenURL)(UIApplication *, SEL, NSURL *);
static BOOL h_canOpenURL(UIApplication *self, SEL _cmd, NSURL *url) {
    NSString *scheme = [[url scheme] lowercaseString];
    if ([scheme isEqualToString:@"cydia"] || [scheme isEqualToString:@"sileo"] ||
        [scheme isEqualToString:@"zbra"]  || [scheme isEqualToString:@"filza"] ||
        [scheme isEqualToString:@"undecimus"] || [scheme isEqualToString:@"checkra1n"])
        return NO;
    return o_canOpenURL(self, _cmd, url);
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
                     (IMP)h_fileExists, (IMP *)&o_fileExists);
    HK::swizzleClass([NSFileManager class], @selector(fileExistsAtPath:isDirectory:),
                     (IMP)h_fileExistsDir, (IMP *)&o_fileExistsDir);
    HK::swizzleClass([UIApplication class], @selector(canOpenURL:),
                     (IMP)h_canOpenURL, (IMP *)&o_canOpenURL);

    HK::installSym("_dyld_image_count",      (void *)h_dyld_count, (void **)&o_dyld_count);
    HK::installSym("_dyld_get_image_name",   (void *)h_dyld_name,  (void **)&o_dyld_name);
    HK::installSym("_dyld_get_image_header", (void *)h_dyld_hdr,   (void **)&o_dyld_hdr);
    HK::installSym("_dyld_get_image_vmaddr_slide", (void *)h_dyld_slide, (void **)&o_dyld_slide);
    HK::installSym("dladdr",                 (void *)h_dladdr,     (void **)&o_dladdr);

    HK::installSym("SecCodeCheckValidity",                 (void *)h_SecCodeCheckValidity,                 (void **)&o_SecCodeCheckValidity);
    HK::installSym("SecCodeCheckValidityWithErrors",       (void *)h_SecCodeCheckValidityWithErrors,       (void **)&o_SecCodeCheckValidityWithErrors);
    HK::installSym("SecStaticCodeCheckValidity",           (void *)h_SecStaticCodeCheckValidity,           (void **)&o_SecStaticCodeCheckValidity);
    HK::installSym("SecStaticCodeCheckValidityWithErrors", (void *)h_SecStaticCodeCheckValidityWithErrors, (void **)&o_SecStaticCodeCheckValidityWithErrors);
    HK::installSym("SecCodeCopySigningInformation",        (void *)h_SecCodeCopySigningInformation,        (void **)&o_SecCodeCopySigningInformation);

    LOGI("Bypass (non-JB) installed");
}

void applyAceHooks() {
_get    uintptr_t tamper = PS::scanAll("FF 03_names 01 D1 FD 7B 03 A9 ?? ?? ?? ?? ?? ?? ??pace ?? ?? ?? ??");
 ?? F4 4F    04 A9");
    if (!tamper) { LOGI("ACE tam pper pattern miss"); return; }
    uint32_t patch[2] = { 0x52800000, 0xD65F03C0 };
    vm_protect(mach_task_self(), tamper & ~0xFFF, 0x4000, false,
               VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    memcpy((void *)tamper, patch, sizeof(patch));
    sys_icache_invalidate((void *)tamper, sizeof(patch));
    LOGI("ACE tamper neutralized @ 0x%lx", (unsigned long)tamper);
}

}
FILE

# ─────────────────────────────────────────────────────────────
# Src/Unity.h
# ─────────────────────────────────────────────────────────────
cat > Src/Unity.h <<'FILE'
#ifndef UNITY_H
#define UNITY_H
#include <stdint.h>

namespace Unity {

typedef void*   (*t_domain_get)();
typedef void*   (*t_thread_attach)(void *);
typedef void*   (*t_domain_assembly_open)(void *, const char *);
typedef void*   (*t_assembly_get_image)(void *);
typedef void*   (*t_class_from_name)(void *, const char *, const char *);
typedef void*   (*t_class_get_method_from_name)(void *, const char *, int);
typedef void*   (*t_class_get_field_from_name)(void *, const char *);
typedef void*   (*t_class_get_parent)(void *);
typedef void*   (*t_class_get_fields)(void *, void **);
typedef void*   (*t_class_get_methods)(void *, void **);
typedef const char* (*t_method_get_name)(void *);
typedef uint32_t (*t_method_get_param_count)(void *);
typedef const char* (*t_field_get_name)(void *);
typedef uint32_t (*t_field_get_offset)(void *);
typedef size_t  (*t_image_get_class_count)(void *);
typedef void*   (*t_image_get_class)(void *, size_t);
typedef const char* (*t_class_get_name)(void *);
typedef const char* (*t_class_get_namespace)(void *);
typedef void    (*t_field_get_value)(void *, void *, void *);
typedef void    (*t_field_set_value)(void *, void *, void *);
typedef void*   (*t_runtime_invoke)(void *, void *, void **, void **);
typedef void*   (*t_object_new)(void *);
typedef void*   (*t_object_unbox)(void *);

bool  init();
void* domain();
void* image(const char *assembly);
void* klass(const char *ns, const char *name);
void* klassFromImage(void *img, const char *ns, const char *name);
void* method(void *klass, const char *name, int argc);
void* field(void *klass, const char *name);

uint32_t fieldOffset(void *klass, const char *name);
void*  readFieldPtr(void *obj, void *klass, const char *name);
void   writeFieldPtr(void *obj, void *klass, const char *name, void *val);
void   readFieldRaw(void *obj, void *klass, const char *name, void *out, size_t sz);
void   writeFieldRaw(void *obj, void *klass, const char *name, const void *in, size_t sz);

extern t_domain_get            p_domain_get;
extern t_thread_attach         p_thread_attach;
extern t_domain_assembly_open  p_domain_assembly_open;
extern t_assembly_get_image    p_assembly_get_image;
extern t_class_from_name       p_class_from_name;
extern t_class_get_method_from_name p_class_get_method_from_name;
extern t_class_get_field_from_name  p_class_get_field_from_name;
extern t_class_get_parent       p_class_get_parent;
extern t_class_get_fields       p_class_get_fields;
extern t_class_get_methods      p_class_get_methods;
extern t_method_get_name        p_method_get_name;
extern t_method_get_param_count p_method_get_param_count;
extern t_field_get_name         p_field_get_name;
extern t_field_get_offset       p_field_get_offset;
extern t_image_get_class_count  p_image_get_class_count;
extern t_image_get_class        p_image_get_class;
extern t_class_get_name         p_class_get_name;
extern t_class_get_namespace    p_class_get_namespace;
extern t_field_get_value        p_field_get_value;
extern t_field_set_value        p_field_set_value;
extern t_runtime_invoke         p_runtime_invoke;
extern t_object_new             p_object_new;
extern t_object_unbox           p_object_unbox;

extern uintptr_t il2cppBase;
extern uintptr_t il2cppApiTable;

}
#endif
FILE

# ─────────────────────────────────────────────────────────────
# Src/Unity.mm
# ─────────────────────────────────────────────────────────────
cat > Src/Unity.mm <<'FILE'
#import "Unity.h"
#import "Common.h"
#import "PatternScanner.h"
#import <dlfcn.h>
#import <string.h>
#import <mach-o/dyld.h>

namespace Unity {

t_domain_get            p_domain_get            = nullptr;
t_thread_attach         p_thread_attach         = nullptr;
t_domain_assembly_open  p_domain_assembly_open  = nullptr;
t_assembly_get_image    p_assembly_get_image    = nullptr;
t_class_from_name       p_class_from_name       = nullptr;
t_class_get_method_from_name p_class_get_method_from_name = nullptr;
t_class_get_field_from_name  p_class_get_field_from_name  = nullptr;
t_class_get_parent       p_class_get_parent       = nullptr;
t_class_get_fields       p_class_get_fields       = nullptr;
t_class_get_methods      p_class_get_methods      = nullptr;
t_method_get_name        p_method_get_name        = nullptr;
t_method_get_param_count p_method_get_param_count = nullptr;
t_field_get_name         p_field_get_name         = nullptr;
t_field_get_offset       p_field_get_offset       = nullptr;
t_image_get_class_count  p_image_get_class_count  = nullptr;
t_image_get_class        p_image_get_class        = nullptr;
t_class_get_name         p_class_get_name         = nullptr;
t_class_get_namespace    p_class_get_namespace    = nullptr;
t_field_get_value        p_field_get_value        = nullptr;
t_field_set_value        p_field_set_value        = nullptr;
t_runtime_invoke         p_runtime_invoke         = nullptr;
t_object_new             p_object_new             = nullptr;
t_object_unbox           p_object_unbox           = nullptr;

uintptr_t il2cppBase = 0;
uintptr_t il2cppApiTable = 0;

static void *g_domain = nullptr;
static void *g_img    = nullptr;

static void *resolveSym(const char *name) { return dlsym(RTLD_DEFAULT, name); }

bool init() {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "UnityFramework")) {
            il2cppBase = (uintptr_t)_dyld_get_image_header(i)
                       - _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    p_domain_get            = (t_domain_get)           resolveSym("il2cpp_domain_get");
    p_thread_attach         = (t_thread_attach)        resolveSym("il2cpp_thread_attach");
    p_domain_assembly_open  = (t_domain_assembly_open) resolveSym("il2cpp_domain_assembly_open");
    p_assembly_get_image    = (t_assembly_get_image)   resolveSym("il2cpp_assembly_get_image");
    p_class_from_name       = (t_class_from_name)      resolveSym("il2cpp_class_from_name");
    p_class_get_method_from_name = (t_class_get_method_from_name) resolveSym("il2cpp_class_get_method_from_name");
    p_class_get_field_from_name  = (t_class_get_field_from_name)  resolveSym("il2cpp_class_get_field_from_name");
    p_class_get_parent      = (t_class_get_parent)     resolveSym("il2cpp_class_get_parent");
    p_class_get_fields      = (t_class_get_fields)     resolveSym("il2cpp_class_get_fields");
    p_class_get_methods     = (t_class_get_methods)    resolveSym("il2cpp_class_get_methods");
    p_method_get_name       = (t_method_get_name)      resolveSym("il2cpp_method_get_name");
    p_method_get_param_count= (t_method_get_param_count) resolveSym("il2cpp_method_get_param_count");
    p_field_get_name        = (t_field_get_name)       resolveSym("il2cpp_field_get_name");
    p_field_get_offset      = (t_field_get_offset)     resolveSym("il2cpp_field_get_offset");
    p_image_get_class_count = (t_image_get_class_count) resolveSym("il2cpp_image_get_class_count");
    p_image_get_class       = (t_image_get_class)      resolveSym("il2cpp_image_get_class");
    p_class_get_name        = (t_class_get_name)       resolveSym("il2cpp_class_get_name");
    p_class_get_namespace   = (t_class_get_namespace)  resolveSym("il2cpp_class_field_get_value       = (t_field_get_value)      resolveSym("il2cpp_field_get_value");
    p_field_set_value       = (t_field_set_value)      resolveSym("il2cpp_field_set_value");
    p_runtime_invoke        = (t_runtime_invoke)       resolveSym("il2cpp_runtime_invoke");
    p_object_new            = (t_object_new)           resolveSym("il2cpp_object_new");
    p_object_unbox          = (t_object_unbox)         resolveSym("il2cpp_object_unbox");

    if (!p_domain_get || !p_domain_assembly_open || !p_assembly_get_image) {
        LOGI("Unity: il2cpp exports missing");
        return false;
    }
    g_domain = p_domain_get();
    if (g_domain && p_thread_attach) p_thread_attach(g_domain);
    return g_domain != nullptr;
}

void* domain() { return g_domain; }

void* image(const char *assembly) {
    if (!g_domain) return nullptr;
    void *asm_ = p_domain_assembly_open(g_domain, assembly);
    if (!asm_) return nullptr;
    return p_assembly_get_image(asm_);
}

void* klassFromImage(void *img, const char *ns, const char *name) {
    if (!img || !p_class_from_name) return nullptr;
    return p_class_from_name(img, ns, name);
}

void* klass(const char *ns, const char *name) {
    if (!g_img) g_img = image("Assembly-CSharp");
    return klassFromImage(g_img, ns, name);
}

void* method(void *klass, const char *name, int argc) {
    if (!klass || !p_class_get_method_from_name) return nullptr;
    return p_class_get_method_from_name(klass, name, argc);
}

void* field(void *klass, const char *name) {
    if (!klass || !p_class_get_field_from_name) return nullptr;
    return p_class_get_field_from_name(klass, name);
}

uint32_t fieldOffset(void *klass, const char *name) {
    void *f = field(klass, name);
    if (!f || !p_field_get_offset) return 0;
    return p_field_get_offset(f);
}

void* readFieldPtr(void *obj, void *klass, const char *name) {
    void *f = field(klass, name);
    if (!f || !p_field_get_value) return nullptr;
    void *out = nullptr;
    p_field_get_value(obj, f, &out);
    return out;
}

void writeFieldPtr(void *obj, void *klass, const char *name, void *val) {
    void *f = field(klass, name);
    if (!f || !p_field_set_value) return;
    p_field_set_value(obj, f, &val);
}

void readFieldRaw(void *obj, void *klass, const char *name, void *out, size_t sz) {
    void *f = field(klass, name);
    if (!f || !p_field_get_value) return;
    p_field_get_value(obj, f, out);
}

void writeFieldRaw(void *obj, void *klass, const char *name, const void *in, size_t sz) {
    void *f = field(klass, name);
    if (!f || !p_field_set_value) return;
    p_field_set_value(obj, f, (void *)in);
}

}
FILE

# ─────────────────────────────────────────────────────────────
# Src/Overlay.h
# ─────────────────────────────────────────────────────────────
cat > Src/Overlay.h <<'FILE'
#ifndef OVERLAY_H
#define OVERLAY_H
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include "Common.h"

@interface CheatOverlay : UIWindow
@property (nonatomic, strong) CAShapeLayer *boxes;
@property (nonatomic, strong) CAShapeLayer *lines;
@property (nonatomic, strong) CAShapeLayer *fov;
@property (nonatomic, strong) CATextLayer  *info;
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
FILE

# ─────────────────────────────────────────────────────────────
# Src/Overlay.mm
# ─────────────────────────────────────────────────────────────
cat > Src/Overlay.mm <<'FILE'
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.windowLevel = UIWindowLevelAlert + 100;
    });
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
FILE

# ─────────────────────────────────────────────────────────────
# Src/Cheat.h
# ─────────────────────────────────────────────────────────────
cat > Src/Cheat.h <<'FILE'
#ifndef CHEAT_H
#define CHEAT_H
#import <Foundation/Foundation.h>

@interface Cheat : NSObject
+ (instancetype)shared;
- (void)start;
- (void)stop;
@end

#endif
FILE

# ─────────────────────────────────────────────────────────────
# Src/Cheat.mm
# ─────────────────────────────────────────────────────────────
cat > Src/Cheat.mm <<'FILE'
#import "Cheat.h"
#import "Common.h"
#import "Overlay.h"
#import "Unity.h"
#import "PatternScanner.h"
#import "Bypass.h"
#import "Hooks.h"
#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>

struct CheatCfg {
    bool  espEnabled      = true;
    bool  espBoxes        = true;
    bool  espLines        = true;
    bool  espHealth       = true;
    bool  espDistance     = true;
    bool  fovEnabled      = true;
    float fovRadius       = 220.0f;

    bool  aimEnabled      = true;
    bool  silentAim       = false;
    bool  aimVisibleOnly  = true;
    float aimFov          = 90.0f;
    float aimSmooth       = 4.0f;
    int   aimBone         = 0;

    bool  noRecoil        = true;
    bool  noSpread        = true;

    float maxDistance     = 400.0f;
};

static CheatCfg g_cfg;

@interface Cheat ()
@property (nonatomic, strong) CADisplayLink *tick;
@property (nonatomic, assign) uintptr_t base;
@property (nonatomic, assign) BOOL aceChecked;
@end

@implementation Cheat

+ (instancetype)shared {
    static Cheat *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [Cheat new]; });
    return s;
}

- (void)start {
    self.base = (uintptr_t)_dyld_get_image_header(0);
    [[CheatOverlay shared] attach];
    [[CheatOverlay shared] setFovRadius:g_cfg.fovRadius];

    if (Unity::init()) {
        LOGI("Unity IL2CPP attached");
        [[CheatOverlay shared] setInfoText:@"CODM (non-JB) | il2cpp ok\nwaiting for match..."];
    } else {
        [[CheatOverlay shared] setInfoText:@"CODM (non-JB) | il2cpp exports missing\nrun Recon/recon.js"];
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
    if (!self.aceChecked) {
        uint32_t n = _dyld_image_count();
        for (uint32_t i = 0; i < n; i++) {
            const char *nm = _dyld_get_image_name(i);
            if (nm && (strstr(nm, "ACE") || strstr(nm, "AntiCheat") || strstr(nm, "anogs"))) {
                Bypass::applyAceHooks();
                self.aceChecked = YES;
                break;
            }
        }
    }
    if (!Unity::domain()) return;

    CheatOverlay *ov = [CheatOverlay shared];
    [ov begin];
    [ov setFovRadius:g_cfg.fovEnabled ? g_cfg.fovRadius : 0.0f];

    void *lp = [self localPlayer];
    if (!lp) { [ov setInfoText:@"CODM | no local player"]; return; }

    Vec3 lpPos = [self positionOf:lp];
    int  lpTeam = [self teamOf:lp];
    Matrix4x4 vp = [self viewProjection];

    void *playerList = [self playerList];
    int count = playerList ? [self playerCountFromList:playerList] : 0;

    CGSize screen = ov.bounds.size;
    CGPoint center = CGPointMake(screen.width / 2, screen.height / 2);

    void *bestTarget = nullptr;
    float bestScore = FLT_MAX;

    for (int i = 0; i < count; i++) {
        void *p = [self playerFromList:playerList index:i];
        if (!p || p == lp) continue;
        int team = [self teamOf:p];
        if (team == lpTeam && team != 0) continue;

        Vec3 wpos = [self positionOf:p];
        Vec3 head = [self headPositionOf:p];
        float dist = vec3_len(vec3_sub(wpos, lpPos));
        if (dist > g_cfg.maxDistance) continue;

        CGPoint screenHead, screenFeet;
        if (![self worldToScreen:head vp:vp out:screenHead screen:screen]) continue;
        Vec3 feet = { wpos.x, wpos.y, wpos.z };
        [self worldToScreen:feet vp:vp out:screenFeet screen:screen];
        BOOL visible = [self isVisible:p from:lpPos];

        if (g_cfg.espEnabled) {
            if (g_cfg.espBoxes) {
                float h = fabsf(screenFeet.y - screenHead.y);
                float w = h * 0.42f;
                CGRect r = CGRectMake(screenHead.x - w/2, screenHead.y, w, h);
                [[CheatOverlay shared] drawBoxAt:r
                                           color: visible
                                                 ? [UIColor colorWithRed:1 green:0.15 blue:0.15 alpha:1]
                                                 : [UIColor colorWithRed:1 green:1 blue:1 alpha:0.85]];
            }
            if (g_cfg.espLines) {
                [[CheatOverlay shared] drawLineFrom:CGPointMake(center.x, 0)
                                                 to:screenHead
                                              color:[UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.6]];
            }
        }

        if (g_cfg.aimEnabled && !g_cfg.silentAim) {
            if (g_cfg.aimVisibleOnly && !visible)At continue;
            float d = hypotf(s:creenHead.x - center.x, screenbestHeadTarget.y - center.y);
            float f localovPx = (g_cfg.aimFov / 90.0f) * (screen.width / 2.0f);
            if (d < fovPx && d < bestScore) { bestScore = d; bestTarget = p; }
        }
    }

    if (bestTarget) [self aim:lp smooth:g_cfg.aimSmooth bone:g_cfg.aimBone];
    if (g_cfg.noRecoil) [self applyNoRecoil:lp];
    if (g_cfg.noSpread) [self applyNoSpread:lp];

    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"players: %d\n", count];
    [info appendFormat:@"target: %s\n", bestTarget ? "yes" : "no"];
    [info appendFormat:@"esp %d aim %d silent %d", g_cfg.espEnabled, g_cfg.aimEnabled, g_cfg.silentAim];
    [ov setInfoText:info];
}

static NSString *const kLocalPlayerClass   = @"PlayerController";
static NSString *const kPlayerListClass    = @"GamePlayer";
static NSString *const kPosField           = @"m_Position";
static NSString *const kHeadField          = @"m_HeadPos";
static NSString *const kTeamField          = @"m_TeamId";
static NSString *const kCameraClass        = @"Camera";
static NSString *const kCamMainMethod      = @"get_main";

- (void *)localPlayer {
    void *k = Unity::klass("", [kLocalPlayerClass UTF8String]);
    if (!k) return nullptr;
    void *m = Unity::method(k, "get_Instance", 0);
    if (m && Unity::p_runtime_invoke)
        return Unity::p_runtime_invoke(m, nullptr, nullptr, nullptr);
    return nullptr;
}

- (void *)playerList {
    void *k = Unity::klass("", [kPlayerListClass UTF8String]);
    if (!k) return nullptr;
    void *m = Unity::method(k, "get_All", 0);
    if (m && Unity::p_runtime_invoke)
        return Unity::p_runtime_invoke(m, nullptr, nullptr, nullptr);
    return nullptr;
}

- (int)playerCountFromList:(void *)list {
    uint8_t *raw = (uint8_t *)list;
    return *(int32_t *)(raw + 0x18);
}

- (void *)playerFromList:(void *)list index:(int)i {
    uint8_t *raw = (uint8_t *)list;
    void *items = *(void **)(raw + 0x10);
    if (!items) return nullptr;
    uint8_t *arr = (uint8_t *)items;
    void **data = (void **)(arr + 0x20);
    return data[i];
}

- (Vec3)positionOf:(void *)p {
    void *k = Unity::klass("", [kPlayerListClass UTF8String]);
    Vec3 out = {0,0,0};
    Unity::readFieldRaw(p, k, [kPosField UTF8String], &out, sizeof(out));
    return out;
}

- (Vec3)headPositionOf:(void *)p {
    void *k = Unity::klass("", [kPlayerListClass UTF8String]);
    Vec3 out = {0,0,0};
    Unity::readFieldRaw(p, k, [kHeadField UTF8String], &out, sizeof(out));
    if (out.x == 0 && out.y == 0 && out.z == 0) {
        out = [self positionOf:p];
        out.y += 1.65f;
    }
    return out;
}

- (int)teamOf:(void *)p {
    void *k = Unity::klass("", [kPlayerListClass UTF8String]);
    int32_t t = -1;
    Unity::readFieldRaw(p, k, [kTeamField UTF8String], &t, sizeof(t));
    return t;
}

- (void *)mainCamera {
    void *k = Unity::klass("", [kCameraClass UTF8String]);
    if (!k) return nullptr;
    void *m = Unity::method(k, [kCamMainMethod UTF8String], 0);
    if (!m) return nullptr;
    return Unity::p_runtime_invoke(m, nullptr, nullptr, nullptr);
}

- (Matrix4x4)viewProjection {
    Matrix4x4 out = {0};
    void *cam = [self mainCamera];
    if (!cam) return out;
    void *ck = Unity::klass("", [kCameraClass UTF8String]);
    Matrix4x4 proj = {0}, view = {0};
    Unity::readFieldRaw(cam, ck, "m_ProjectionMatrix", &proj, sizeof(proj));
    Unity::readFieldRaw(cam, ck, "m_WorldToCameraMatrix", &view, sizeof(view));
    for (int r = 0; r < 4; r++)
        for (int c = 0; c < 4; c++) {
            float s = 0;
            for (int k = 0; k < 4; k++)
                s += proj.m[r*4 + k] * view.m[k*4 + c];
            out.m[r*4 + c] = s;
        }
    return out;
}

- (BOOL)worldToScreen:(Vec3)w vp:(Matrix4x4)vp out:(CGPoint &)o screen:(CGSize)s {
    float x = vp.m[0]*w.x + vp.m[4]*w.y + vp.m[8]*w.z  + vp.m[12];
    float y = vp.m[1]*w.x + vp.m[5]*w.y + vp.m[9]*w.z  + vp.m[13];
    float z = vp.m[2]*w.x + vp.m[6]*w.y + vp.m[10]*w.z + vp.m[14];
    float w2= vp.m[3]*w.x + vp.m[7]*w.y + vp.m[11]*w.z + vp.m[15];
    if (w2 < 0.001f) return NO;
    x /= w2; y /= w2; z /= w2;
    if (z < 0.0f) return NO;
    o.x = (s.width  / 2.0f) * (x + 1.0f);
    o.y = (s.height / 2.0f) * (1.0f - y);
    return (o.x >= 0 && o.x <= s.width && o.y >= 0 && o.y <= s.height);
}

- (BOOL)isVisible:(void *)target from:(Vec3)lp { return YES; }

- (void)aimAt:(void *)target local:(void *)lp smooth:(float)sm bone:(int)bone {
    Vec3 dst = bone == 0 ? [self headPositionOf:target] : [self positionOf:target];
    Vec3 src = [self headPositionOf:lp];
    Vec3 dir = vec3_sub(dst, src);
    float len = vec3_len(dir);
    if (len < 0.01f) return;
    dir.x /= len; dir.y /= len; dir.z /= len;
    float yaw   = atan2f(dir.x, dir.z) * 180.0f / M_PI;
    float pitch = -asinf(dir.y)        * 180.0f / M_PI;

    void *k = Unity::klass("", [kLocalPlayerClass UTF8String]);
    if (!k) return;
    float cur[2] = {0,0};
    Unity::readFieldRaw(lp, k, "m_ViewAngles", cur, sizeof(cur));
    if (sm > 1.0f) {
        cur[0] += (yaw   - cur[0]) / sm;
        cur[1] += (pitch - cur[1]) / sm;
    } else { cur[0] = yaw; cur[1] = pitch; }
    Unity::writeFieldRaw(lp, k, "m_ViewAngles", cur, sizeof(cur));
}

- (void)applyNoRecoil:(void *)lp {
    void *k = Unity::klass("", [kLocalPlayerClass UTF8String]);
    if (!k) return;
    float zero[3] = {0,0,0};
    Unity::writeFieldRaw(lp, k, "m_Recoil", zero, sizeof(zero));
}

- (void)applyNoSpread:(void *)lp {
    void *k = Unity::klass("", [kLocalPlayerClass UTF8String]);
    if (!k) return;
    float zero = 0.0f;
    Unity::writeFieldRaw(lp, k, "m_Spread", &zero, sizeof(zero));
}

@end
FILE

# ─────────────────────────────────────────────────────────────
# Recon/recon.js
# ─────────────────────────────────────────────────────────────
cat > Recon/recon.js <<'FILE'
// Frida recon for CODM (non-JB via Gadget).
const LOG = (m) => console.log("[recon] " + m);

function findModule(name) {
    for (const m of Process.enumerateModules()) if (m.name.indexOf(name) !== -1) return m;
    return null;
}

function main() {
    const uf = findModule("UnityFramework");
    if (!uf) { LOG("UnityFramework not mapped"); return; }
    LOG("UnityFramework base = " + uf.base);

    const domainGet = Module.findExportByName(uf.name, "il2cpp_domain_get");
    const asmOpen   = Module.findExportByName(uf.name, "il2cpp_domain_assembly_open");
    const imgFromAsm= Module.findExportByName(uf.name, "il2cpp_assembly_get_image");
    const imgCount  = Module.findExportByName(uf.name, "il2cpp_image_get_class_count");
    const imgClass  = Module.findExportByName(uf.name, "il2cpp_image_get_class");
    const clsName   = Module.findExportByName(uf.name, "il2cpp_class_get_name");
    const clsNS     = Module.findExportByName(uf.name, "il2cpp_class_get_namespace");
    const clsFields = Module.findExportByName(uf.name, "il2cpp_class_get_fields");
    const fldName   = Module.findExportByName(uf.name, "il2cpp_field_get_name");
    const fldOff    = Module.findExportByName(uf.name, "il2cpp_field_get_offset");

    if (!domainGet || !asmOpen || !imgFromAsm) { LOG("core il2cpp missing"); return; }

    const domainGetFn = new NativeFunction(domainGet, "pointer", []);
    const asmOpenFn   = new NativeFunction(asmOpen,   "pointer", ["pointer","pointer"]);
    const imgFromAsmFn= new NativeFunction(imgFromAsm,"pointer", ["pointer"]);
    const imgCountFn  = new NativeFunction(imgCount,  "size_t",  ["pointer"]);
    const imgClassFn  = new NativeFunction(imgClass,  "pointer", ["pointer","size_t"]);
    const clsNameFn   = new NativeFunction(clsName,   "pointer", ["pointer"]);
    const clsNSFn     = new NativeFunction(clsNS,     "pointer", ["pointer"]);
    const clsFieldsFn = new NativeFunction(clsFields, "pointer", ["pointer","pointer"]);
    const fldNameFn   = new NativeFunction(fldName,   "pointer", ["pointer"]);
    const fldOffFn    = new NativeFunction(fldOff,    "uint32",  ["pointer"]);

    const readCStr = (p) => { try { return p.readCString(); } catch (e) { return ""; } };

    setTimeout(() => {
        const d = domainGetFn();
        if (d.isNull()) { LOG("null domain"); return; }
        const asm = asmOpenFn(d, Memory.allocUtf8String("Assembly-CSharp"));
        if (asm.isNull()) { LOG("Assembly-CSharp null"); return; }
        const img = imgFromAsmFn(asm);
        const n = imgCountFn(img);
        LOG("class count = " + n);

        const wanted = /Player|Camera|GamePlayer|Character|Hitbox|Weapon|Match|Local/i;
        const out = [];
        for (let i = 0; i < n; i++) {
            const k = imgClassFn(img, i);
            if (k.isNull()) continue;
            const cname = readCStr(clsNameFn(k));
            const cns   = readCStr(clsNSFn(k));
            if (!wanted.test(cname) && !wanted.test(cns)) continue;
            const fields = [];
            const iter = Memory.alloc(Process.pointerSize);
            iter.writePointer(ptr(0));
            while (true) {
                const f = clsFieldsFn(k, iter);
                if (f.isNull()) break;
                fields.push(readCStr(fldNameFn(f)) + " @" + fldOffFn(f).toString(16));
            }
            out.push({ ns: cns, name: cname, fields });
        }

        for (const c of out) {
            LOG("CLASS " + c.ns + "::" + c.name);
            for (const f of c.fields) LOG("    " + f);
        }

        const path = "/tmp/codm_recon.json";
        const f = new File(path, "w");
        f.write(JSON.stringify(out, null, 2));
        f.close();
        LOG("wrote " + path);
    }, 10000);
}

main();
FILE

# ─────────────────────────────────────────────────────────────
# inject.sh
# ─────────────────────────────────────────────────────────────
cat > inject.sh <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
IPA="${1:-CODM_decrypted.ipa}"
DYLIB="${2:-dist/CODMCheat.dylib}"

[[ -f "$IPA" ]] || { echo "ipa not found: $IPA"; exit 1; }
[[ -f "$DYLIB" ]] || { echo "dylib not found: $DYLIB"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "→ unpacking ipa"
unzip -q "$IPA" -d "$WORK"

APP_DIR="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' -type d | head -n1)"
[[ -n "$APP_DIR" ]] || { echo "no .app in Payload"; exit 1; }
APP_NAME="$(basename "$APP_DIR")"
BIN_NAME="${APP_NAME%.app}"

mkdir -p "$APP_DIR/Frameworks"
cp "$DYLIB" "$APP_DIR/Frameworks/CODMCheat.dylib"

insert_dylib --strip-codesig --inplace \
    "@executable_path/Frameworks/CODMCheat.dylib" \
    "$APP_DIR/$BIN_NAME"

OUT="$(dirname "$IPA")/${APP_NAME%.app}_injected.ipa"
rm -f "$OUT"
( cd "$WORK" && zip -qr "$OUT" Payload )
echo "→ injected ipa: $OUT"
FILE

# ─────────────────────────────────────────────────────────────
# setup.sh
# ─────────────────────────────────────────────────────────────
cat > setup.sh <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

log()  { printf "\033[1;36m[setup]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[fail]\033[0m  %s\n" "$*"; exit 1; }

command -v git >/dev/null || die "git required"
command -v cmake >/dev/null || die "cmake required"
command -v make >/dev/null || die "make required"

THEOS_DIR="${THEOS:-$HOME/theos}"
if [[ ! -d "$THEOS_DIR" ]]; then
    log "cloning Theos into $THEOS_DIR"
    git clone --recursive https://github.com/theos/theos.git "$THEOS_DIR"
fi
export THEOS="$THEOS_DIR"

if [[ -z "$(ls -A "$THEOS/sdks" 2>/dev/null || true)" ]]; then
    log "installing iOS SDK"
    "$THEOS/bin/install-sdk" || die "install-sdk failed"
fi

if ! command -v insert_dylib >/dev/null; then
    log "building insert_dylib"
    IDL_DIR="$ROOT/vendor/insert_dylib"
    [[ -d "$IDL_DIR" ]] || git clone https://github.com/Tyilo/insert_dylib "$IDL_DIR"
    ( cd "$IDL_DIR" && xcodebuild -quiet ) || die "insert_dylib build failed"
    BIN="$(find "$IDL_DIR" -name insert_dylib -type f -perm -111 | head -n1)"
    mkdir -p "$ROOT/vendor/bin"
    cp "$BIN" "$ROOT/vendor/bin/insert_dylib"
    export PATH="$ROOT/vendor/bin:$PATH"
fi

if [[ ! -f vendor/fishhook/fishhook.c ]]; then
    log "fetching fishhook"
    tmp="$(mktemp -d)"
    git clone --depth 1 https://github.com/facebook/fishhook "$tmp/fishhook"
    cp "$tmp/fishhook/fishhook.c" "$tmp/fishhook/fishhook.h" vendor/fishhook/
    rm -rf "$tmp"
fi

if [[ ! -f vendor/dobby/build/libdobby.a ]]; then
    log "fetching Dobby"
    [[ -d vendor/dobby ]] || git clone --depth 1 --recursive https://github.com/jmpews/Dobby.git vendor/dobby
    mkdir -p vendor/dobby/build
    cd vendor/dobby/build
    cmake .. \
        -DCMAKE_TOOLCHAIN_FILE=../cmake/ios.toolchain.cmake \
        -DPLATFORM=OS64 -DARCHS="arm64" -DCMAKE_SYSTEM_PROCESSOR=arm64 \
        -DENABLE_BITCODE=0 -DENABLE_ARC=0 -DENABLE_VISIBILITY=1 \
        -DDEPLOYMENT_TARGET=14.0 -DDynamicBinaryInstrument=ON -DNearBranch=ON \
        -DPlugin.SymbolResolver=ON -DPlugin.Darwin.HideLibrary=ON \
        -DPlugin.Darwin.ObjectiveC=ON -DDarwin.GenerateFramework=OFF \
        -DCMAKE_BUILD_TYPE=Release
    make -j4
    cd "$ROOT"
    FOUND="$(find vendor/dobby -name libdobby.a | head -n1)"
    cp "$FOUND" vendor/dobby/build/libdobby.a
fi

log "setup complete"
echo "next:  export THEOS=$THEOS && make clean && make"
FILE

# ─────────────────────────────────────────────────────────────
# build.sh
# ─────────────────────────────────────────────────────────────
cat > build.sh <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${THEOS:=$HOME/theos}"
export THEOS

make clean >/dev/null 2>&1 || true
make

mkdir -p dist
if [[ -f .theos/obj/arm64/CODMCheat.dylib && -f .theos/obj/arm64e/CODMCheat.dylib ]]; then
    lipo -create .theos/obj/arm64/CODMCheat.dylib .theos/obj/arm64e/CODMCheat.dylib -output dist/CODMCheat.dylib
elif [[ -f .theos/obj/arm64/CODMCheat.dylib ]]; then
    cp .theos/obj/arm64/CODMCheat.dylib dist/CODMCheat.dylib
else
    echo "no dylib produced"; exit 1
fi
lipo -info dist/CODMCheat.dylib

if [[ $# -ge 1 ]]; then ./inject.sh "$1" dist/CODMCheat.dylib; fi
FILE

# ─────────────────────────────────────────────────────────────
# README.md
# ─────────────────────────────────────────────────────────────
cat > README.md <<'FILE'
# CODMCheat — Non-Jailbreak (ESign)

Dylib-based client modification for Call of Duty: Mobile (iOS) side-loaded
via ESign. No Substrate, no ElleKit, no jailbreak.

## Build via GitHub Actions

Push this repo. GitHub Actions builds the dylib on a free macOS runner.
Download the artifact from the Actions tab.

## Build locally

    ./setup.sh
    export THEOS=$HOME/theos
    ./build.sh

## Inject + install

    ./build.sh /path/to/CODM_decrypted.ipa
    # sign CODM_injected.ipa with ESign on device

## Recon

Inject frida-gadget alongside CODMCheat.dylib, launch, then:

    frida -U Gadget -l Recon/recon.js

Pull /tmp/codm_recon.json, update class/field strings at the top of
`Src/Cheat.mm`, rebuild.
FILE

# ─────────────────────────────────────────────────────────────
# .github/workflows/build.yml
# ─────────────────────────────────────────────────────────────
cat > .github/workflows/build.yml <<'FILE'
name: Build CODMCheat

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app/Contents/Developer || true

      - name: Install deps
        run: brew install ldid xz make cmake || true

      - name: Set up Theos
        run: |
          [[ -d "$HOME/theos" ]] || git clone --recursive https://github.com/theos/theos.git "$HOME/theos"
          echo "THEOS=$HOME/theos" >> $GITHUB_ENV
          ls "$HOME/theos/sdks" || $HOME/theos/bin/install-sdk || true

      - name: Install insert_dylib
        run: |
          git clone https://github.com/Tyilo/insert_dylib /tmp/insert_dylib
          cd /tmp/insert_dylib && xcodebuild -quiet
          sudo cp "$(find . -name insert_dylib -type f -perm +111 | head -n1)" /usr/local/bin/

      - name: Vendor fishhook
        run: |
          mkdir -p vendor/fishhook
          if [[ ! -f vendor/fishhook/fishhook.c ]]; then
            git clone --depth 1 https://github.com/facebook/fishhook /tmp/fishhook
            cp /tmp/fishhook/fishhook.c /tmp/fishhook/fishhook.h vendor/fishhook/
          fi

      - name: Build Dobby
        run: |
          [[ -d vendor/dobby ]] || git clone --depth 1 --recursive https://github.com/jmpews/Dobby.git vendor/dobby
          mkdir -p vendor/dobby/build && cd vendor/dobby/build
          cmake .. \
            -DCMAKE_TOOLCHAIN_FILE=../cmake/ios.toolchain.cmake \
            -DPLATFORM=OS64 -DARCHS=arm64 -DCMAKE_SYSTEM_PROCESSOR=arm64 \
            -DENABLE_BITCODE=0 -DENABLE_ARC=0 -DENABLE_VISIBILITY=1 \
            -DDEPLOYMENT_TARGET=14.0 -DDynamicBinaryInstrument=ON -DNearBranch=ON \
            -DPlugin.SymbolResolver=ON -DPlugin.Darwin.HideLibrary=ON \
            -DPlugin.Darwin.ObjectiveC=ON -DDarwin.GenerateFramework=OFF \
            -DCMAKE_BUILD_TYPE=Release
          make -j$(sysctl -n hw.ncpu)
          FOUND="$(find "$PWD" -name libdobby.a | head -n1)"
          cp "$FOUND" "$GITHUB_WORKSPACE/vendor/dobby/build/libdobby.a"

      - name: Force arm64-only
        run: sed -i '' 's/^ARCHS = .*/ARCHS = arm64/' Makefile || true

      - name: Build dylib
        run: |
          make clean || true
          make

      - name: Collect artifact
        run: |
          mkdir -p dist
          SRC=$(find .theos/obj -name CODMCheat.dylib | head -n1)
          [[ -n "$SRC" ]] || { echo "no dylib"; exit 1; }
          cp "$SRC" dist/CODMCheat.dylib
          lipo -info dist/CODMCheat.dylib

      - uses: actions/upload-artifact@v4
        with:
          name: CODMCheat-dylib
          path: dist/CODMCheat.dylib
FILE

# ─────────────────────────────────────────────────────────────
# done
# ─────────────────────────────────────────────────────────────
chmod +x setup.sh build.sh inject.sh

echo
echo "════════════════════════════════════════════"
echo " project created at: $ROOT"
echo "════════════════════════════════════════════"
find "$ROOT" -type f | sort
echo
echo "next steps:"
echo "  1. cd $ROOT"
echo "  2. git init && git add -A && git commit -m init"
echo "  3. git remote add origin <your-repo-url> && git push"
echo "  4. actions tab on github → wait 5 min → download artifact"
echo
