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
