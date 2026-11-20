#import <UIKit/UIKit.h>

// Called from the existing chat lifecycle hooks, never installs a second hook.
void WUDragDropAppeared(UIViewController *owner);
void WUDragDropDisappeared(UIViewController *owner);
BOOL WUDragDropAvailable(void);
BOOL WUDragDropLifecycleAvailable(void);
