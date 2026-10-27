#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>

// No private messages, KVC, ivar values, filesystem enumeration or file operations.
static NSString *FPString(const char *s) { return s ? [NSString stringWithUTF8String:s] ?: @"?" : @"-"; }
static BOOL FPCandidate(NSString *n) {
    return [n hasPrefix:@"DOC"] || [n containsString:@"DocumentManager"] ||
      [n containsString:@"DocumentBrowser"] || [n containsString:@"FileProvider"];
}
@interface FPReport : NSObject
@property(nonatomic,strong) NSMapTable *ids;
@property(nonatomic,strong) NSMutableArray *objects;
@property(nonatomic,strong) NSMutableSet *classes;
@property(nonatomic,strong) NSMutableString *text;
- (NSString *)ref:(id)obj;
- (void)edge:(id)a label:(NSString *)label target:(id)b;
- (NSString *)capture:(UIWindow *)window;
@end
@implementation FPReport
- (instancetype)init {
    if ((self=[super init])) {
        _ids=[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory];
        _objects=[NSMutableArray array]; _classes=[NSMutableSet set]; _text=[NSMutableString string];
    } return self;
}
- (NSString *)ref:(id)obj {
    if (!obj) return @"nil";
    NSString *s=[self.ids objectForKey:obj];
    if (!s) {
        if (self.objects.count >= 400) return @"LIMIT";
        s=[NSString stringWithFormat:@"o%lu",(unsigned long)self.objects.count+1];
        [self.ids setObject:s forKey:obj]; [self.objects addObject:obj];
        NSString *n=FPString(class_getName(object_getClass(obj)));
        [self.classes addObject:n]; [self.text appendFormat:@"OBJECT %@ %@\n",s,n];
    } return s;
}
- (void)edge:(id)a label:(NSString *)label target:(id)b {
    NSString *x=[self ref:a], *y=[self ref:b];
    [self.text appendFormat:@"EDGE %@ %@ %@\n",x,label,y];
}
- (void)metadata:(Class)c {
    [self.text appendFormat:@"\nCLASS %@ SUPER %@\n",FPString(class_getName(c)),FPString(class_getName(class_getSuperclass(c)))];
    unsigned n=0;
    Ivar *iv=class_copyIvarList(c,&n);
    for(unsigned i=0;i<MIN(n,160u);i++) [self.text appendFormat:@" IVAR %@ TYPE %@ (value unread)\n",FPString(ivar_getName(iv[i])),FPString(ivar_getTypeEncoding(iv[i]))];
    if(n>160) [self.text appendString:@" IVARS_TRUNCATED\n"]; free(iv);
    objc_property_t *ps=class_copyPropertyList(c,&n);
    for(unsigned i=0;i<MIN(n,160u);i++) [self.text appendFormat:@" PROPERTY %@ %@\n",FPString(property_getName(ps[i])),FPString(property_getAttributes(ps[i]))];
    if(n>160) [self.text appendString:@" PROPERTIES_TRUNCATED\n"]; free(ps);
    for(int meta=0;meta<2;meta++) {
        Method *ms=class_copyMethodList(meta?object_getClass(c):c,&n);
        for(unsigned i=0;i<MIN(n,300u);i++) [self.text appendFormat:@" %@ %@ %@\n",meta?@"+":@"-",FPString(sel_getName(method_getName(ms[i]))),FPString(method_getTypeEncoding(ms[i]))];
        if(n>300) [self.text appendString:@" METHODS_TRUNCATED\n"]; free(ms);
    }
    Protocol *__unsafe_unretained *protos=class_copyProtocolList(c,&n);
    for(unsigned i=0;i<MIN(n,50u);i++) {
        [self.text appendFormat:@" PROTOCOL %@\n",FPString(protocol_getName(protos[i]))];
        for(int required=0;required<2;required++) for(int instance=0;instance<2;instance++) {
            unsigned count=0;
            objc_property_t *props=protocol_copyPropertyList2(protos[i],&count,required,instance);
            for(unsigned j=0;j<MIN(count,100u);j++) [self.text appendFormat:@"  PROPERTY required=%d instance=%d %@ %@\n",required,instance,FPString(property_getName(props[j])),FPString(property_getAttributes(props[j]))];
            if(count>100) [self.text appendString:@"  PROTOCOL_PROPERTIES_TRUNCATED\n"]; free(props);
        }
    }
    if(n>50) [self.text appendString:@" PROTOCOLS_TRUNCATED\n"]; free(protos);
}
- (NSString *)capture:(UIWindow *)window {
    NSAssert([NSThread isMainThread],@"UIKit main thread required");
    char build[128]={0}; size_t len=sizeof(build); sysctlbyname("kern.osversion",build,&len,NULL,0);
    [self.text appendFormat:@"Files Native Probe 0.1.0 / observation only\niOS %@ build %@\n",UIDevice.currentDevice.systemVersion,FPString(build)];
    [self.text appendString:@"S0 injection=observed; explicit capture=observed\nS1 UIKit identities=observed; private context identities=UNREAD/UNVERIFIED\nS2 factory/lifecycle contract=UNVERIFIED\nS3 second native controller=NOT CONSTRUCTED/NOT DISPLAYED\nS4 independent navigation/selection/history=NOT TESTED\nS5 cross-pane bridge=NOT TESTED; no file operations\nIDs are local to this capture; not comparable between captures.\nNo titles, item names, paths, URLs, bookmarks, provider accounts, content, pointers or scene persistent identifiers.\nMetadata is declaration only, not a value read or a factory contract. Swift-only members may be absent. Limits are explicit.\nPUBLIC_UIKIT_GRAPH\n"];
    [self ref:window];
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        [self ref:scene];
        [self.text appendFormat:@"SCENE %@ activation=%ld\n",[self ref:scene],(long)scene.activationState];
        for(UIWindow *w in ((UIWindowScene *)scene).windows) [self edge:scene label:@"windows" target:w];
    }
    for(NSUInteger i=0;i<self.objects.count && i<400;i++) {
        id o=self.objects[i];
        if ([o isKindOfClass:UIWindow.class]) {
            [self edge:o label:@"windowScene" target:((UIWindow *)o).windowScene];
            [self edge:o label:@"rootViewController" target:((UIWindow *)o).rootViewController];
        } else if ([o isKindOfClass:UIViewController.class]) {
            UIViewController *vc=o;
            [self edge:o label:@"parent" target:vc.parentViewController];
            [self edge:o label:@"presented" target:vc.presentedViewController];
            [self edge:o label:@"presenting" target:vc.presentingViewController];
            for(UIViewController *child in vc.childViewControllers) [self edge:o label:@"child" target:child];
            if ([vc isKindOfClass:UINavigationController.class]) {
                NSUInteger index=0;
                for(UIViewController *child in ((UINavigationController *)vc).viewControllers)
                    [self edge:o label:[NSString stringWithFormat:@"navigationStack[%lu]",(unsigned long)index++] target:child];
            }
            if ([vc isKindOfClass:UISplitViewController.class]) for(UIViewController *child in ((UISplitViewController *)vc).viewControllers) [self edge:o label:@"splitControllers" target:child];
            if ([vc isKindOfClass:UITabBarController.class]) for(UIViewController *child in ((UITabBarController *)vc).viewControllers) [self edge:o label:@"tabControllers" target:child];
        }
    }
    if(self.objects.count>=400) [self.text appendString:@"OBJECT_GRAPH_TRUNCATED\n"];
    unsigned count=0; Class *loaded=objc_copyClassList(&count);
    NSMutableArray *candidates=[NSMutableArray array];
    for(unsigned i=0;i<count;i++) { NSString *name=FPString(class_getName(loaded[i])); if(FPCandidate(name)) [candidates addObject:name]; }
    free(loaded); [candidates sortUsingSelector:@selector(compare:)];
    [self.text appendFormat:@"\nCANDIDATE_CLASS_COUNT %lu (loaded classes only)\n",(unsigned long)candidates.count];
    for(NSString *name in candidates) [self.text appendFormat:@"CANDIDATE %@\n",name];
    NSUInteger added=0;
    for(NSString *name in candidates) { if(added++>=220) break; [self.classes addObject:name]; }
    if(candidates.count>220) [self.text appendString:@"CANDIDATE_METADATA_TRUNCATED 220\n"];
    for(NSString *name in [[self.classes allObjects] sortedArrayUsingSelector:@selector(compare:)]) {
        if(self.text.length>1500000) { [self.text appendString:@"REPORT_METADATA_TRUNCATED\n"]; break; }
        Class c=objc_getClass(name.UTF8String); if(c) [self metadata:c];
    }
    return [self.text copy];
}
@end

@interface FPViewer : UIViewController
@property(nonatomic,copy) NSString *report;
@end
@implementation FPViewer
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"原生 Files 观察报告";
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
            [b setTitle:@"FP 诊断" forState:UIControlStateNormal];
            b.accessibilityLabel=@"生成原生 Files 只读诊断报告";
            b.backgroundColor=UIColor.secondarySystemBackgroundColor; b.layer.cornerRadius=10;
            b.translatesAutoresizingMaskIntoConstraints=NO;
            [b addTarget:self action:@selector(activate:) forControlEvents:UIControlEventTouchUpInside];
            [w addSubview:b]; [self.buttons setObject:b forKey:w];
            [NSLayoutConstraint activateConstraints:@[
                [b.trailingAnchor constraintEqualToAnchor:w.safeAreaLayoutGuide.trailingAnchor constant:-8],
                [b.bottomAnchor constraintEqualToAnchor:w.safeAreaLayoutGuide.bottomAnchor constant:-52],
                [b.widthAnchor constraintEqualToConstant:88], [b.heightAnchor constraintEqualToConstant:44]]];
        }
    }
}
- (void)activate:(UIButton *)button {
    UIWindow *w=button.window; if(!w) return;
    UIViewController *host=w.rootViewController;
    while(host.presentedViewController && !host.presentedViewController.isBeingDismissed) host=host.presentedViewController;
    // Never stack over an existing sheet, picker or action menu.
    if(host!=w.rootViewController || host.isBeingPresented || host.isBeingDismissed) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"只读观察探针" message:@"仅收集类/方法/签名及公开 UIKit 对象关系；不读取文件、私有属性值或账号。不会构造第二浏览器，也不会验证双栈成功。报告仅在内存中，关闭即释放；分享由你选择目标。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"生成报告" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // Dismissal completion ensures the probe alert is absent from the captured graph.
        [host dismissViewControllerAnimated:YES completion:^{
            if(!w.isKeyWindow || host.presentedViewController) return;
            FPReport *capture=[FPReport new];
            NSString *report=[capture capture:w];
            FPViewer *viewer=[FPViewer new]; viewer.report=report;
            UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:viewer];
            [host presentViewController:nav animated:YES completion:nil];
        }];
    }]];
    [host presentViewController:alert animated:YES completion:nil];
}
@end

__attribute__((constructor)) static void FPStart(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.DocumentsApp"]) return;
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
