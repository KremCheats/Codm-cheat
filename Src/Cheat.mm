#import "Cheat.h"
#import "Common.h"
#import "Overlay.h"
#import <QuartzCore/QuartzCore.h>

@implementation Cheat
+ (instancetype)shared {
    static Cheat *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [Cheat new]; });
    return s;
}
- (void)start {
    LOGI("Cheat::start");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CheatOverlay shared] attach];
        [[CheatOverlay shared] setInfoText:@"CODM (non-JB)\nbypass active"];
    });
}
- (void)stop {}
@end
