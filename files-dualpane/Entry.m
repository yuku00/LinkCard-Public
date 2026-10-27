#import "DualPane.h"
#import <objc/runtime.h>
#import <sys/sysctl.h>
#include <string.h>

@interface FPEntry : NSObject
+ (instancetype)shared;
- (void)open:(UIBarButtonItem *)sender;
@end
@implementation FPEntry
+ (instancetype)shared { static FPEntry *entry; static dispatch_once_t once; dispatch_once(&once,^{ entry=[FPEntry new]; }); return entry; }
- (void)open:(UIBarButtonItem *)sender {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive) continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIViewController *root=window.rootViewController;
            if(window.isKeyWindow && root && !root.presentedViewController) { FPDualPanePresent(root); return; }
        }
    }
}
@end
static void AddEntry(UIViewController *vc) {
    if(!vc.navigationController || vc.navigationController.topViewController!=vc || FPDualPaneContains(vc)) return;
    UIViewController *root=vc.view.window.rootViewController;
    if(!root || root.presentedViewController || ![NSStringFromClass(vc.class) containsString:@"DOC"]) return;
    NSMutableArray *items=[vc.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray new];
    for(UIBarButtonItem *item in items) if(item.target==[FPEntry shared]) return;
    UIBarButtonItem *button=[[UIBarButtonItem alloc] initWithTitle:@"双窗格" style:UIBarButtonItemStylePlain target:[FPEntry shared] action:@selector(open:)];
    button.accessibilityLabel=@"打开双原生 Files 浏览窗格";
    [items addObject:button]; vc.navigationItem.rightBarButtonItems=items;
}
__attribute__((constructor)) static void FPStart(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.DocumentsApp"]) return;
        char build[64]={0}; size_t size=sizeof(build); sysctlbyname("kern.osversion",build,&size,NULL,0);
        if(strcmp(build,"20G75")) return;
        Method m=class_getInstanceMethod(UIViewController.class,@selector(viewDidAppear:)); IMP original=method_getImplementation(m);
        method_setImplementation(m,imp_implementationWithBlock(^(UIViewController *self,BOOL animated){
            ((void(*)(id,SEL,BOOL))original)(self,@selector(viewDidAppear:),animated);
            dispatch_async(dispatch_get_main_queue(),^{ AddEntry(self); });
        }));
    }
}
