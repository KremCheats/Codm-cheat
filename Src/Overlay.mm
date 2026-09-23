#import "Overlay.h"
@implementation CheatOverlay
+ (instancetype)shared {
    static CheatOverlay *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[CheatOverlay alloc] initWithFrame:[UIScreen mainScreen].bounds]; });
    return s;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.windowLevel = UIWindow;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.rootViewController = [UIViewController new];
        self.rootViewController.view.backgroundColor = [UIColor clearColor];
        self.hidden = YES;
        self.boxes = [CAShapeLayer layer];
        self.boxes.frame = self.bounds;
        self.boxes.fillColor = [UIColor clearColor].CGColor;
        self.boxes.lineWidth = 1.2;
        self.boxes.strokeColor = [UIColor colorWithRed:0 green:1 blue:0.3 alpha:1].CGColor;
        self.info = [CATextLayer layer];
        self.info.frame = CGRectMake(12, 60, frame.size.width - 24, 220);
        self.info.foregroundColor = [UIColor colorWithRed:0 green:1 blue:0.5 alpha:1].CGColor;
        self.info.fontSize = 11;
        self.info.contentsScale = [UIScreen mainScreen].scale;
        self.info.alignmentMode = kCAAlignmentLeft;
        self.info.wrapped = YES;
        [self.layer addSublayer:self.boxes];
        [self.layer addSublayer:self.info];
    }
    return self;
}
- (void)attach { self.hidden = NO; [self makeKeyAndVisible]; }
- (void)setInfoText:(NSString *)t { self.info.string = t; }
@end
