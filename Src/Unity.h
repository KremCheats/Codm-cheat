#ifndef UNITY_H
#define UNITY_H
#include <stdint.h>
namespace Unity {
bool init();
const char* statusMessage();
uintptr_t frameworkBase();
int resolvedSymbols();
int classCount();
}
#endif
