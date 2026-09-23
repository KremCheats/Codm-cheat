#ifndef CHEAT_H
#define CHEAT_H
#import <Foundation/Foundation.h>
@interface Cheat : NSObject
+ (instancetype)shared;
- (void)start;
- (void)stop;
@end
#endif
