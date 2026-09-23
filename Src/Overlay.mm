#import "Overlay.h"

@implementation SRWindow
+ (instancetype)shared {
    static SRWindow *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[SRWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    });
    return s;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.windowLevel = UIWindowLevelNormal + 1;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.hidden = YES;
        self.boxes = [CAShapeLayer layer];
        self.boxes.frame = self.bounds;
        self.boxes.fillColor = [UIColor clearColor].CGColor;
        self.boxes.lineWidth = 1.5;
        self.boxes.strokeColor = [UIColor colorWithRed:0 green:1 blue:0.3 alpha:1].CGColor;
        self.info = [CATextLayer layer];
        self.info.frame = CGRectMake(12, 70, frame.size.width - 24, 400);
        self.info.foregroundColor = [UIColor colorWithRed:0.6 green:0.8 blue:0.6 alpha:1].CGColor;
        self.info.fontSize = 11;
        self.info.contentsScale = [UIScreen mainScreen].scale;
        self.info.alignmentMode = kCAAlignmentLeft;
        self.info.wrapped = YES;
        self.info.string = @"";
        [self.layer addSublayer:self.boxes];
        [self.layer addSublayer:self.info];
    }
    return self;
}
- (void)attachToScene {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            if (s.activationState == UISceneActivationStateForegroundActive ||
                s.activationState == UISceneActivationStateForegroundInactive) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
    }
    if (scene) {
        self.windowScene = scene;
        self.hidden = NO;
        self.windowLevel = UIWindowLevelNormal + 1;
    }
}
- (void)setInfoText:(NSString *)t { self.info.string = t; }
@end
