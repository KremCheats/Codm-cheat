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
    "CydiaSubstrate", "MobileSubstrate", "Substrate", "libhooker",
    "ElleKit", "ellekit", "substitute", "Substitute", "TweakInject",
    "cynject", NULL
};
static inline bool isSuspect(const char *p) {
    if (!p) return false;
    for (int i = 0; kSuspect[i]; i++)
        if (strstr(p, kSuspect[i])) return true;
    return false;
}

static const char *kJbPaths[] = {
    "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
    "/Applications/Filza.app", "/Library/MobileSubstrate", "/Library/Substrate",
    "/bin/bash", "/bin/sh", "/bin/zsh",
    "/usr/sbin/sshd", "/usr/bin/ssh", "/usr/bin/sshd",
    "/etc/apt", "/etc/ssh/sshd_config",
    "/private/var/lib/apt", "/private/var/lib/cydia", "/private/var/stash",
    "/var/jb", "/var/jb/usr/bin/ssh", "/var/jb/Library/MobileSubstrate",
    NULL
};
static inline bool isJbPath(const char *p) {
    if (!p) return false;
    for (int i = 0; kJbPaths[i]; i++)
        if (strcmp(p, kJbPaths[i]) == 0) return true;
    return isSuspect(p);
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

static SecStatus (*o_SecCV)(void *, uint32_t, void *);
static SecStatus h_SecCV(void *c, uint32_t f, void *r) { return 0; }
static SecStatus (*o_SecCVWE)(void *, uint32_t, void *, CFErrorRef *);
static SecStatus h_SecCVWE(void *c, uint32_t f, void *r, CFErrorRef *e) {
    if (e) *e = NULL; return 0;
}
static SecStatus (*o_SecSCV)(void *, uint32_t, void *);
static SecStatus h_SecSCV(void *c, uint32_t f, void *r) { return 0; }
static SecStatus (*o_SecSCVWE)(void *, uint32_t, void *, CFErrorRef *);
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
        [sc isEqualToString:@"zbra"]  || [sc isEqualToString:@"filza"]) return NO;
    return o_cOU(s, c, u);
}

namespace Bypass {

void install() {
    LOGI("Bypass installing");

    // libc
    HK::rebind("fopen",   (void *)h_fopen,   (void **)&o_fopen);
    HK::rebind("stat",    (void *)h_stat,    (void **)&o_stat);
    HK::rebind("lstat",   (void *)h_lstat,   (void **)&o_lstat);
    HK::rebind("access",  (void *)h_access,  (void **)&o_access);
    HK::rebind("opendir", (void *)h_opendir, (void **)&o_opendir);
    HK::rebind("getenv",  (void *)h_getenv,  (void **)&o_getenv);

    // process
    HK::rebind("ptrace",  (void *)h_ptrace,  (void **)&o_ptrace);
    HK::rebind("sysctl",  (void *)h_sysctl,  (void **)&o_sysctl);
    HK::rebind("dladdr",  (void *)h_dladdr,  (void **)&o_dladdr);

    // objc
    HK::swizzleClass([NSFileManager class], @selector(fileExistsAtPath:),
                     (IMP)h_fE, (IMP *)&o_fE);
    HK::swizzleClass([NSFileManager class], @selector(fileExistsAtPath:isDirectory:),
                     (IMP)h_fED, (IMP *)&o_fED);
    HK::swizzleClass([UIApplication class], @selector(canOpenURL:),
                     (IMP)h_cOU, (IMP *)&o_cOU);

    // code signing
    HK::rebind("SecCodeCheckValidity",                 (void *)h_SecCV,   (void **)&o_SecCV);
    HK::rebind("SecCodeCheckValidityWithErrors",       (void *)h_SecCVWE, (void **)&o_SecCVWE);
    HK::rebind("SecStaticCodeCheckValidity",           (void *)h_SecSCV,  (void **)&o_SecSCV);
    HK::rebind("SecStaticCodeCheckValidityWithErrors", (void *)h_SecSCVWE,(void **)&o_SecSCVWE);
    HK::rebind("SecCodeCopySigningInformation",        (void *)h_SecCSI,  (void **)&o_SecCSI);

    LOGI("Bypass installed");
}

}
