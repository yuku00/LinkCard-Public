#import <Foundation/Foundation.h>
@class UIWindow,UIViewController;
@interface UIView : NSObject
@property(nonatomic,strong) NSArray *subviews;
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,strong) id nextResponder;
@property(nonatomic) BOOL hidden;
@end
@interface UIWindow : UIView
@property(nonatomic,strong) UIViewController *rootViewController;
@end
@interface UIViewController : NSObject
@property(nonatomic,strong) NSArray *childViewControllers;
@property(nonatomic,strong) UIViewController *presentedViewController;
@property(nonatomic,weak) UIViewController *parentViewController;
@property(nonatomic,strong) UIView *viewIfLoaded;
@property(nonatomic) BOOL isBeingDismissed;
@end
@interface UINavigationController : UIViewController
@property(nonatomic,strong) UIViewController *visibleViewController;
@end
@interface UITabBarController : UIViewController
@property(nonatomic,strong) UIViewController *selectedViewController;
@end
@interface UITableView : UIView
@property(nonatomic,strong) id dataSource;
@property(nonatomic,strong) id delegate;
@end
@interface UICollectionView : UIView
@property(nonatomic,strong) id dataSource;
@property(nonatomic,strong) id delegate;
@property(nonatomic,strong) id collectionViewLayout;
@end
