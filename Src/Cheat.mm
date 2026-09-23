#import "Cheat.h"
#import "Common.h"
#import "Overlay.h"
#import "Unity.h"
#import <QuartzCore/QuartzCore.h>

struct CheatCfg {
    bool espEnabled = true, espBoxes = true, espLines = true;
    bool fovEnabled = true; float fovRadius = 220.0f;
    bool aimEnabled = true, silentAim = false, aimVisibleOnly = true;
    float aimFov = 90.0f, aimSmooth = 4.0f; int aimBone = 0;
    bool noRecoil = true, noSpread = true;
    float maxDistance = 400.0f;
};
static CheatCfg g_cfg;

@interface Cheat ()
@property (nonatomic, strong) CADisplayLink *tick;
@end

@implementation Cheat
+ (instancetype)shared {
    static Cheat *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [Cheat new]; });
    return s;
}
- (void)start {
    [[CheatOverlay shared] attach];
    [[CheatOverlay shared] setFovRadius:g_cfg.fovRadius];
    if (Unity::init()) {
        [[CheatOverlay shared] setInfoText:@"CODM (non-JB) | il2cpp ok\nwaiting for match..."];
    } else {
        [[CheatOverlay shared] setInfoText:@"CODM (non-JB) | il2cpp exports missing"];
    }
    self.tick = [CADisplayLink displayLinkWithTarget:self selector:@selector(onTick:)];
    [self.tick addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)stop {
    [self.tick invalidate];
    self.tick = nil;
    [[CheatOverlay shared] clear];
}
- (void)onTick:(CADisplayLink *)dl {
    if (!Unity::domain()) return;
    CheatOverlay *ov = [CheatOverlay shared];
    [ov begin];
    [ov setFovRadius:g_cfg.fovEnabled ? g_cfg.fovRadius : 0.0f];
    [ov setInfoText:@"CODM (non-JB) | running"];
}
@end
