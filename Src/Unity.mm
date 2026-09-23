#import "Unity.h"
#import "Common.h"
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

namespace Unity {
static uintptr_t g_base = 0;
static char      g_status[200] = "not initialized";
static int       g_syms = 0;

bool init() {
    if (_dyld_image_count() > 0) g_base = (uintptr_t)_dyld_get_image_header(0);

    const char* names[] = {
        "il2cpp_domain_get",
        "il2cpp_thread_attach",
        "il2cpp_domain_assembly_open",
        "il2cpp_assembly_get_image",
        "il2cpp_class_from_name",
        "il2cpp_class_get_method_from_name",
        "il2cpp_class_get_field_from_name",
        "il2cpp_runtime_invoke",
        "il2cpp_object_new",
        "il2cpp_image_get_class_count",
        "il2cpp_image_get_class",
        "il2cpp_class_get_name",
        "il2cpp_class_get_namespace",
    };
    g_syms = 0;
    for (int i = 0; i < 13; i++) if (dlsym(RTLD_DEFAULT, names[i])) g_syms++;
    snprintf(g_status, sizeof(g_status), "main 0x%lx | il2cpp syms %d/13",
             (unsigned long)g_base, g_syms);
    return true;
}
const char* statusMessage() { return g_status; }
uintptr_t mainBase() { return g_base; }
int resolvedSymbols() { return g_syms; }
}
