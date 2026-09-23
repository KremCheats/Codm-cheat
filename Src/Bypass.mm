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
