#import "Unity.h"
#import "Common.h"
#import <dlfcn.h>
#import <string.h>
#import <mach-o/dyld.h>
namespace Unity {
t_dg p_domain_get = nullptr;
t_dao p_domain_assembly_open = nullptr;
t_agi p_assembly_get_image = nullptr;
t_cfn p_class_from_name = nullptr;
t_cgm p_class_get_method_from_name = nullptr;
t_cgf p_class_get_field_from_name = nullptr;
t_ri p_runtime_invoke = nullptr;
static void *g_domain = nullptr;
static void *g_img = nullptr;
static void *rs(const char *n) { return dlsym(RTLD_DEFAULT, n); }
bool init() {
    p_domain_get = (t_dg)rs("il2cpp_domain_get");
    p_domain_assembly_open = (t_dao)rs("il2cpp_domain_assembly_open");
    p_assembly_get_image = (t_agi)rs("il2cpp_assembly_get_image");
    p_class_from_name = (t_cfn)rs("il2cpp_class_from_name");
    p_class_get_method_from_name = (t_cgm)rs("il2cpp_class_get_method_from_name");
    p_class_get_field_from_name = (t_cgf)rs("il2cpp_class_get_field_from_name");
    p_runtime_invoke = (t_ri)rs("il2cpp_runtime_invoke");
    if (!p_domain_get || !p_domain_assembly_open || !p_assembly_get_image) return false;
    g_domain = p_domain_get();
    return g_domain != nullptr;
}
void* domain() { return g_domain; }
void* klass(const char *ns, const char *n) {
    if (!g_img) {
        if (!g_domain) return nullptr;
        void *asm_ = p_domain_assembly_open(g_domain, "Assembly-CSharp");
        if (!asm_) return nullptr;
        g_img = p_assembly_get_image(asm_);
    }
    if (!g_img || !p_class_from_name) return nullptr;
    return p_class_from_name(g_img, ns, n);
}
void* method(void *k, const char *n, int a) {
    if (!k || !p_class_get_method_from_name) return nullptr;
    return p_class_get_method_from_name(k, n, a);
}
void* field(void *k, const char *n) {
    if (!k || !p_class_get_field_from_name) return nullptr;
    return p_class_get_field_from_name(k, n);
}
void readFieldRaw(void *o, void *k, const char *n, void *out, size_t sz) {
    void *f = field(k, n);
    if (!f) return;
    // il2cpp_field_get_value would be called here; stub for build
}
void writeFieldRaw(void *o, void *k, const char *n, const void *in, size_t sz) {
    void *f = field(k, n);
    if (!f) return;
}
}
