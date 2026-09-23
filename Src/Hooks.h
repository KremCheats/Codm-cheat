#ifndef HOOKS_H
#define HOOKS_H
#include <stdint.h>
#include <objc/runtime.h>
namespace HK {
void rebind(const char *name, void *replacement, void **orig);
bool swizzleClass(Class cls, SEL sel, IMP replacement, IMP *original);
}
#endif
