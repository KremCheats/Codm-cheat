#ifndef UNITY_H
#define UNITY_H
#include <stdint.h>
namespace Unity {
typedef void* (*t_dg)();
typedef void* (*t_dao)(void*,const char*);
typedef void* (*t_agi)(void*);
typedef void* (*t_cfn)(void*,const char*,const char*);
typedef void* (*t_cgm)(void*,const char*,int);
typedef void* (*t_cgf)(void*,const char*);
typedef void* (*t_ri)(void*,void*,void**,void**);
bool init();
void* domain();
void* klass(const char*,const char*);
void* method(void*,const char*,int);
void* field(void*,const char*);
void readFieldRaw(void*,void*,const char*,void*,size_t);
void writeFieldRaw(void*,void*,const char*,const void*,size_t);
extern t_dg p_domain_get;
extern t_dao p_domain_assembly_open;
extern t_agi p_assembly_get_image;
extern t_cfn p_class_from_name;
extern t_cgm p_class_get_method_from_name;
extern t_cgf p_class_get_field_from_name;
extern t_ri p_runtime_invoke;
}
#endif
