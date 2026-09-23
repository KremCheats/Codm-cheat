#import "Overlay.h"
@implementation CheatOverlay
+ (instancetype)shared {
    static CheatOverlay *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[CheatOverlay alloc] initWithFrame:[UIScreen mainScreen].bounds]; });
    return s;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.windowLevel = UIWindowLevelAlert + 100;
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
        self.lines = [CAShapeLayer layer];
        self.lines.frame = self.bounds;
        self.lines.fillColor = [UIColor clearColor].CGColor;
        self.lines.lineWidth = 1.0;
        self.lines.strokeColor = [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.8].CGColor;
        self.fov = [CAShapeLayer layer];
        self.fov.frame = self.bounds;
        self.fov.fillColor = [UIColor clearColor].CGColor;
        self.fov.lineWidth = 1.0;
        self.fov.strokeColor = [UIColor colorWithRed:1 green:1 blue:1 alpha:0.35].CGColor;
        self.info = [CATextLayer layer];
        self.info.frame = CGRectMake(12, 60, frame.size.width - 24, 220);
        self.info.foregroundColor = [UIColor colorWithRed:0 green:1 blue:0.5 alpha:1].CGColor;
        self.info.font = (__bridge CFTypeRef)[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        self.info.fontSize = 11;
        self.info.contentsScale = [UIScreen mainScreen].scale;
        self.info.alignmentMode = kCAAlignmentLeft;
        self.info.wrapped = YES;
        [self.layer addSublayer:self.boxes];
        [self.layer addSublayer:self.lines];
        [self.layer addSublayer:self.fov];
        [self.layer addSublayer:self.info];
    }
    return self;
}
- (void)attach {
    self.hidden = NO;
    [self makeKeyAndVisible];
}
- (void)begin { self.boxes.path = NULL; self.lines.path = NULL; self.fov.path = NULL; }
- (void)setFovRadius:(CGFloat)r {
    CGPoint c = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0);
    UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:0 endAngle:M_PI * 2 clockwise:YES];
    self.fov.path = p.CGPath;
}
- (void)setInfoText:(NSString *)t { self.info.string = t; }
- (void)drawBoxAt:(CGRect)r color:(UIColor *)c {
    UIBezierPath *p = [UIBezierPath bezierPathWithRect:r];
    CGMutablePathRef cur = CGPathCreateMutableCopy(self.boxes.path ?: CGPathCreateMutable());
    CGPathAddPath(cur, NULL, p.CGPath);
    self.boxes.path = cur;
    CGPathRelease(cur);
}
- (void)drawLineFrom:(CGPoint)a to:(CGPoint)b color:(UIColor *)c {
    CGMutablePathRef cur = CGPathCreateMutableCopy(self.lines.path ?: CGPathCreateMutable());
    CGPathMoveToPoint(cur, NULL, a.x, a.y);
    CGPathAddLineToPoint(cur, NULL, b.x, b.y);
    self.lines.path = cur;
    CGPathRelease(cur);
}
- (void)clear { self.boxes.path = NULL; self.lines.path = NULL; }
@end
