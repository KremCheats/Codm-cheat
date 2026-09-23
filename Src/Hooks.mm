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
void rebindInImage(void* header, intptr_t slide, const char *name, void *replacement, void **orig) {
    struct rebinding rb;
    rb.name = name;
    rb.replacement = replacement;
    rb.replaced = orig;
    rebind_symbols_image(header, slide, &rb, 1);
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
