#import "Cheat.h"
#import "Common.h"
#import "Overlay.h"
#import "Unity.h"
#import <QuartzCore/QuartzCore.h>

@interface Cheat ()
@property (nonatomic, strong) NSTimer *sceneRetry;
@property (nonatomic, strong) NSTimer *unityRetry;
@property (nonatomic, assign) BOOL unityOk;
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
    CheatOverlay *ov = [CheatOverlay shared];
    [ov attachToScene];
    if (ov.hidden == NO) {
        [self render];
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
    [self render];
}

- (void)render {
    CheatOverlay *ov = [CheatOverlay shared];
    NSMutableString* s = [NSMutableString string];
    [s appendString:@"CODM (non-JB)\n"];
    [s appendString:@"bypass active\n"];
    [s appendFormat:@"unity: %s\n", Unity::statusMessage()];
    if (self.unityOk) {
        [s appendFormat:@"fw: 0x%lx\n", (unsigned long)Unity::frameworkBase()];
        [s appendFormat:@"syms: %d/13\n", Unity::resolvedSymbols()];
        [s appendFormat:@"classes: %d\n", Unity::classCount()];
        [s appendString:@"il2cpp reachable"];
    } else {
        [s appendString:@"waiting for unity..."];
    }
    [ov setInfoText:s];
}

- (void)stop {
    [self.sceneRetry invalidate]; self.sceneRetry = nil;
    [self.unityRetry invalidate]; self.unityRetry = nil;
    [[CheatOverlay shared] setInfoText:@""];
}

@end
