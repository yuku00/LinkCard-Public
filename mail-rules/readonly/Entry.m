#import "Graph.h"
#import <sys/sysctl.h>

@interface ROButton : UIButton @end
@implementation ROButton @end
@interface ROViewer : UIViewController
@property(nonatomic,copy) NSString *report;
@end
@implementation ROViewer
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"只读采集0.5.2";
    UITextView *text=[[UITextView alloc] initWithFrame:self.view.bounds];
    text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    text.editable=NO; text.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    text.text=self.report; [self.view addSubview:text];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
}
- (void)close { [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }
- (void)share {
    if(self.presentedViewController) return;
    UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:@[self.report] applicationActivities:nil];
    sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}
@end

@interface ROEntry : NSObject
@property(nonatomic,strong) ROSession *session;
@property(nonatomic,strong) NSMapTable *buttons;
@property(nonatomic,copy) NSString *observerStatus;
@property(nonatomic) BOOL pending;
@property(nonatomic) BOOL panelOpen;
- (void)install;
- (void)tap:(ROButton *)button;
@end
@implementation ROEntry
- (instancetype)init {
    if((self=[super init])) {
        _session=[ROSession new]; _buttons=[NSMapTable weakToWeakObjectsMapTable];
        _observerStatus=@"not-installed; manual stages available";
    } return self;
}
- (UIWindow *)window {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if(ROIsKind(scene,UIWindowScene.class) && scene.activationState==UISceneActivationStateForegroundActive)
            for(UIWindow *w in ((UIWindowScene *)scene).windows)
                if(w.isKeyWindow && w.windowLevel==UIWindowLevelNormal) return w;
    return nil;
}
- (void)capture:(NSString *)label automatic:(BOOL)automatic {
    if(!self.session.active || self.session.paused || self.panelOpen) return;
    UIWindow *window=[self window]; if(!window) return;
    @try { [self.session record:ROGraph(window,self.session) label:label automatic:automatic]; }
    @catch(NSException *exception) { (void)exception; /* Never include error strings. */ }
    ROButton *button=[self.buttons objectForKey:window];
    button.accessibilityHint=[self.session.pageRole isEqual:@"mailbox-picker-not-message-list"] ? @"当前是邮箱选择器，不是邮件列表。请取消后进入实际收件箱。" : @"仅匿名界面结构；点此标记阶段或停止分享。";
}
- (void)eventOwner:(id)owner event:(id)event {
    if(!NSThread.isMainThread || !self.session.active || self.session.paused || self.panelOpen) return;
    [self.session eventOwner:owner argument:event];
    if(self.pending) return;
    self.pending=YES; NSUInteger generation=self.session.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        self.pending=NO;
        if(self.session.generation==generation) [self capture:@"natural-UI-event" automatic:YES];
    });
}
- (void)afterPanel:(UIAlertController *)panel perform:(dispatch_block_t)block {
    // Dismiss ONLY our own alert, never the Mail host or its navigation container.
    [panel dismissViewControllerAnimated:YES completion:^{
        self.panelOpen=NO; [self.session resume]; block();
    }];
}
- (void)viewReport:(UIWindow *)window {
    UIViewController *host=ROVisibleHost(window);
    if(!host || host.isBeingDismissed || host.isBeingPresented) return;
    NSMutableDictionary *document=[[self.session document:self.observerStatus] mutableCopy];
    document[@"runtimeGate"]=@"com.apple.mobilemail / 20G75";
    NSData *data=[NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingSortedKeys error:NULL];
    if(data.length>1536*1024) {
        document[@"metadata"]=@{@"omitted":@YES,@"reason":@"serialized-report-budget"};
        data=[NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingSortedKeys error:NULL];
    }
    if(data.length>1536*1024) {
        document[@"stages"]=@[]; document[@"reportTruncated"]=@"stage bytes exceeded 1.5 MiB; omitted, not claimed collected";
        data=[NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingSortedKeys error:NULL];
    }
    ROViewer *viewer=[ROViewer new]; viewer.report=data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:@"Report serialization failed (no details read).";
    UINavigationController *container=[[UINavigationController alloc] initWithRootViewController:viewer];
    [host presentViewController:container animated:YES completion:nil];
}
- (void)tap:(ROButton *)button {
    if(self.panelOpen) return;
    UIWindow *window=button.window; UIViewController *host=ROVisibleHost(window);
    if(!host || host.isBeingDismissed || host.isBeingPresented) return;
    // Capture the native page before our alert appears; no business action is performed.
    if(self.session.active) [self capture:@"before-probe-panel" automatic:YES];
    self.panelOpen=YES; [self.session pause];
    NSString *role=self.session.pageRole;
    NSString *hint=[role isEqual:@"mailbox-picker-not-message-list"] ? @"当前为 MailboxPicker 邮箱选择器，不是邮件列表；请取消选择器，进入实际收件箱后标记。" : @"列表候选不等于已核验收件箱；请亲自进入实际收件箱。";
    NSString *message=[NSString stringWithFormat:@"%@\n当前类别：%@\n已留存 %lu 阶段。只读采集 UI 关系与接口类型，不读邮件值。\n自然操作首页→收件箱→选择/原生筛选→取消/刷新；每个关键页面点此标记。若查看移动/新建菜单，只打开后取消，不提交。本探针不拦截你自己的真实操作。\n仅内存记录，无自动上传。",hint,role,(unsigned long)self.session.stageCount];
    UIAlertController *panel=[UIAlertController alertControllerWithTitle:@"只读采集0.5.2" message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakPanel=panel;
    if(!self.session.active) {
        [panel addAction:[UIAlertAction actionWithTitle:@"开始只读采集" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            [self afterPanel:weakPanel perform:^{ [self.session start]; [self capture:@"start-native-page" automatic:NO]; }];
        }]];
        if(self.session.stageCount) [panel addAction:[UIAlertAction actionWithTitle:@"查看上轮报告 / 分享" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            [self afterPanel:weakPanel perform:^{ [self viewReport:window]; }];
        }]];
    } else {
        for(NSString *label in @[@"首页",@"实际收件箱",@"选择",@"原生筛选",@"取消后",@"自然刷新后"]) {
            [panel addAction:[UIAlertAction actionWithTitle:[@"标记：" stringByAppendingString:label] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
                [self afterPanel:weakPanel perform:^{ [self capture:label automatic:NO]; }];
            }]];
        }
        [panel addAction:[UIAlertAction actionWithTitle:@"停止分享" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            [self afterPanel:weakPanel perform:^{ [self capture:@"stop-native-page" automatic:NO]; [self.session stop]; [self viewReport:window]; }];
        }]];
    }
    [panel addAction:[UIAlertAction actionWithTitle:@"清空采集内存" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        [self afterPanel:weakPanel perform:^{ [self.session clear]; }];
    }]];
    [panel addAction:[UIAlertAction actionWithTitle:@"返回 Mail" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){
        [self afterPanel:weakPanel perform:^{}];
    }]];
    [host presentViewController:panel animated:YES completion:nil];
}
- (void)install {
    UIWindow *window=[self window]; if(!window || !window.rootViewController) return;
    if([self.buttons objectForKey:window]) return;
    ROButton *button=[ROButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"只读采集0.5.2" forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont systemFontOfSize:12];
    button.accessibilityLabel=@"只读采集0.5.2；默认关闭，点此开始";
    button.backgroundColor=UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius=6; button.translatesAutoresizingMaskIntoConstraints=NO;
    [button addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:button]; [self.buttons setObject:button forKey:window];
    [NSLayoutConstraint activateConstraints:@[[button.trailingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.trailingAnchor constant:-8],[button.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:48],[button.widthAnchor constraintEqualToConstant:108],[button.heightAnchor constraintEqualToConstant:32]]];
}
@end

__attribute__((constructor)) static void ROStart(void) {
    @autoreleasepool {
        char build[64]={0}; size_t size=sizeof(build);
        if(sysctlbyname("kern.osversion",build,&size,NULL,0)!=0 || !size || size>=sizeof(build)) return;
        if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.mobilemail"] || strcmp(build,"20G75")) return;
        dispatch_async(dispatch_get_main_queue(),^{
            static ROEntry *entry; entry=[ROEntry new];
            BOOL installed=ROInstallObserver(object_getClass(UIApplication.sharedApplication),^(id owner,id event){ [entry eventOwner:owner event:event]; });
            entry.observerStatus=installed?@"public UIApplication sendEvent: only; exact ABI v24@0:8@16; original once; no event values":@"ABI unavailable: no hook; explicit stage snapshots only";
            for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UISceneDidActivateNotification,UIWindowDidBecomeKeyNotification])
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){ [entry install]; }];
            [entry install];
        });
    }
}
