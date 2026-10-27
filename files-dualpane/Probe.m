#import <UIKit/UIKit.h>
#import "LifecycleTrace.h"
#import "NativeExperiment.h"

@interface FPViewer : UIViewController
@property(nonatomic,copy) NSString *report;
@end
@implementation FPViewer
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Files 0.3.0 原生实验";
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    UITextView *text=[[UITextView alloc] initWithFrame:self.view.bounds];
    text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    text.editable=NO; text.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    text.text=self.report; [self.view addSubview:text];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)share {
    UIActivityViewController *activity=[[UIActivityViewController alloc] initWithActivityItems:@[self.report] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
    [self presentViewController:activity animated:YES completion:nil];
}
@end

@interface FPEntry : NSObject
@property(nonatomic,strong) NSMapTable *buttons;
+ (instancetype)shared;
- (void)install;
- (void)activate:(UIButton *)button;
@end
@implementation FPEntry
+ (instancetype)shared { static FPEntry *entry; static dispatch_once_t once; dispatch_once(&once,^{ entry=[FPEntry new]; entry.buttons=[NSMapTable weakToWeakObjectsMapTable]; }); return entry; }
- (void)install {
    if(![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(),^{ [self install]; }); return; }
    for(UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if(![s isKindOfClass:UIWindowScene.class] || s.activationState!=UISceneActivationStateForegroundActive) continue;
        for(UIWindow *w in ((UIWindowScene *)s).windows) {
            if(!w.isKeyWindow || w.windowLevel!=UIWindowLevelNormal || !w.rootViewController) continue;
            UIButton *b=[self.buttons objectForKey:w];
            if(b) { [w bringSubviewToFront:b]; continue; }
            b=[UIButton buttonWithType:UIButtonTypeSystem];
            [b setTitle:@"原生实验 / 导出" forState:UIControlStateNormal];
            b.accessibilityLabel=@"打开最后一次原生实验或停止并导出匿名报告";
            b.backgroundColor=UIColor.secondarySystemBackgroundColor; b.layer.cornerRadius=10;
            b.translatesAutoresizingMaskIntoConstraints=NO;
            [b addTarget:self action:@selector(activate:) forControlEvents:UIControlEventTouchUpInside];
            [w addSubview:b]; [self.buttons setObject:b forKey:w];
            [NSLayoutConstraint activateConstraints:@[
                [b.trailingAnchor constraintEqualToAnchor:w.safeAreaLayoutGuide.trailingAnchor constant:-8],
                [b.bottomAnchor constraintEqualToAnchor:w.safeAreaLayoutGuide.bottomAnchor constant:-52],
                [b.widthAnchor constraintEqualToConstant:120], [b.heightAnchor constraintEqualToConstant:44]]];
        }
    }
}
- (void)activate:(UIButton *)button {
    UIWindow *w=button.window; if(!w) return;
    UIViewController *host=w.rootViewController;
    while(host.presentedViewController && !host.presentedViewController.isBeingDismissed) host=host.presentedViewController;
    // Never stack over an existing sheet, picker or action menu.
    if(host!=w.rootViewController || host.isBeingPresented || host.isBeingDismissed) return;
    if(!FPExperimentHasRun()) {
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"最后一次原生实例实验" message:@"新增一个可关闭原生浏览实例，不修改原控制器树。只进入目录、返回和选择；不要使用复制/移动/删除/重命名等菜单。原生 Files 可能正常更新历史偏好；私有接口可能崩溃。请启动后尽快完成，关闭实验再导出。" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"启动真实原生实例" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [host dismissViewControllerAnimated:YES completion:^{ FPExperimentPresent(host); }];
        }]];
        [host presentViewController:a animated:YES completion:nil]; return;
    }
    FPLifecycleStop();
    FPViewer *viewer=[FPViewer new]; viewer.report=[FPExperimentReport() stringByAppendingFormat:@"\n%@",FPLifecycleReport()];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:viewer];
    [host presentViewController:nav animated:YES completion:nil];
}
@end

__attribute__((constructor)) static void FPStart(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.DocumentsApp"]) return;
        FPLifecycleStart(); // Arm synchronously before the application creates its natural graph.
        dispatch_async(dispatch_get_main_queue(),^{
            // Exact iOS 16.6 target: no unvalidated activation on other releases.
            NSOperatingSystemVersion v=NSProcessInfo.processInfo.operatingSystemVersion;
            if(v.majorVersion!=16 || v.minorVersion!=6) return;
            FPEntry *entry=[FPEntry shared];
            for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UISceneDidActivateNotification,UIWindowDidBecomeKeyNotification])
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){ [entry install]; }];
            [entry install];
        });
    }
}
