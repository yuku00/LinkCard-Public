// Foundation/CoreGraphics mock only. Production WUDictation.m is compiled unchanged.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@class UIWindow, UIViewController, UINavigationController, UITouch, UIEvent;
@interface UIResponder : NSObject
@property(nonatomic, weak) UIResponder *nextResponder;
@end
@interface UIView : UIResponder
@property(nonatomic, weak) UIView *superview;
@property(nonatomic, strong) NSMutableArray<UIView *> *subviews;
@property(nonatomic, readonly) UIWindow *window;
@property(nonatomic, getter=isHidden) BOOL hidden;
@property(nonatomic) CGFloat alpha;
@property(nonatomic, getter=isUserInteractionEnabled) BOOL userInteractionEnabled;
@property(nonatomic, getter=isFirstResponder) BOOL firstResponder;
@property(nonatomic) CGRect bounds, frame;
@property(nonatomic) NSUInteger focusCalls;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (BOOL)isDescendantOfView:(UIView *)view;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (BOOL)becomeFirstResponder;
- (void)setNeedsLayout;
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
@end
@interface UIImageView : UIView @end
@interface UIWindow : UIView
@property(nonatomic, getter=isKeyWindow) BOOL keyWindow;
@end
@interface UIViewController : UIResponder
@property(nonatomic, strong) UIViewController *presentedViewController;
@property(nonatomic, strong) UINavigationController *navigationController;
@property(nonatomic, getter=isBeingDismissed) BOOL beingDismissed;
@end
@interface UINavigationController : UIViewController
@property(nonatomic, strong) UIViewController *topViewController;
@end
@interface UIApplication : NSObject
@property(nonatomic) NSInteger applicationState;
+ (instancetype)sharedApplication;
@end
enum { UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground };
FOUNDATION_EXPORT NSString *const UIApplicationWillResignActiveNotification;
FOUNDATION_EXPORT NSString *const UIApplicationDidBecomeActiveNotification;
typedef NS_ENUM(NSInteger, UITouchPhase) { UITouchPhaseBegan, UITouchPhaseMoved, UITouchPhaseStationary, UITouchPhaseEnded, UITouchPhaseCancelled };
@interface UITouch : NSObject
@property(nonatomic) NSTimeInterval timestamp;
@property(nonatomic) UITouchPhase phase;
@property(nonatomic, weak) UIView *view;
@property(nonatomic) CGPoint point;
- (CGPoint)locationInView:(UIView *)view;
@end
@interface UIEvent : NSObject
@property(nonatomic, strong) NSSet<UITouch *> *allTouches;
@end
