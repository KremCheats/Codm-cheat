#ifndef OVERLAY_H
#define OVERLAY_H
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
@interface CheatOverlay : UIWindow
@property (nonatomic, strong) CAShapeLayer *boxes;
@property (nonatomic, strong) CATextLayer *info;
+ (instancetype)shared;
- (void)attachToScene;
- (void)begin;
- (void)setInfoText:(NSString *)t;
- (void)drawBoxAt:(CGRect)r color:(UIColor *)c;
- (void)drawLineFrom:(CGPoint)a to:(CGPoint)b color:(UIColor *)c;
@end
#endif
