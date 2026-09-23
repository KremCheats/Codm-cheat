#import "Runtime.h"
#import "Common.h"
#import "Overlay.h"
#import "Unity.h"
#import <QuartzCore/QuartzCore.h>

@interface Runtime ()
@property (nonatomic, strong) NSTimer *sceneRetry;
@property (nonatomic, strong) NSTimer *unityRetry;
@property (nonatomic, assign) BOOL unityOk;
@end

@implementation Runtime
+ (instancetype)shared {
    static Runtime *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [Runtime new]; });
    return s;
}
- (void)start {
    [self tryAttach];
    self.sceneRetry = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                       target:self
                                                     selector:@selector(tryAttach)
                                                     userInfo:nil
                                                      repeats:YES];
    self.unityRetry = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                       target:self
                                                     selector:@selector(tryUnity)
                                                     userInfo:nil
                                                      repeats:YES];
}
- (void)tryAttach {
    SRWindow *ov = [SRWindow shared];
    [ov attachToScene];
    if (ov.hidden == NO) {
        [self.sceneRetry invalidate];
        self.sceneRetry = nil;
    }
}
- (void)tryUnity {
    if (self.unityOk) return;
    if (Unity::init()) {
        self.unityOk = YES;
        [self.unityRetry invalidate];
        self.unityRetry = nil;
    }
#ifdef DEBUG_OVERLAY
    SRWindow *ov = [SRWindow shared];
    [ov setInfoText:[NSString stringWithUTF8String:Unity::statusMessage()]];
#endif
}
- (void)stop {
    [self.sceneRetry invalidate]; self.sceneRetry = nil;
    [self.unityRetry invalidate]; self.unityRetry = nil;
}
@end
