#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import "Theme.h"

// Intentionally no rules loader, identities, query hooks, replay or mailbox actions.
static char PanelKey;
@interface MRSafetyPanel : NSObject {
@public
    UIViewController *owner; // associated object's lifetime is bounded by its owner
    UIBarButtonItem *button;
}
- (void)show;
@end
@implementation MRSafetyPanel
- (void)show {
    if(owner.presentedViewController) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Mail 0.4.0 · 安全隔离版" message:@"发件人隐藏已完全停用，旧规则数据未改动。\n本版未实现同账号新建邮箱与批量移动，不会操作邮件。\n外观仅调整系统首页、列表和阅读页外围；保持原入口、排序、徽标与正文。" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:MRThemeEnabled()?@"关闭原生简洁外观":@"开启原生简洁外观" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){ MRThemeSetEnabled(!MRThemeEnabled()); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.barButtonItem=button;
    [owner presentViewController:alert animated:YES completion:nil];
}
- (void)dealloc { [button release]; [super dealloc]; }
@end
__attribute__((constructor)) static void InstallSafetyPanel(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobilemail"]) return;
        char build[64]={0};size_t size=sizeof(build);
        if(sysctlbyname("kern.osversion",build,&size,NULL,0) || strcmp(build,"20G75")) return;
        Class c=NSClassFromString(@"MessageListViewController");
        SEL sel=@selector(viewDidAppear:); Method method=class_getInstanceMethod(c,sel);
        if(!method || strcmp(method_getTypeEncoding(method),"v20@0:8B16")) return;
        IMP original=method_getImplementation(method);
        IMP replacement=imp_implementationWithBlock(^(UIViewController *vc,BOOL animated) {
            ((void(*)(id,SEL,BOOL))original)(vc,sel,animated);
            if(![NSStringFromClass(vc.class) isEqual:@"MessageListViewController"]) return;
            MRSafetyPanel *panel=objc_getAssociatedObject(vc,&PanelKey);
            if(!panel) {
                panel=[[[MRSafetyPanel alloc] init] autorelease]; panel->owner=vc;
                panel->button=[[UIBarButtonItem alloc] initWithTitle:@"插件" style:UIBarButtonItemStylePlain target:panel action:@selector(show)];
                panel->button.accessibilityLabel=@"Mail 插件状态与外观";
                objc_setAssociatedObject(vc,&PanelKey,panel,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            NSArray *items=vc.navigationItem.rightBarButtonItems ?: @[];
            if(![items containsObject:panel->button]) vc.navigationItem.rightBarButtonItems=[items arrayByAddingObject:panel->button];
        });
        if(!class_addMethod(c,sel,replacement,method_getTypeEncoding(method))) method_setImplementation(method,replacement);
    }
}
