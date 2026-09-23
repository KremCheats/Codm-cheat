#ifndef fishhook_h
#define fishhook_h
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#ifdef __cplusplus
extern "C" {
#endif
struct rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};
int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel);
#ifdef __cplusplus
}
#endif
#endif
