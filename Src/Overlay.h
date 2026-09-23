#ifndef OVERLAY_H
#define OVERLAY_H
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
@interface SRWindow : UIWindow
@property (nonatomic, strong) CAShapeLayer *boxes;
@property (nonatomic, strong) CATextLayer *info;
+ (instancetype)shared;
- (void)attachToScene;
- (void)setInfoText:(NSString *)t;
@end
#endif
