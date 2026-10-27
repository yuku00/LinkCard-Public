// 20G75: Full's container factory gives the exact location for each visible controller.
// Never read Swift storage or treat hierarchy.lastLocation as a current-folder getter.
static char FPContainerLocationKey;
static BOOL FPBool(id object, NSString *name) {
    if(!ABI([object class],name,"B@:")) return NO;
    SEL s=NSSelectorFromString(name); return ((BOOL(*)(id,SEL))[object methodForSelector:s])(object,s);
}
static id FPClassGet(NSString *name, NSString *selector) {
    Class cls=NSClassFromString(name);
    if(!ABI(object_getClass(cls),selector,"@@:")) return nil;
    SEL s=NSSelectorFromString(selector); return ((id(*)(id,SEL))[(id)cls methodForSelector:s])(cls,s);
}
static UIViewController *FPVisibleController(FPBrowserPane *pane) {
    id nav=Get(FPFull(pane),@"internalNavigationController");
    return [nav isKindOfClass:UINavigationController.class] ? [nav visibleViewController] : nil;
}
static id FPLocationInTree(UIViewController *view) {
    id location=objc_getAssociatedObject(view,&FPContainerLocationKey); if(location) return location;
    for(UIViewController *child in view.childViewControllers) {
        id found=FPLocationInTree(child); if(found) return found;
    }
    return nil;
}
static id FPCurrentLocation(FPBrowserPane *pane) {
    if(FPBool(pane.nativeSplit,@"isShowingCollapsedSidebarViewController")) return FPClassGet(@"DOCConcreteLocation",@"browseStartingPointsLocation");
    UIViewController *visible=FPVisibleController(pane);
    if(!visible || !InExperiment(visible)) return nil;
    // A visible sidebar wins over any old collection retained by Full.
    if(FindSplit(visible,NSClassFromString(@"Files.DOCSidebarViewController")))
        return FPClassGet(@"DOCConcreteLocation",@"browseStartingPointsLocation");
    return FPLocationInTree(visible);
}
static BOOL FPBrowseVisible(FPBrowserPane *pane) {
    UIViewController *visible=FPVisibleController(pane);
    id browse=FPClassGet(@"DOCConcreteLocation",@"browseStartingPointsLocation");
    return (FPBool(pane.nativeSplit,@"isShowingCollapsedSidebarViewController") || (visible && FindSplit(visible,NSClassFromString(@"Files.DOCSidebarViewController"))!=nil) ||
                          (browse && [FPCurrentLocation(pane) isEqual:browse]));
}
static NSURL *FPFolder(FPBrowserPane *pane) {
    if(FPBrowseVisible(pane)) return nil;
    id location=FPCurrentLocation(pane);
    return FPNodeURL(Get(location,@"node"));
}
static void InstallLocationTracking(void) {
    Class cls=NSClassFromString(@"DOCFullDocumentManagerViewController");
    SEL s=NSSelectorFromString(@"provideContainerControllerAt:from:isUserInteraction:isBrowsingTrash:");
    if(!ABI(cls,NSStringFromSelector(s),"@@:@@BB")) return;
    Method m=class_getInstanceMethod(cls,s); IMP old=method_getImplementation(m);
    class_replaceMethod(cls,s,imp_implementationWithBlock(^id(id full,id location,id source,BOOL user,BOOL trash){
        id container=((id(*)(id,SEL,id,id,BOOL,BOOL))old)(full,s,location,source,user,trash);
        if(OwnState(Get(full,@"configuration")) && [container isKindOfClass:UIViewController.class])
            objc_setAssociatedObject(container,&FPContainerLocationKey,location,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return container;
    }),method_getTypeEncoding(m));
}
