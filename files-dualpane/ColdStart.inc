// One automatic attempt per process, armed by the real scene connection only.
static BOOL FPColdConsumed, FPColdConnected;
static __weak UIScene *FPColdScene;
static BOOL FPEntryABI(Class cls, SEL sel, const char *types) {
    Method m=class_getInstanceMethod(cls,sel); if(!m) return NO;
    NSMethodSignature *a=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)], *b=[NSMethodSignature signatureWithObjCTypes:types];
    if(strcmp(a.methodReturnType,b.methodReturnType)||a.numberOfArguments!=b.numberOfArguments) return NO;
    for(NSUInteger i=0;i<a.numberOfArguments;i++) if(strcmp([a getArgumentTypeAtIndex:i],[b getArgumentTypeAtIndex:i])) return NO;
    return YES;
}
static BOOL FPReadyTree(UIViewController *v) {
    if(v.presentedViewController || v.isBeingPresented || v.isBeingDismissed || v.transitionCoordinator) return NO;
    for(UIViewController *c in v.childViewControllers) if(!FPReadyTree(c)) return NO;
    return YES;
}
static BOOL FPHasModal(UIViewController *v) {
    if(v.presentedViewController) return YES;
    for(UIViewController *c in v.childViewControllers) if(FPHasModal(c)) return YES;
    return NO;
}
static BOOL FPHasBrowser(UIViewController *v) {
    if([v isKindOfClass:NSClassFromString(@"DOCSplitBrowserViewController")]) return v.isViewLoaded && v.view.window!=nil;
    for(UIViewController *c in v.childViewControllers) if(FPHasBrowser(c)) return YES;
    return NO;
}
static void FPTryCold(NSUInteger remaining) {
    if(FPColdConsumed || !FPColdConnected) return;
    UIScene *scene=FPColdScene;
    if(!remaining || !scene) { FPColdConsumed=YES; return; }
    if([scene isKindOfClass:UIWindowScene.class] && scene.activationState==UISceneActivationStateForegroundActive) {
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIViewController *root=window.rootViewController;
            if(!window.isKeyWindow || !root) continue;
            // A modal/preview already owns this launch. Never compete or reopen later.
            if(FPHasModal(root)) { FPColdConsumed=YES; return; }
            if(FPReadyTree(root) && FPHasBrowser(root)) { FPColdConsumed=YES; FPDualPanePresent(root); return; }
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{ FPTryCold(remaining-1); });
}
static void FPInstallColdStart(void) {
    Class cls=NSClassFromString(@"Files.WindowSceneDelegate");
    SEL connect=@selector(scene:willConnectToSession:options:);
    // Public scene protocol, exact class and ABI observed in the lifecycle report.
    if(!FPEntryABI(cls,connect,"v@:@@@")) return; // manual entry remains available
    Method m=class_getInstanceMethod(cls,connect); IMP old=method_getImplementation(m);
    class_replaceMethod(cls,connect,imp_implementationWithBlock(^(id self,UIScene *scene,UISceneSession *session,UISceneConnectionOptions *options){
        BOOL first=!FPColdConnected; FPColdConnected=YES;
        if(first) {
            FPColdScene=scene;
            if(options.URLContexts.count || options.userActivities.count || options.shortcutItem) FPColdConsumed=YES;
        }
        ((void(*)(id,SEL,id,id,id))old)(self,connect,scene,session,options);
        if(first) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ FPTryCold(20); });
    }),method_getTypeEncoding(m));
    for(NSString *name in @[@"scene:openURLContexts:",@"scene:continueUserActivity:"]) {
        SEL sel=NSSelectorFromString(name); if(!FPEntryABI(cls,sel,"v@:@@")) continue;
        Method method=class_getInstanceMethod(cls,sel); IMP original=method_getImplementation(method);
        class_replaceMethod(cls,sel,imp_implementationWithBlock(^(id self,id scene,id payload){
            FPColdConsumed=YES;
            ((void(*)(id,SEL,id,id))original)(self,sel,scene,payload);
        }),method_getTypeEncoding(method));
    }
}
