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
