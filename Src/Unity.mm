#import "Unity.h"
#import "Common.h"
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

namespace Unity {

static uintptr_t g_base = 0;
static char      g_status[160] = "not initialized";
static int       g_syms = 0;
static int       g_classes = 0;

static uintptr_t findUnityBase() {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char* nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

bool init() {
    g_base = findUnityBase();
    if (!g_base) {
        snprintf(g_status, sizeof(g_status), "UnityFramework not mapped");
        return false;
    }

    // Count how many il2cpp_* symbols are visible via dlsym.
    // Do NOT call any of them yet — just check presence.
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
    for (int i = 0; i < 13; i++) {
        if (dlsym(RTLD_DEFAULT, names[i])) g_syms++;
    }
    g_classes = 0;
    snprintf(g_status, sizeof(g_status),
             "unity fw 0x%lx | syms %d/13 | (safe mode)",
             (unsigned long)g_base, g_syms);
    return true;
}

const char* statusMessage() { return g_status; }
uintptr_t frameworkBase() { return g_base; }
int resolvedSymbols() { return g_syms; }
int classCount() { return g_classes; }

}
