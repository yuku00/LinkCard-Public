#import "ReadOnly.h"
#ifdef RO_HOST
#import "../tests/ReadonlyUIKit.h"
#else
#import <UIKit/UIKit.h>
#endif

UIViewController *ROVisibleHost(UIWindow *window);
NSDictionary *ROGraph(UIWindow *window, ROSession *session);
