#ifndef OVERLAY_H
#define OVERLAY_H
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include "Common.h"
@interface CheatOverlay : UIWindow
@property (nonatomic, strong) CAShapeLayer *boxes;
@property (nonatomic, strong) CAShapeLayer *lines;
@property (nonatomic, strong) CAShapeLayer *fov;
@property (nonatomic, strong) CATextLayer *info;
+ (instancetype)shared;
- (void)attach;
- (void)begin;
- (void)setFovRadius:(CGFloat)r;
- (void)setInfoText:(NSString *)t;
- (void)clear;
- (void)drawBoxAt:(CGRect)r color:(UIColor *)c;
- (void)drawLineFrom:(CGPoint)a to:(CGPoint)b color:(UIColor *)c;
@end
#endif
