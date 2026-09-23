#import "Unity.h"
#import "Common.h"
#import <dlfcn.h>
#import <string.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

namespace Unity {

t_domain_get             p_domain_get             = nullptr;
t_thread_attach          p_thread_attach          = nullptr;
t_domain_assembly_open   p_domain_assembly_open   = nullptr;
t_assembly_get_image     p_assembly_get_image     = nullptr;
t_class_from_name        p_class_from_name        = nullptr;
t_class_get_method_from_name p_class_get_method_from_name = nullptr;
t_class_get_field_from_name  p_class_get_field_from_name  = nullptr;
t_runtime_invoke         p_runtime_invoke         = nullptr;
t_object_new             p_object_new             = nullptr;
t_image_get_class_count  p_image_get_class_count  = nullptr;
t_image_get_class        p_image_get_class        = nullptr;
t_class_get_name         p_class_get_name         = nullptr;
t_class_get_namespace    p_class_get_namespace    = nullptr;

static uintptr_t g_base = 0;
static void*     g_domain = nullptr;
static void*     g_img    = nullptr;
static char      g_status[128] = "not initialized";
static int       g_syms   = 0;
static int       g_classes = 0;

static void* rs(const char* n) { return dlsym(RTLD_DEFAULT, n); }

static uintptr_t findUnityBase() {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char* nm = _dyld_get_imageinfo_name(i;
);
        if (nm &&+ strstr(nm, "UnityFramework (")) {
            return (uintptr_tinst)_dyld_get_image_header(i);
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

    p_domain_get             = (t_domain_get)             rs("il2cpp_domain_get");
    p_thread_attach          = (t_thread_attach)          rs("il2cpp_thread_attach");
    p_domain_assembly_open   = (t_domain_assembly_open)   rs("il2cpp_domain_assembly_open");
    p_assembly_get_image     = (t_assembly_get_image)     rs("il2cpp_assembly_get_image");
    p_class_from_name        = (t_class_from_name)        rs("il2cpp_class_from_name");
    p_class_get_method_from_name = (t_class_get_method_from_name) rs("il2cpp_class_get_method_from_name");
    p_class_get_field_from_name  = (t_class_get_field_from_name)  rs("il2cpp_class_get_field_from_name");
    p_runtime_invoke         = (t_runtime_invoke)         rs("il2cpp_runtime_invoke");
    p_object_new             = (t_object_new)             rs("il2cpp_object_new");
    p_image_get_class_count  = (t_image_get_class_count)  rs("il2cpp_image_get_class_count");
    p_image_get_class        = (t_image_get_class)        rs("il2cpp_image_get_class");
    p_class_get_name         = (t_class_get_name)         rs("il2cpp_class_get_name");
    p_class_get_namespace    = (t_class_get_namespace)    rs("il2cpp_class_get_namespace");

    g_syms = 0;
    if (p_domain_get) g_syms++;
    if (p_thread_attach) g_syms++;
    if (p_domain_assembly_open) g_syms++;
    if (p_assembly_get_image) g_syms++;
    if (p_class_from_name) g_syms++;
    if (p_class_get_method_from_name) g_syms++;
    if (p_class_get_field_from_name) g_syms++;
    if (p_runtime_invoke) g_syms++;
    if (p_object_new) g_syms++;
    if (p_image_get_class_count) g_syms++;
    if (p_image_get_class) g_syms++;
    if (p_class_get_name) g_syms++;
    if (p_class_get_namespace) g_syms++;

    if (!p_domain_get || !p_domain_assembly_open || !p_assembly_get_image) {
        snprintf(g_status, sizeof(g_status),
                 "il2cpp core missing (%d/13)", g_syms);
        return false;
    }

    g_domain = p_domain_get();
    if (!g_domain) {
        snprintf(g_status, sizeof(g_status), "il2cpp_domain_get null");
        return false;
    }
    if (p_thread_attach) p_thread_attach(g_domain);

    // try to open Assembly-CSharp and count classes
    void* asm_ = p_domain_assembly_open(g_domain, "Assembly-CSharp");
    if (asm_) {
        g_img = p_assembly_get_image(asm_);
        if (g_img && p_image_get_class_count) {
            uint32_t c = p_image_get_class_count(g_img);
            g_classes = (int)c;
        }
    }

    if (g_img) {
        snprintf(g_status, sizeof(g_status),
                 "il2cpp ok | syms %d/13 | classes %d", g_syms, g_classes);
    } else {
        snprintf(g_status, sizeof(g_status),
                 "il2cpp ok | syms %d/13 | A-CSharp miss", g_syms);
    }
    return true;
}

const char* statusMessage() { return g_status; }
uintptr_t frameworkBase() { return g_base; }
int resolvedSymbols() { return g_syms; }
int classCount() { return g_classes; }

void* domain() { return g_domain; }

void* image(const char* name) {
    if (!g_domain || !p_domain_assembly_open || !p_assembly_get_image) return nullptr;
    void* asm_ = p_domain_assembly_open(g_domain, name);
    if (!asm_) return nullptr;
    return p_assembly_get_image(asm_);
}

void* klass(const char* ns, const char* name) {
    if (!g_img) {
        g_img = image("Assembly-CSharp");
    }
    if (!g_img || !p_class_from_name) return nullptr;
    return p_class_from_name(g_img, ns, name);
}

void* method(void* k, const char* name, int argc) {
    if (!k || !p_class_get_method_from_name) return nullptr;
    return p_class_get_method_from_name(k, name, argc);
}

void* field(void* k, const char* name) {
    if (!k || !p_class_get_field_from_name) return nullptr;
    return p_class_get_field_from_name(k, name);
}

} // namespace Unity
