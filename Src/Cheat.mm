#import "Cheat.h"
#import "Common.h"
#import "Overlay.h"
#import <QuartzCore/QuartzCore.h>

@interface Cheat ()
@property (nonatomic, strong) NSTimer *sceneRetry;
@end

@implementation Cheat

+ (instancetype)shared {
    static Cheat *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [Cheat new]; });
    return s;
}

- (void)start {
    LOGI("Cheat::start");
    // Try to attach now; if the scene isn't ready, keep retrying every 500ms.
    [self tryAttach];
    self.sceneRetry = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                       target:self
                                                     selector:@selector(tryAttach)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)tryAttach {
    CheatOverlay *ov = [CheatOverlay shared];
    [ov attachToScene];
    if (ov.hidden == NO) {
        [ov setInfoText:@"CODM (non-JB)\nbypass active\noverlay visible"];
        [self.sceneRetry invalidate];
        self.sceneRetry = nil;
    }
}

- (void)stop {
    [self.sceneRetry invalidate];
    self.sceneRetry = nil;
    [[CheatOverlay shared] setInfoText:@""];
}

@end
