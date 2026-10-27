// Native actions retain Files' provider-aware implementation.
static FPBrowserPane *PaneForResponder(UIResponder *r) {
    for(;r;r=r.nextResponder) if([r isKindOfClass:FPBrowserPane.class]) return (id)r;
    return nil;
}
#include "CompactCells.inc"
static char FPCellEventDepthKey, FPDisplayDepthKey;
static BOOL IsPaneListCell(UICollectionViewCell *cell) {
    if(objc_getAssociatedObject(cell,&FPCellResettingKey) || !PaneForResponder(cell)) return NO;
    UICollectionView *collection=nil;
    for(UIView *v=cell.superview;v;v=v.superview) if([v isKindOfClass:UICollectionView.class]) { collection=(id)v; break; }
    if(!collection || !InExperiment(collection.delegate)) return NO;
    id controller=collection.delegate;
    if(FPClassInChain(controller,@"Files.DOCSidebarViewController"))
        return [cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class];
    if(!FPClassInChain(controller,@"Files.DOCItemCollectionViewController") ||
       (!FPClassInChain(cell,@"Files.DOCItemCollectionListCell") && !FPClassInChain(cell,@"Files.DOCItemCollectionCell"))) return NO;
    SEL list=NSSelectorFromString(@"accessibilityIsInListMode");
    if(!ABI(object_getClass(controller),NSStringFromSelector(list),"B@:") || !((BOOL(*)(id,SEL))[controller methodForSelector:list])(controller,list)) return NO;
    return collection.bounds.size.width>0 && cell.bounds.size.width>=collection.bounds.size.width*0.75;
}
static void FPStyleVisibleCell(UICollectionViewCell *cell) {
    // Do not classify a busy/resetting cell as out-of-scope and restore it mid-apply.
    if(objc_getAssociatedObject(cell,&FPCellBusyKey) || objc_getAssociatedObject(cell,&FPCellResettingKey) || [objc_getAssociatedObject(cell,&FPCellEventDepthKey) unsignedIntegerValue]) return;
    StyleCell(cell,IsPaneListCell(cell));
}
static void FPHookCell(Class cls) {
    static NSMutableSet *implementations; if(!implementations) implementations=[NSMutableSet new];
    // An inherited wrapper is already sufficient; an actual override still needs its own hook.
    for(NSString *name in @[@"updateConfigurationUsingState:",@"_bridgedUpdateConfigurationUsingState:",@"prepareForReuse"]) {
        BOOL reuse=[name isEqualToString:@"prepareForReuse"];
        if(!ABI(cls,name,reuse ? "v@:" : "v@:@")) continue;
        SEL selector=NSSelectorFromString(name); Method method=class_getInstanceMethod(cls,selector);
        IMP original=method_getImplementation(method);
        if([implementations containsObject:[NSValue valueWithPointer:(const void *)original]]) continue;
        IMP replacement;
        if(reuse) replacement=imp_implementationWithBlock(^(UICollectionViewCell *cell){
            if(objc_getAssociatedObject(cell,&FPCellResettingKey)) { ((void(*)(id,SEL))original)(cell,selector); return; }
            objc_setAssociatedObject(cell,&FPCellResettingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try { StyleCell(cell,NO); ((void(*)(id,SEL))original)(cell,selector); }
            @finally { objc_setAssociatedObject(cell,&FPCellResettingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        });
        else replacement=imp_implementationWithBlock(^(UICollectionViewCell *cell,UICellConfigurationState *state){
            NSUInteger depth=[objc_getAssociatedObject(cell,&FPCellEventDepthKey) unsignedIntegerValue];
            objc_setAssociatedObject(cell,&FPCellEventDepthKey,@(depth+1),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try { ((void(*)(id,SEL,id))original)(cell,selector,state); }
            @finally { objc_setAssociatedObject(cell,&FPCellEventDepthKey,depth ? @(depth) : nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            if(!depth) FPStyleVisibleCell(cell);
        });
        [implementations addObject:[NSValue valueWithPointer:(const void *)replacement]];
        class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
    }
}
static void FPHookDisplay(Class cls) {
    static NSMutableSet *implementations; if(!implementations) implementations=[NSMutableSet new];
    SEL display=NSSelectorFromString(@"collectionView:willDisplayCell:forItemAtIndexPath:");
    if(!ABI(cls,NSStringFromSelector(display),"v@:@@@")) return;
    Method method=class_getInstanceMethod(cls,display); IMP original=method_getImplementation(method);
    if([implementations containsObject:[NSValue valueWithPointer:(const void *)original]]) return;
    IMP replacement=imp_implementationWithBlock(^(id owner,UICollectionView *cv,UICollectionViewCell *cell,NSIndexPath *path){
        NSUInteger depth=[objc_getAssociatedObject(cell,&FPDisplayDepthKey) unsignedIntegerValue];
        objc_setAssociatedObject(cell,&FPDisplayDepthKey,@(depth+1),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @try { ((void(*)(id,SEL,id,id,id))original)(owner,display,cv,cell,path); }
        @finally { objc_setAssociatedObject(cell,&FPDisplayDepthKey,depth ? @(depth) : nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        if(depth || !InExperiment(owner)) return;
        if(IsPaneListCell(cell)) FPHookCell(object_getClass(cell));
        FPStyleVisibleCell(cell);
    });
    [implementations addObject:[NSValue valueWithPointer:(const void *)replacement]];
    class_replaceMethod(cls,display,replacement,method_getTypeEncoding(method));
}
static void FPRestorePaneStyles(UIViewController *owner) {
    if(!InExperiment(owner)) return;
    // A single close-time pass, never a controller layout or fitting pass.
    id collection=Get(owner,@"collectionView");
    if([collection isKindOfClass:UICollectionView.class]) for(UICollectionViewCell *cell in [(UICollectionView *)collection visibleCells]) StyleCell(cell,NO);
    for(UIViewController *child in owner.childViewControllers) FPRestorePaneStyles(child);
}
static void InstallNativeActions(void) {
    Class item=NSClassFromString(@"Files.DOCItemCollectionViewController"), sidebar=NSClassFromString(@"Files.DOCSidebarViewController");
    if(item) FPHookDisplay(item);
    if(sidebar) FPHookDisplay(sidebar);
    // Once at pane creation, cover already-loaded Swift/KVO overrides without scanning layouts.
    unsigned count=0; Class __unsafe_unretained *classes=objc_copyClassList(&count);
    for(unsigned i=0;i<count;i++) {
        for(Class parent=class_getSuperclass(classes[i]);parent;parent=class_getSuperclass(parent)) {
            if(parent==item || parent==sidebar) { FPHookDisplay(classes[i]); break; }
        }
    }
    free(classes);
    Class c=NSClassFromString(@"Files.DOCItemCollectionViewController");
    for(NSString *name in @[@"performDelete:",@"performDeleteNow:",@"delete:"]) {
        if(!ABI(c,name,"v@:@")) continue;
        SEL sel=NSSelectorFromString(name); Method m=class_getInstanceMethod(c,sel); IMP old=method_getImplementation(m);
        class_replaceMethod(c,sel,imp_implementationWithBlock(^(UIViewController *s,id sender){
            static char confirmed;
            if(!InExperiment(s) || [objc_getAssociatedObject(s,&confirmed) boolValue]) { ((void(*)(id,SEL,id))old)(s,sel,sender); return; }
            if(s.presentedViewController) return;
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"确认删除所选项目？" message:@"由 Files 和文件提供商执行。部分位置会永久删除且无法恢复。取消不会修改文件。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"确认删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
                objc_setAssociatedObject(s,&confirmed,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                ((void(*)(id,SEL,id))old)(s,sel,sender);
                objc_setAssociatedObject(s,&confirmed,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }]];
            [s presentViewController:alert animated:YES completion:nil];
        }),method_getTypeEncoding(m));
    }
}
