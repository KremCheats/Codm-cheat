#ifndef COMMON_H
#define COMMON_H
#import <Foundation/Foundation.h>
#import <os/log.h>
#define LOGI(fmt, ...) os_log(OS_LOG_DEFAULT, "[srt] " fmt, ##__VA_ARGS__)
#endif
