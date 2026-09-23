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
