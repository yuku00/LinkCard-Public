#import "NativeExperiment.h"
#import "LifecycleTrace.h"
#import <objc/runtime.h>
#import <sys/sysctl.h>
#include <string.h>

// Only this typed init declaration is used for allocation; ARC preserves init-family ownership.
@protocol FPNativeFactory <NSObject>
- (instancetype)initWithConfiguration:(id)configuration sourceObserver:(id)observer;
@end
static BOOL attempted, shown, closing;
static unsigned selections, navigationUpdates, blockedOpens;
static NSMutableArray<NSString *> *states;
static __weak UIViewController *observedSplit;
static NSPointerArray *originalControllers, *originalParents, *watched;
static __weak UIViewController *originalRoot;
static __weak UIWindow *originalWindow;
static NSArray<NSString *> *watchNames;
static void Note(NSString *s) { if(!states) states=[NSMutableArray new]; if(states.count<64) [states addObject:s]; }
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
static void Snapshot(UIViewController *vc) {
    [originalControllers addPointer:(__bridge void *)vc];
    [originalParents addPointer:(__bridge void *)vc.parentViewController];
    for(UIViewController *child in vc.childViewControllers) Snapshot(child);
}
static BOOL GraphPreserved(void) {
    if(!originalRoot || originalWindow.rootViewController!=originalRoot) return NO;
    for(NSUInteger i=0;i<originalControllers.count;i++) {
        UIViewController *v=(__bridge id)[originalControllers pointerAtIndex:i];
        UIViewController *p=(__bridge id)[originalParents pointerAtIndex:i];
        if(!v || v.parentViewController!=p) return NO;
    }
    return YES;
}
static UIViewController *FindSplit(UIViewController *v, Class cls) {
    if([v isKindOfClass:cls]) return v;
    for(UIViewController *child in v.childViewControllers) { UIViewController *found=FindSplit(child,cls); if(found) return found; }
    return nil;
}
static BOOL InExperiment(id object) {
    if(!shown || closing || ![object isKindOfClass:UIViewController.class]) return NO;
    for(UIViewController *v=object; v; v=v.parentViewController) if(v==observedSplit) return YES;
    return NO;
}
static void Observe(id object, const char *selector) {
    if(!InExperiment(object)) return;
    if(!strcmp(selector,"collectionView:didSelectItemAtIndexPath:")) selections++;
    if(!strcmp(selector,"fullDocumentManagerViewController:didUpdateHierarchy:displayedRootLocation:")) navigationUpdates++;
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
@interface FPExperimentContainer : UIViewController <UIDocumentBrowserViewControllerDelegate>
@property(nonatomic,strong) UIViewController *nativeSplit;
@property(nonatomic,strong) id sourceObserver;
@property(nonatomic,strong) id configuration;
- (void)close;
- (void)unsupported;
@end
@implementation FPExperimentContainer
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.title=@"原生新增实例 · 0.3.0";
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"关闭实验" style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    UILabel *warning=[UILabel new]; warning.text=@"仅浏览/选择/返回；不要使用菜单复制、移动、删除或重命名。";
    warning.numberOfLines=0; warning.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    warning.textColor=UIColor.secondaryLabelColor; warning.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:warning];
    UIViewController *child=self.nativeSplit; [self addChildViewController:child];
    child.view.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:child.view];
    [NSLayoutConstraint activateConstraints:@[
        [warning.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
        [warning.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [warning.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [child.view.topAnchor constraintEqualToAnchor:warning.bottomAnchor constant:4],
        [child.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [child.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [child.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    [child didMoveToParentViewController:self];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(!shown) { shown=YES; Note(@"presented=yes; automatic UIKit appearance forwarding"); }
}
- (void)unsupported {
    blockedOpens++;
    if(closing || self.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"实验不支持打开或预览文档" message:@"此次仅验证目录浏览、选择与返回；没有转发给原 Files 宿主。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"返回浏览" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)documentBrowser:(UIDocumentBrowserViewController *)browser didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls { [self unsupported]; }
- (void)documentBrowser:(UIDocumentBrowserViewController *)browser didPickDocumentURLs:(NSArray<NSURL *> *)urls { [self unsupported]; }
- (void)documentBrowser:(id)browser didPickImportedURLs:(id)urls { [self unsupported]; }
- (void)documentBrowser:(id)browser commitPreviewOfDocumentAtURL:(id)url { [self unsupported]; }
- (void)documentBrowser:(UIDocumentBrowserViewController *)browser didRequestDocumentCreationWithHandler:(void (^)(NSURL *,UIDocumentBrowserImportMode))handler {
    handler(nil,UIDocumentBrowserImportModeNone); [self unsupported];
}
- (void)documentManagerWasCancelled:(id)manager { [self close]; }
- (void)close {
    if(closing) return; closing=YES;
    Note([NSString stringWithFormat:@"close requested; originalGraphPreserved=%d",GraphPreserved()]);
    [self dismissViewControllerAnimated:YES completion:^{
        // Dismissal has already forwarded disappearance; then detach only our child.
        UIViewController *child=self.nativeSplit;
        [child willMoveToParentViewController:nil]; [child.view removeFromSuperview]; [child removeFromParentViewController];
        Note([NSString stringWithFormat:@"close detached=%d",child.parentViewController==nil]);
        self.nativeSplit=nil; self.configuration=nil; self.sourceObserver=nil;
        Note(@"owned strong references cleared; shared observer not stopped; no foreign tokens removed");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            Note([NSString stringWithFormat:@"post-close originalGraphPreserved=%d",GraphPreserved()]);
            for(NSUInteger i=0;i<watched.count;i++) Note([NSString stringWithFormat:@"release %@ stillAlive=%d",watchNames[i],[watched pointerAtIndex:i]!=NULL]);
            Note(@"stillAlive is a weak snapshot, not a leak diagnosis; use the floating button to export");
        });
    }];
}
@end

static void BlockPreview(id object) {
    for(UIViewController *v=object; v; v=v.parentViewController)
        if([v isKindOfClass:FPExperimentContainer.class]) { [(FPExperimentContainer *)v unsupported]; return; }
}
static BOOL PreviewABI(void) {
    Class c=NSClassFromString(@"Files.DOCItemCollectionViewController");
    return ABI(c,@"performPreview:","v@:@") &&
        ABI(c,@"contextMenuInteraction:configurationForMenuAtLocation:","@@:@{CGPoint=dd}") &&
        ABI(c,@"collectionView:contextMenuConfigurationForItemsAtIndexPaths:point:","@@:@@{CGPoint=dd}") &&
        ABI(c,@"collectionView:contextMenuConfigurationForItemAtIndexPath:point:","@@:@@{CGPoint=dd}");
}
static void InstallPreviewGuards(void) {
    // Scope every guard to descendants of our new Split; original graph is transparent pass-through.
    Class c=NSClassFromString(@"Files.DOCItemCollectionViewController");
    SEL p=NSSelectorFromString(@"performPreview:"); Method pm=class_getInstanceMethod(c,p); IMP po=method_getImplementation(pm);
    class_replaceMethod(c,p,imp_implementationWithBlock(^(id s,id sender){ if(InExperiment(s)) { BlockPreview(s); return; } ((void(*)(id,SEL,id))po)(s,p,sender); }),method_getTypeEncoding(pm));
    SEL menu=NSSelectorFromString(@"contextMenuInteraction:configurationForMenuAtLocation:"); Method mm=class_getInstanceMethod(c,menu); IMP mo=method_getImplementation(mm);
    class_replaceMethod(c,menu,imp_implementationWithBlock(^id(id s,id interaction,CGPoint point){ if(InExperiment(s)) { BlockPreview(s); return nil; } return ((id(*)(id,SEL,id,CGPoint))mo)(s,menu,interaction,point); }),method_getTypeEncoding(mm));
    for(NSString *name in @[@"collectionView:contextMenuConfigurationForItemsAtIndexPaths:point:",@"collectionView:contextMenuConfigurationForItemAtIndexPath:point:"]) {
        SEL sel=NSSelectorFromString(name); Method m=class_getInstanceMethod(c,sel); IMP original=method_getImplementation(m);
        class_replaceMethod(c,sel,imp_implementationWithBlock(^id(id s,id collection,id index,CGPoint point){ if(InExperiment(s)) { BlockPreview(s); return nil; } return ((id(*)(id,SEL,id,id,CGPoint))original)(s,sel,collection,index,point); }),method_getTypeEncoding(m));
    }
}
static NSString *Preflight(UIViewController *host, FPExperimentContainer *adapter, id *outConfig, id *outObserver, UIViewController **outOriginal) {
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
    if(!PreviewABI()) return @"document preview/context-menu guard ABI unavailable";
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
    NSString *state=[@"dev.filesdualpane.experiment." stringByAppendingString:NSUUID.UUID.UUIDString];
    Set(copy,@"setStateIdentifier:",state);
    SEL drag=NSSelectorFromString(@"setCollectionSupportsDragAndDrop:");
    ((void(*)(id,SEL,BOOL))[copy methodForSelector:drag])(copy,drag,NO);
    if(![Get(copy,@"stateIdentifier") isEqual:state] || [Get(config,@"stateIdentifier") isEqual:state]) return @"namespace isolation failed";
    *outConfig=copy; *outObserver=observer; *outOriginal=original; return nil;
}
void FPExperimentPresent(UIViewController *host) {
    if(attempted || !NSThread.isMainThread || host.presentedViewController) return;
    attempted=YES; Note(@"preflight=started; final device round; one new native Split, not two parallel panes");
    originalRoot=host; originalWindow=host.view.window;
    originalControllers=[NSPointerArray weakObjectsPointerArray]; originalParents=[NSPointerArray weakObjectsPointerArray]; Snapshot(host);
    FPExperimentContainer *container=[FPExperimentContainer new];
    id config=nil,observer=nil; UIViewController *original=nil;
    NSString *failure=Preflight(host,container,&config,&observer,&original);
    if(!failure) {
        Note(@"preflight=passed; copied namespace; real scene/mode/observer retained; drag-and-drop disabled");
        id oldFull=Get(original,@"fullDocumentManagerViewController");
        // Factory is dynamically evidenced on 20G75; no guessed enum or nil required argument.
        Note(@"construction=entered");
        UIViewController *split=[(id<FPNativeFactory>)[NSClassFromString(@"DOCSplitBrowserViewController") alloc] initWithConfiguration:config sourceObserver:observer];
        id full=Get(split,@"fullDocumentManagerViewController");
        if(!split || !full || split==original || full==oldFull || split.parentViewController) failure=@"factory did not produce unattached independent Split/Full";
        if(!failure) {
            NSMutableArray *watch=[NSMutableArray arrayWithObjects:split,full,container,config,nil];
            NSMutableArray *names=[NSMutableArray arrayWithObjects:@"split",@"full",@"adapterContainer",@"configuration",nil];
            for(NSString *key in @[@"hierarchyController",@"documentManager",@"dataSource",@"actionManager",@"internalNavigationController"]) {
                id value=Get(full,key), old=Get(oldFull,key);
                if(!value || value==old) { failure=[@"new dependency missing/shared: " stringByAppendingString:key]; break; }
                [watch addObject:value]; [names addObject:key];
            }
            if(!failure && Get(full,@"fullDocumentManagerDelegate")!=split) failure=@"factory internal Full delegate is not new Split";
            if(!failure) {
                ((UIDocumentBrowserViewController *)full).delegate=container;
                ((UIDocumentBrowserViewController *)full).allowsDocumentCreation=NO;
                if(((UIDocumentBrowserViewController *)full).delegate!=container || Get(Get(full,@"documentManager"),@"uiBrowserDelegate")!=container) failure=@"external delegate isolation failed";
            }
            if(!failure) {
                watched=[NSPointerArray weakObjectsPointerArray]; for(id object in watch) [watched addPointer:(__bridge void *)object]; watchNames=[names copy];
                container.nativeSplit=split; container.configuration=config; container.sourceObserver=observer;
                observedSplit=split; InstallPreviewGuards(); FPLifecycleSetEventObserver(Observe);
                Note(@"construction=passed; independent Full/hierarchy/documentManager/dataSource/actionManager/navigation; external delegate isolated");
                Note([NSString stringWithFormat:@"before presentation originalGraphPreserved=%d",GraphPreserved()]);
                UINavigationController *modal=[[UINavigationController alloc] initWithRootViewController:container];
                modal.modalPresentationStyle=UIModalPresentationFullScreen; modal.modalInPresentation=YES;
                [host presentViewController:modal animated:YES completion:nil]; return;
            }
        }
        Note(@"construction failed; new local references released without presenting or touching original containment");
    }
    Note([@"blocked: " stringByAppendingString:failure?:@"unknown"]);
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"实验未呈现" message:failure preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:alert animated:YES completion:nil];
}
BOOL FPExperimentHasRun(void) { return attempted; }
NSString *FPExperimentReport(void) {
    NSMutableString *out=[NSMutableString stringWithString:@"Files native experiment 0.3.0 — final round\nScope: one NEW native Split in an independent dismissible UIKit container; no transplanted original controllers. Not a finished dual-pane file manager.\nNo paths, names, URLs, account data, disk logging or networking from the experiment. Files/provider normal activity and preference writes are not suppressed. Native menus are NOT a write sandbox: do not use copy/move/delete/rename/import.\n"];
    [out appendFormat:@"attempted=%d presented=%d closeRequested=%d selectionCallbacks=%u hierarchyCallbacksAfterPresentation=%u blockedOpenPreviewCallbacks=%u originalGraphPreserved=%d\n",attempted,shown,closing,selections,navigationUpdates,blockedOpens,attempted?GraphPreserved():NO];
    [out appendString:@"Callbacks indicate exercised native code, not proof of successful directory navigation or isolated history. Verify displayed navigation/back manually. Weak stillAlive is not a leak conclusion.\n"];
    for(NSString *s in states) [out appendFormat:@"%@\n",s];
    return out;
}
