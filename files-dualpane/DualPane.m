#import "DualPane.h"
#import <QuickLook/QuickLook.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#include <string.h>
// Only this typed init declaration is used for allocation; ARC preserves init-family ownership.
@protocol FPNativeFactory <NSObject>
- (instancetype)initWithConfiguration:(id)configuration sourceObserver:(id)observer;
@end
static BOOL ABI(Class c, NSString *name, const char *types) {
    Method m=class_getInstanceMethod(c,NSSelectorFromString(name)); if(!m) return NO;
    NSMethodSignature *a=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
    NSMethodSignature *b=[NSMethodSignature signatureWithObjCTypes:types];
    if(strcmp(a.methodReturnType,b.methodReturnType)||a.numberOfArguments!=b.numberOfArguments) return NO;
    for(NSUInteger i=0;i<a.numberOfArguments;i++) if(strcmp([a getArgumentTypeAtIndex:i],[b getArgumentTypeAtIndex:i])) return NO;
    return YES;
}
static id Get(id o, NSString *name) {
    if(!o || !ABI([o class],name,"@@:")) return nil;
    SEL s=NSSelectorFromString(name); return ((id(*)(id,SEL))[o methodForSelector:s])(o,s);
}
static void Set(id o, NSString *name, id value) {
    SEL s=NSSelectorFromString(name); ((void(*)(id,SEL,id))[o methodForSelector:s])(o,s,value);
}
static UIViewController *FindSplit(UIViewController *v, Class cls) {
    if([v isKindOfClass:cls]) return v;
    for(UIViewController *child in v.childViewControllers) { UIViewController *found=FindSplit(child,cls); if(found) return found; }
    return nil;
}
static BOOL RequiredMethods(Protocol *p, id adapter) {
    if(!p) return NO;
    unsigned count=0; struct objc_method_description *methods=protocol_copyMethodDescriptionList(p,YES,YES,&count);
    BOOL ok=YES;
    for(unsigned i=0;i<count;i++) if(!methods[i].types || !ABI([adapter class],NSStringFromSelector(methods[i].name),methods[i].types)) ok=NO;
    free(methods);
    Protocol *__unsafe_unretained *parents=protocol_copyProtocolList(p,&count);
    for(unsigned i=0;i<count;i++) if(!RequiredMethods(parents[i],adapter)) ok=NO;
    free(parents); return ok;
}

// Only our copied configuration namespaces use transient state; original Files falls through.
static NSMutableDictionary<NSString *, id> *paneStates;
static NSString *OwnState(id config) {
    id key=Get(config,@"stateIdentifier");
    return [key isKindOfClass:NSString.class] && [key hasPrefix:@"dev.filesdualpane.session."] ? key : nil;
}
static BOOL InstallStateIsolation(void) {
    static BOOL installed; if(installed) return YES;
    Class store=NSClassFromString(@"DOCUserInterfaceStateStore"), state=NSClassFromString(@"DOCUserInterfaceState");
    if(!state || !ABI(state,@"init","@@:") || !ABI(store,@"interfaceStateForConfiguration:","@@:@") || !ABI(store,@"updateInterfaceState:forConfiguration:","v@:@@")) return NO;
    for(NSString *name in @[@"_writeUserInterfaceStateToDefaultsForConfiguration:",@"_writeMostRecentUserInterfaceStateToDefaultsForConfiguration:"])
        if(!ABI(store,name,"v@:@")) return NO;
    paneStates=[NSMutableDictionary new];
    SEL read=NSSelectorFromString(@"interfaceStateForConfiguration:"); Method rm=class_getInstanceMethod(store,read); IMP ro=method_getImplementation(rm);
    class_replaceMethod(store,read,imp_implementationWithBlock(^id(id self,id config){
        NSString *key=OwnState(config); if(!key) return ((id(*)(id,SEL,id))ro)(self,read,config);
        @synchronized(paneStates) { id value=paneStates[key]; return value ?: [[state alloc] init]; }
    }),method_getTypeEncoding(rm));
    SEL update=NSSelectorFromString(@"updateInterfaceState:forConfiguration:"); Method um=class_getInstanceMethod(store,update); IMP uo=method_getImplementation(um);
    class_replaceMethod(store,update,imp_implementationWithBlock(^(id self,id value,id config){
        NSString *key=OwnState(config);
        if(!key) { ((void(*)(id,SEL,id,id))uo)(self,update,value,config); return; }
        @synchronized(paneStates) { if(paneStates[key] && value) paneStates[key]=value; }
    }),method_getTypeEncoding(um));
    for(NSString *name in @[@"_writeUserInterfaceStateToDefaultsForConfiguration:",@"_writeMostRecentUserInterfaceStateToDefaultsForConfiguration:"]) {
        SEL sel=NSSelectorFromString(name); Method m=class_getInstanceMethod(store,sel); IMP old=method_getImplementation(m);
        class_replaceMethod(store,sel,imp_implementationWithBlock(^(id self,id config){
            if(!OwnState(config)) ((void(*)(id,SEL,id))old)(self,sel,config);
        }),method_getTypeEncoding(m));
    }
    installed=YES; return YES;
}
@interface FPBrowserPane : UIViewController <UIDocumentBrowserViewControllerDelegate>
@property(nonatomic,strong) UIViewController *nativeSplit;
@property(nonatomic,strong) id configuration;
@property(nonatomic,strong) id sourceObserver;
@property(nonatomic) BOOL initialListStarted;
@property(nonatomic) NSUInteger listAttempts;
@property(nonatomic) NSUInteger homeIndex;
@property(nonatomic) BOOL homeAttempted;
- (void)applyInitialList;
- (void)previewURLs:(NSArray<NSURL *> *)urls;
- (void)unsupported;
- (void)close;
@end
@interface FPDualContainer : UIViewController
@property(nonatomic,copy) NSArray<FPBrowserPane *> *panes;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) UISegmentedControl *mode;
@property(nonatomic) BOOL closing;
@property(nonatomic) BOOL userSelectedMode;
@property(nonatomic) BOOL transferBusy;
@property(nonatomic,strong) UILabel *status;
- (void)close;
@end
BOOL FPDualPaneContains(UIViewController *v) {
    for(;v;v=v.parentViewController) if([v isKindOfClass:FPDualContainer.class]) return YES;
    return NO;
}
static BOOL InExperiment(id v) {
    if(![v isKindOfClass:UIViewController.class]) return NO;
    for(;v;v=[v parentViewController]) if([v isKindOfClass:FPBrowserPane.class]) return YES;
    return NO;
}
#include "ScopedPreview.inc"
#include "FileCore.inc"
#include "CrossPane.inc"
@implementation FPBrowserPane
- (void)dealloc {
    NSString *key=OwnState(_configuration);
    @synchronized(paneStates) { if(key) [paneStates removeObjectForKey:key]; }
}
- (void)viewDidLoad {
    [super viewDidLoad];
    UIViewController *child=self.nativeSplit; [self addChildViewController:child];
    child.view.frame=self.view.bounds; child.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:child.view]; [child didMoveToParentViewController:self];
    UINavigationController *navigation=Get(FPFull(self),@"internalNavigationController");
    if([navigation isKindOfClass:UINavigationController.class]) navigation.navigationBar.prefersLargeTitles=NO;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(!self.initialListStarted) { self.initialListStarted=YES; [self applyInitialList]; }
}
- (void)applyInitialList {
    if(!self.parentViewController || !self.nativeSplit) return;
    id full=Get(self.nativeSplit,@"fullDocumentManagerViewController");
    id current=Get(full,@"currentItemCollectionViewController");
    if(InExperiment(current) && ABI([full class],@"performViewAsList:","v@:@")) {
        // Native semantic action supplies its own enum. Never guess setDisplayMode: values.
        SEL sel=NSSelectorFromString(@"performViewAsList:");
        ((void(*)(id,SEL,id))[full methodForSelector:sel])(full,sel,nil);
        if(ABI([current class],@"accessibilityIsInListMode","B@:")) {
            SEL check=NSSelectorFromString(@"accessibilityIsInListMode");
            if(((BOOL(*)(id,SEL))[current methodForSelector:check])(current,check)) {
                if(!self.homeAttempted) { self.homeAttempted=YES; FPRestoreHome(self); }
                return;
            }
        }
        // A missing/unconfirmed implementation leaves native layout and a visible fallback.
        self.parentViewController.navigationItem.prompt=@"列表未确认：请用本栏原生菜单选择列表";
        return;
    }
    if(++self.listAttempts>=10) { self.parentViewController.navigationItem.prompt=@"列表不可用：保留原生布局"; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/4),dispatch_get_main_queue(),^{ [self applyInitialList]; });
}
- (void)previewURLs:(NSArray<NSURL *> *)urls {
    if(self.presentedViewController || ![urls isKindOfClass:NSArray.class] || !urls.count) return;
    NSMutableArray *valid=[NSMutableArray new], *scopes=[NSMutableArray new];
    for(id value in urls) {
        if(![value isKindOfClass:NSURL.class] || ![value isFileURL]) continue;
        if([value startAccessingSecurityScopedResource]) [scopes addObject:value];
        [valid addObject:value];
    }
    if(!valid.count) return;
    FPScopedPreview *preview=[FPScopedPreview new]; preview.urls=valid; preview.scopes=scopes; preview.dataSource=preview;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *failure=CheckPreviewURLs(valid);
        dispatch_async(dispatch_get_main_queue(),^{
            if(!self.parentViewController || self.presentedViewController) return;
            if(failure) {
                UIAlertController *a=[UIAlertController alertControllerWithTitle:@"无法预览" message:failure.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"返回" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            } else [self presentViewController:preview animated:YES completion:nil];
        });
    });
}
- (void)unsupported {
    if(self.presentedViewController || self.isBeingDismissed) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"不支持新建文档" message:@"本版可新建文件夹，不提供文本编辑或文档模板。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"返回" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)documentBrowser:(UIDocumentBrowserViewController *)b didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls { [self previewURLs:urls]; }
- (void)documentBrowser:(UIDocumentBrowserViewController *)b didPickDocumentURLs:(NSArray<NSURL *> *)urls { [self previewURLs:urls]; }
- (void)documentBrowser:(id)b didPickImportedURLs:(id)urls { [self previewURLs:urls]; }
- (void)documentBrowser:(id)b commitPreviewOfDocumentAtURL:(id)url { if([url isKindOfClass:NSURL.class]) [self previewURLs:@[url]]; }
- (void)documentBrowser:(UIDocumentBrowserViewController *)b didRequestDocumentCreationWithHandler:(void (^)(NSURL *,UIDocumentBrowserImportMode))handler { handler(nil,UIDocumentBrowserImportModeNone); [self unsupported]; }
- (void)documentManagerWasCancelled:(id)manager { [self close]; }
- (void)close { for(UIViewController *p=self.parentViewController;p;p=p.parentViewController) if([p isKindOfClass:FPDualContainer.class]) { [(FPDualContainer *)p close]; return; } }
@end
#include "NativeActions.inc"
static NSString *Preflight(UIViewController *host, FPBrowserPane *adapter, id *outConfig, id *outObserver, UIViewController **outOriginal) {
    char build[64]={0}; size_t length=sizeof(build); sysctlbyname("kern.osversion",build,&length,NULL,0);
    if(strcmp(build,"20G75") || !NSThread.isMainThread) return @"requires main thread and iOS build 20G75";
    Class cls=NSClassFromString(@"DOCSplitBrowserViewController"), full=NSClassFromString(@"DOCFullDocumentManagerViewController");
    if(!cls || ![cls isSubclassOfClass:UISplitViewController.class] || ![full isSubclassOfClass:UIDocumentBrowserViewController.class]) return @"native class hierarchy unavailable";
    if(!ABI(cls,@"initWithConfiguration:sourceObserver:","@@:@@")) return @"Split initializer ABI mismatch";
    for(NSString *key in @[@"configuration",@"sourceObserver",@"fullDocumentManagerViewController"])
        if(!ABI(cls,key,"@@:")) return [@"Split getter unavailable: " stringByAppendingString:key];
    for(NSString *key in @[@"configuration",@"hierarchyController",@"documentManager",@"dataSource",@"actionManager",@"internalNavigationController"])
        if(!ABI(full,key,"@@:")) return [@"Full getter unavailable: " stringByAppendingString:key];
    if(!ABI(full,@"setDelegate:","v@:@") || !ABI(full,@"fullDocumentManagerDelegate","@@:")) return @"Full external delegate binding unavailable";
    if(!ABI(NSClassFromString(@"Files.DOCDocumentManager"),@"uiBrowserDelegate","@@:")) return @"document manager delegate verification unavailable";
    if(!RequiredMethods(@protocol(UIDocumentBrowserViewControllerDelegate),adapter)) return @"external browser protocol has unimplemented required methods";
    // Internal Split/sidebar/hierarchy protocols remain on factory-created native delegates.
    UIViewController *original=FindSplit(host,cls); if(!original) return @"no existing Split in original child tree";
    id config=Get(original,@"configuration"), observer=Get(original,@"sourceObserver");
    if(!config || !observer) return @"existing Split configuration/sourceObserver missing";
    if(![config conformsToProtocol:@protocol(NSCopying)] || !ABI([config class],@"copyWithZone:","@@:^{_NSZone=}")) return @"configuration copy ABI unavailable";
    for(NSString *key in @[@"stateIdentifier",@"sceneIdentifier"])
        if(!ABI([config class],key,"@@:")) return [@"configuration getter unavailable: " stringByAppendingString:key];
    if(!ABI([config class],@"setStateIdentifier:","v@:@") || !ABI([config class],@"setCollectionSupportsDragAndDrop:","v@:B")) return @"configuration namespace/drag restriction ABI unavailable";
    id copy=[config copy]; if(!copy || copy==config || [copy class]!=[config class]) return @"configuration did not return independent same-class copy";
    id scene=Get(config,@"sceneIdentifier"), copiedScene=Get(copy,@"sceneIdentifier");
    if(!scene || ![scene isEqual:copiedScene]) return @"real scene identifier unavailable or changed by copy";
    NSString *state=[@"dev.filesdualpane.session." stringByAppendingString:NSUUID.UUID.UUIDString];
    Set(copy,@"setStateIdentifier:",state);
    for(NSString *name in @[@"setCollectionSupportsDragAndDrop:",@"setSaveLastVisitedLocation:",@"setRestoreLastVisitedLocation:"]) {
        if(!ABI([copy class],name,"v@:B")) return @"temporary configuration flag ABI unavailable";
        SEL flag=NSSelectorFromString(name);
        ((void(*)(id,SEL,BOOL))[copy methodForSelector:flag])(copy,flag,NO);
    }
    if(![Get(copy,@"stateIdentifier") isEqual:state] || [Get(config,@"stateIdentifier") isEqual:state]) return @"namespace isolation failed";
    *outConfig=copy; *outObserver=observer; *outOriginal=original; return nil;
}

@implementation FPDualContainer
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"双窗格 · 0.7.0"; self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.mode=[[UISegmentedControl alloc] initWithItems:@[@"并排",@"左栏",@"右栏"]];
    self.mode.selectedSegmentIndex=0; // Both panes, including narrow phones.
    [self.mode addTarget:self action:@selector(changeMode) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView=self.mode;
    self.stack=[[UIStackView alloc] init]; self.stack.axis=UILayoutConstraintAxisHorizontal; self.stack.distribution=UIStackViewDistributionFillEqually;
    self.stack.spacing=1; self.stack.backgroundColor=UIColor.separatorColor; self.stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:self.stack];
    self.status=[UILabel new]; self.status.translatesAutoresizingMaskIntoConstraints=NO;
    self.status.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption2]; self.status.adjustsFontForContentSizeCategory=YES;
    self.status.numberOfLines=2; self.status.text=@"下方跨栏/首页 · 点状态查看完整结果";
    self.status.userInteractionEnabled=YES; self.status.accessibilityTraits|=UIAccessibilityTraitButton;
    [self.status addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showStatus)]];
    [self.view addSubview:self.status];
    [NSLayoutConstraint activateConstraints:@[[self.status.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:8],[self.status.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-8],[self.status.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];
    UIBarButtonItem *left=[[UIBarButtonItem alloc] initWithTitle:@"左栏 ⇄ / 首页" menu:FPPaneMenu(self,0)];
    UIBarButtonItem *right=[[UIBarButtonItem alloc] initWithTitle:@"右栏 ⇄ / 首页" menu:FPPaneMenu(self,1)];
    self.toolbarItems=@[left,[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],right];
    [self.navigationController setToolbarHidden:NO animated:NO];
    [NSLayoutConstraint activateConstraints:@[[self.stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[self.stack.bottomAnchor constraintEqualToAnchor:self.status.topAnchor],[self.stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],[self.stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor]]];
    for(FPBrowserPane *pane in self.panes) {
        [self addChildViewController:pane];
        [self.stack addArrangedSubview:pane.view]; [pane didMoveToParentViewController:self];
    }
    [self applyMode];
}
- (void)showStatus {
    if(self.presentedViewController) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"操作结果" message:self.status.text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"返回" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)changeMode { self.userSelectedMode=YES; [self applyMode]; }
- (void)applyMode {
    NSInteger mode=self.mode.selectedSegmentIndex;
    for(NSUInteger i=0;i<self.panes.count;i++) self.stack.arrangedSubviews[i].hidden=(mode!=0 && mode!=(NSInteger)i+1);
    [self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    for(FPBrowserPane *pane in self.panes) {
        // Public size classes, not guessed private sidebar enum values.
        UIUserInterfaceSizeClass size=pane.view.bounds.size.width<600 ? UIUserInterfaceSizeClassCompact : UIUserInterfaceSizeClassRegular;
        if(pane.traitCollection.horizontalSizeClass!=size) [self setOverrideTraitCollection:[UITraitCollection traitCollectionWithHorizontalSizeClass:size] forChildViewController:pane];
    }
}
- (void)close {
    if(self.closing) return;
    if(self.transferBusy) { FPNotice(self,@"文件任务进行中，请等待明确结果再关闭。"); return; }
    self.closing=YES;
    [self dismissViewControllerAnimated:YES completion:^{
        for(FPBrowserPane *pane in self.panes) {
            UIViewController *split=pane.nativeSplit;
            [split willMoveToParentViewController:nil]; [split.view removeFromSuperview]; [split removeFromParentViewController];
            pane.nativeSplit=nil; pane.sourceObserver=nil;
            NSString *key=OwnState(pane.configuration); @synchronized(paneStates) { if(key) [paneStates removeObjectForKey:key]; }
            pane.configuration=nil;
            [pane willMoveToParentViewController:nil]; [pane.view removeFromSuperview]; [pane removeFromParentViewController];
        }
        self.panes=nil;
        // Never stop the shared observer or remove tokens owned by native controllers.
    }];
}
@end
static void ShowFailure(UIViewController *host, NSString *reason) {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"无法打开双窗格" message:reason preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"返回 Files" style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:a animated:YES completion:nil];
}
void FPDualPanePresent(UIViewController *host) {
    if(!NSThread.isMainThread || host.presentedViewController || host.isBeingDismissed) return;
    NSMutableArray<FPBrowserPane *> *panes=[NSMutableArray new];
    NSMutableSet *identities=[NSMutableSet new]; NSString *failure=nil;
    for(NSUInteger index=0;index<2;index++) {
        FPBrowserPane *pane=[FPBrowserPane new]; pane.homeIndex=index; id config=nil,observer=nil; UIViewController *original=nil;
        failure=Preflight(host,pane,&config,&observer,&original); if(failure) break;
        if(!InstallStateIsolation()) { failure=@"此系统的临时界面状态接口不兼容；未创建浏览器。"; break; }
        pane.configuration=config; pane.sourceObserver=observer; [panes addObject:pane];
        @synchronized(paneStates) { paneStates[OwnState(config)]=[[NSClassFromString(@"DOCUserInterfaceState") alloc] init]; }
        UIViewController *split=(UIViewController *)[(id<FPNativeFactory>)[NSClassFromString(@"DOCSplitBrowserViewController") alloc] initWithConfiguration:config sourceObserver:observer];
        pane.nativeSplit=split;
        id full=Get(split,@"fullDocumentManagerViewController"), oldFull=Get(original,@"fullDocumentManagerViewController");
        if(!split || !full || split==original || full==oldFull || split.parentViewController) { failure=@"原生工厂未返回独立浏览器。"; break; }
        if(![Get(Get(full,@"configuration"),@"stateIdentifier") isEqual:OwnState(config)] || ![Get(Get(split,@"configuration"),@"stateIdentifier") isEqual:OwnState(config)]) { failure=@"工厂未保留临时状态命名空间。"; break; }
        NSMutableArray *owned=[NSMutableArray arrayWithObjects:split,full,config,nil];
        for(NSString *key in @[@"hierarchyController",@"documentManager",@"dataSource",@"actionManager",@"internalNavigationController"]) {
            id value=Get(full,key);
            if(!value || value==Get(oldFull,key)) { failure=[@"原生依赖未隔离：" stringByAppendingString:key]; break; }
            [owned addObject:value];
        }
        if(failure) break;
        for(id value in owned) {
            NSValue *identity=[NSValue valueWithPointer:(__bridge const void *)value];
            if([identities containsObject:identity]) { failure=@"左右栏原生依赖发生共享，已取消打开。"; break; }
            [identities addObject:identity];
        }
        if(failure) break;
        if(Get(full,@"fullDocumentManagerDelegate")!=split) { failure=@"原生内部委托不匹配。"; break; }
        ((UIDocumentBrowserViewController *)full).delegate=pane;
        ((UIDocumentBrowserViewController *)full).allowsDocumentCreation=NO;
        if(((UIDocumentBrowserViewController *)full).delegate!=pane || Get(Get(full,@"documentManager"),@"uiBrowserDelegate")!=pane) { failure=@"外部委托未隔离。"; break; }
    }
    if(failure) {
        for(FPBrowserPane *pane in panes) {
            pane.nativeSplit=nil; pane.sourceObserver=nil;
            NSString *key=OwnState(pane.configuration); @synchronized(paneStates) { if(key) [paneStates removeObjectForKey:key]; }
            pane.configuration=nil;
        }
        ShowFailure(host,failure); return;
    }
    static dispatch_once_t once; dispatch_once(&once,^{ InstallNativeActions(); });
    FPDualContainer *container=[FPDualContainer new]; container.panes=panes;
    UINavigationController *modal=[[UINavigationController alloc] initWithRootViewController:container];
    modal.modalPresentationStyle=UIModalPresentationFullScreen; modal.modalInPresentation=YES;
    [host presentViewController:modal animated:YES completion:nil];
}
