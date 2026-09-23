#ifndef RUNTIME_H
#define RUNTIME_H
#import <Foundation/Foundation.h>
@interface Runtime : NSObject
+ (instancetype)shared;
- (void)start;
- (void)stop;
@end
#endif
