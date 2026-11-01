#import <UIKit/UIKit.h>
NSString *const UIApplicationWillResignActiveNotification=@"mock.resign";
NSString *const UIApplicationDidBecomeActiveNotification=@"mock.active";
static NSMutableArray *dismissals;
void WUTestFlushDismissals(void) { NSArray *copy=[dismissals copy]; [dismissals removeAllObjects]; for(dispatch_block_t b in copy) b(); }
@implementation UIResponder @end
@implementation UIView
- (instancetype)init { if((self=[super init])) { _bounds=CGRectMake(0,0,100,100); _subviews=[NSMutableArray array]; } return self; }
- (UIWindow *)window { return [self isKindOfClass:UIWindow.class]?(id)self:self.superview.window; }
- (void)addSubview:(UIView *)v { UIResponder *owner=v.nextResponder; [v removeFromSuperview]; [_subviews addObject:v]; v.superview=self; v.nextResponder=[owner isKindOfClass:UIViewController.class]?owner:self; }
- (void)removeFromSuperview { [self.superview.subviews removeObject:self]; self.superview=nil; self.nextResponder=nil; }
- (BOOL)isDescendantOfView:(UIView *)v { for(UIView *p=self;p;p=p.superview) if(p==v) return YES; return NO; }
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { return self.hitResult?:self; }
- (BOOL)resignFirstResponder { self.firstResponder=NO; return YES; }
@end
@implementation UIImageView @end
@implementation UITextView @end
@implementation UITextField @end
@implementation UIControl
- (void)addTarget:(id)t action:(SEL)a forControlEvents:(NSUInteger)e {}
@end
@implementation UISwitch @end
@implementation UIWindow @end
@implementation UINavigationItem @end
@implementation UIViewController
- (instancetype)init { if((self=[super init])) { _view=[UIView new]; _view.nextResponder=self; _navigationItem=[UINavigationItem new]; } return self; }
- (UIView *)viewIfLoaded { return _view; }
- (BOOL)isViewLoaded { return _view!=nil; }
- (void)viewDidLoad {}
- (void)presentViewController:(UIViewController *)v animated:(BOOL)b completion:(void(^)(void))f {
    NSCAssert(!self.presentedViewController,@"mock rejects stacked presentation"); self.presents++; self.presentedViewController=v; v.presentingViewController=self; if(f) f();
}
- (void)dismissViewControllerAnimated:(BOOL)b completion:(void(^)(void))f {
    self.dismisses++;
    if(self.presentingViewController.presentedViewController==self) self.presentingViewController.presentedViewController=nil;
    self.presentingViewController=nil; self.presentedViewController=nil;
    if(f && self.deferDismissCompletion) { if(!dismissals) dismissals=[NSMutableArray array]; [dismissals addObject:[f copy]]; }
    else if(f) f();
}
@end
@implementation UINavigationController
- (void)pushViewController:(UIViewController *)v animated:(BOOL)b { self.visibleViewController=v; self.topViewController=v; v.navigationController=self; }
@end
@implementation UITabBarController @end
@implementation UIScene @end
@implementation UIWindowScene @end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *a; if(!a) a=[UIApplication new]; return a; }
@end
@implementation UITouch
- (CGPoint)locationInView:(UIView *)v { return self.point; }
@end
@implementation UIEvent @end
@implementation UIAlertAction
+ (instancetype)actionWithTitle:(NSString *)t style:(UIAlertActionStyle)s handler:(void(^)(UIAlertAction *))h { UIAlertAction *a=[self new]; a.title=t; a.style=s; a.handler=h; return a; }
- (void)fire { if(self.handler) self.handler(self); }
@end
@implementation UIPopoverPresentationController @end
@implementation UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)t message:(NSString *)m preferredStyle:(UIAlertControllerStyle)s {
    UIAlertController *a=[self new]; a.title=t; a.actions=[NSMutableArray array]; a.popoverPresentationController=[UIPopoverPresentationController new]; return a;
}
- (void)addAction:(UIAlertAction *)a { [self.actions addObject:a]; }
@end
@implementation UITableView
- (void)reloadData {}
@end
@implementation UITableViewController
- (instancetype)initWithStyle:(NSInteger)s { if((self=[super init])) _tableView=[UITableView new]; return self; }
@end
@implementation UILabel @end
@implementation UITableViewCell
- (instancetype)initWithStyle:(NSInteger)s reuseIdentifier:(NSString *)i { if((self=[super init])) { _textLabel=[UILabel new]; _detailTextLabel=[UILabel new]; } return self; }
@end
@implementation NSIndexPath (UIKitMock)
- (NSInteger)row { return [self indexAtPosition:self.length-1]; }
@end
@implementation UIBarButtonItem
- (instancetype)initWithTitle:(NSString *)t style:(NSInteger)s target:(id)target action:(SEL)a { return [super init]; }
@end
