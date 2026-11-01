// Extends the main tests/dictation-stubs UIKit surface; Foundation/runtime stay real.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
@class UIWindow, UIViewController, UINavigationController, UIEvent, UITouch, UIPopoverPresentationController, UIBarButtonItem;
@interface UIResponder : NSObject
@property(nonatomic,weak) UIResponder *nextResponder;
@end
@interface UIView : UIResponder
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) NSMutableArray<UIView *> *subviews;
@property(nonatomic,readonly) UIWindow *window;
@property(nonatomic,getter=isFirstResponder) BOOL firstResponder;
@property(nonatomic) CGRect bounds;
@property(nonatomic,strong) UIView *hitResult;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (BOOL)isDescendantOfView:(UIView *)view;
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
- (BOOL)resignFirstResponder;
@end
@interface UIImageView : UIView @end
@interface UITextView : UIView @end
@interface UITextField : UIView @end
@interface UIControl : UIView
@property(nonatomic,copy) NSString *accessibilityIdentifier, *accessibilityLabel;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events;
@end
@interface UISwitch : UIControl
@property(nonatomic) BOOL on, enabled;
@end
@interface UIWindow : UIView
@property(nonatomic,getter=isKeyWindow) BOOL keyWindow;
@property(nonatomic,strong) UIViewController *rootViewController;
@end
@interface UINavigationItem : NSObject
@property(nonatomic,strong) UIBarButtonItem *rightBarButtonItem;
@end
@interface UIViewController : UIResponder
@property(nonatomic,strong) UIView *view;
@property(nonatomic,readonly) UIView *viewIfLoaded;
@property(nonatomic,readonly,getter=isViewLoaded) BOOL viewLoaded;
@property(nonatomic,strong) UIViewController *presentedViewController;
@property(nonatomic,weak) UIViewController *presentingViewController;
@property(nonatomic,weak) UINavigationController *navigationController;
@property(nonatomic,strong) UINavigationItem *navigationItem;
@property(nonatomic,copy) NSString *title;
@property(nonatomic) NSUInteger presents,dismisses;
@property(nonatomic) BOOL deferDismissCompletion;
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void(^)(void))completion;
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void(^)(void))completion;
- (void)viewDidLoad;
@end
@interface UINavigationController : UIViewController
@property(nonatomic,strong) UIViewController *visibleViewController, *topViewController;
- (void)pushViewController:(UIViewController *)controller animated:(BOOL)animated;
@end
@interface UITabBarController : UIViewController
@property(nonatomic,strong) UIViewController *selectedViewController;
@end
@interface UIScene : NSObject
@property(nonatomic) NSInteger activationState;
@end
@interface UIWindowScene : UIScene
@property(nonatomic,strong) NSArray<UIWindow *> *windows;
@end
@interface UIApplication : NSObject
@property(nonatomic) NSInteger applicationState;
@property(nonatomic,strong) NSSet<UIScene *> *connectedScenes;
+ (instancetype)sharedApplication;
@end
enum { UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground };
enum { UISceneActivationStateForegroundActive, UISceneActivationStateBackground };
FOUNDATION_EXPORT NSString *const UIApplicationWillResignActiveNotification;
FOUNDATION_EXPORT NSString *const UIApplicationDidBecomeActiveNotification;
typedef NS_ENUM(NSInteger, UITouchPhase) { UITouchPhaseBegan, UITouchPhaseMoved, UITouchPhaseStationary, UITouchPhaseEnded, UITouchPhaseCancelled };
@interface UITouch : NSObject
@property(nonatomic) UITouchPhase phase;
@property(nonatomic) CGPoint point;
- (CGPoint)locationInView:(UIView *)view;
@end
@interface UIEvent : NSObject @end
typedef NS_ENUM(NSInteger, UIAlertActionStyle) { UIAlertActionStyleDefault, UIAlertActionStyleCancel };
typedef NS_ENUM(NSInteger, UIAlertControllerStyle) { UIAlertControllerStyleAlert, UIAlertControllerStyleActionSheet };
@interface UIAlertAction : NSObject
@property(nonatomic,copy) NSString *title;
@property(nonatomic) UIAlertActionStyle style;
@property(nonatomic,copy) void (^handler)(UIAlertAction *);
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void(^)(UIAlertAction *))handler;
- (void)fire;
@end
@interface UIPopoverPresentationController : NSObject
@property(nonatomic,strong) UIView *sourceView;
@property(nonatomic) CGRect sourceRect;
@end
@interface UIAlertController : UIViewController
@property(nonatomic,strong) NSMutableArray<UIAlertAction *> *actions;
@property(nonatomic,strong) UIPopoverPresentationController *popoverPresentationController;
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style;
- (void)addAction:(UIAlertAction *)action;
@end
@interface UITableView : UIView
- (void)reloadData;
@end
@interface UITableViewController : UIViewController
@property(nonatomic,strong) UITableView *tableView;
- (instancetype)initWithStyle:(NSInteger)style;
@end
@interface UILabel : UIView
@property(nonatomic,copy) NSString *text;
@property(nonatomic) NSInteger numberOfLines;
@end
@interface UITableViewCell : UIView
@property(nonatomic,strong) UILabel *textLabel, *detailTextLabel;
@property(nonatomic,strong) UIView *accessoryView;
@property(nonatomic) NSInteger selectionStyle;
- (instancetype)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)identifier;
@end
@interface NSIndexPath (UIKitMock)
@property(nonatomic,readonly) NSInteger row;
@end
@interface UIBarButtonItem : NSObject
- (instancetype)initWithTitle:(NSString *)title style:(NSInteger)style target:(id)target action:(SEL)action;
@end
enum { UITableViewStyleInsetGrouped, UITableViewCellStyleSubtitle, UITableViewCellSelectionStyleNone, UIBarButtonItemStylePlain, UIControlEventValueChanged };
