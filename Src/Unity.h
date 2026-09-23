#ifndef UNITY_H
#define UNITY_H
#include <stdint.h>
#include <string>

namespace Unity {

// IL2CPP exported symbols we care about.
typedef void* (*t_domain_get)();
typedef void* (*t_thread_attach)(void*);
typedef void* (*t_domain_assembly_open)(void*, const char*);
typedef void* (*t_assembly_get_image)(void*);
typedef void* (*t_class_from_name)(void*, const char*, const char*);
typedef void* (*t_class_get_method_from_name)(void*, const char*, int);
typedef void* (*t_class_get_field_from_name)(void*, const char*);
typedef void* (*t_runtime_invoke)(void*, void*, void**, void**);
typedef void* (*t_object_new)(void*);
typedef uint32_t (*t_image_get_class_count)(void*);
typedef void* (*t_image_get_class)(void*, uint32_t);
typedef const char* (*t_class_get_name)(void*);
typedef const char* (*t_class_get_namespace)(void*);

// init: locate UnityFramework, resolve symbols, get domain. Returns true on success.
bool init();

// introspection for diagnostics
const char* statusMessage();   // human readable, "il2cpp ok" etc.
uintptr_t frameworkBase();
int       resolvedSymbols();
int       classCount();

// access
void* domain();
void* image(const char* name);
void* klass(const char* ns, const char* name);
void* method(void* klass, const char* name, int argc);
void* field(void* klass, const char* name);

extern t_domain_get             p_domain_get;
extern t_thread_attach          p_thread_attach;
extern t_domain_assembly_open   p_domain_assembly_open;
extern t_assembly_get_image     p_assembly_get_image;
extern t_class_from_name        p_class_from_name;
extern t_class_get_method_from_name p_class_get_method_from_name;
extern t_class_get_field_from_name  p_class_get_field_from_name;
extern t_runtime_invoke         p_runtime_invoke;
extern t_object_new             p_object_new;
extern t_image_get_class_count  p_image_get_class_count;
extern t_image_get_class        p_image_get_class;
extern t_class_get_name         p_class_get_name;
extern t_class_get_namespace    p_class_get_namespace;

} // namespace Unity
#endif
