#ifndef COMMON_H
#define COMMON_H
#import <Foundation/Foundation.h>
#import <os/log.h>
#ifdef DEBUG
    #define LOGI(fmt, ...) os_log(OS_LOG_DEFAULT, "[CODMCheat] " fmt, ##__VA_ARGS__)
#else
    #define LOGI(fmt, ...) ((void)0)
#endif
#define KERN_PROC_PID 1
struct Matrix4x4 { float m[16]; };
struct Vec3 { float x, y, z; };
static inline Vec3 vec3_sub(Vec3 a, Vec3 b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
static inline float vec3_len(Vec3 v) { return sqrtf(v.x*v.x + v.y*v.y + v.z*v.z); }
#endif
