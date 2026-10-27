// Native actions retain Files' provider-aware implementation.
static FPBrowserPane *PaneForResponder(UIResponder *r) {
    for(;r;r=r.nextResponder) if([r isKindOfClass:FPBrowserPane.class]) return (id)r;
    return nil;
}
#include "CompactCells.inc"
static BOOL IsPaneListCell(UICollectionViewCell *cell) {
    if(objc_getAssociatedObject(cell,&FPCellResettingKey) || !PaneForResponder(cell)) return NO;
    UICollectionView *collection=nil;
    for(UIView *v=cell.superview;v;v=v.superview) if([v isKindOfClass:UICollectionView.class]) { collection=(id)v; break; }
    if(!collection || !InExperiment(collection.delegate)) return NO;
    if([collection.delegate isKindOfClass:NSClassFromString(@"Files.DOCSidebarViewController")]) return YES;
    id controller=collection.delegate; SEL list=NSSelectorFromString(@"accessibilityIsInListMode");
    if(!ABI([controller class],NSStringFromSelector(list),"B@:") || !((BOOL(*)(id,SEL))[controller methodForSelector:list])(controller,list)) return NO;
    return cell.bounds.size.width>=collection.bounds.size.width*0.75;
}
static void FPStyleVisibleCell(UICollectionViewCell *cell) {
    // Do not classify a busy/resetting cell as out-of-scope and restore it mid-apply.
    if(objc_getAssociatedObject(cell,&FPCellBusyKey) || objc_getAssociatedObject(cell,&FPCellResettingKey)) return;
    StyleCell(cell,IsPaneListCell(cell));
}
static void FPHookCell(Class cls) {
    static NSMutableSet *classes; if(!classes) classes=[NSMutableSet new];
    for(Class p=cls;p;p=class_getSuperclass(p)) if([classes containsObject:NSStringFromClass(p)]) return;
    [classes addObject:NSStringFromClass(cls)];
    SEL layout=@selector(layoutSubviews); Method lm=class_getInstanceMethod(cls,layout); IMP lo=method_getImplementation(lm);
    class_replaceMethod(cls,layout,imp_implementationWithBlock(^(UICollectionViewCell *cell){
        ((void(*)(id,SEL))lo)(cell,layout); FPStyleVisibleCell(cell);
    }),method_getTypeEncoding(lm));
    SEL reuse=@selector(prepareForReuse); Method rm=class_getInstanceMethod(cls,reuse); IMP ro=method_getImplementation(rm);
    class_replaceMethod(cls,reuse,imp_implementationWithBlock(^(UICollectionViewCell *cell){
        objc_setAssociatedObject(cell,&FPCellResettingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @try { StyleCell(cell,NO); ((void(*)(id,SEL))ro)(cell,reuse); }
        @finally { objc_setAssociatedObject(cell,&FPCellResettingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    }),method_getTypeEncoding(rm));
}
static void FPRestorePaneStyles(UIViewController *owner) {
    if(!InExperiment(owner)) return;
    // A single close-time pass, never a controller layout or fitting pass.
    id collection=Get(owner,@"collectionView");
    if([collection isKindOfClass:UICollectionView.class]) for(UICollectionViewCell *cell in [(UICollectionView *)collection visibleCells]) StyleCell(cell,NO);
    for(UIViewController *child in owner.childViewControllers) FPRestorePaneStyles(child);
}
static void InstallNativeActions(void) {
    for(NSString *name in @[@"Files.DOCItemCollectionViewController",@"Files.DOCSidebarViewController"]) {
        Class cls=NSClassFromString(name);
        SEL display=NSSelectorFromString(@"collectionView:willDisplayCell:forItemAtIndexPath:");
        if(!ABI(cls,NSStringFromSelector(display),"v@:@@@")) continue;
        Method method=class_getInstanceMethod(cls,display); IMP old=method_getImplementation(method);
        class_replaceMethod(cls,display,imp_implementationWithBlock(^(id owner,UICollectionView *cv,UICollectionViewCell *cell,NSIndexPath *path){
            ((void(*)(id,SEL,id,id,id))old)(owner,display,cv,cell,path);
            if(!InExperiment(owner) || ![cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) return;
            FPHookCell(cell.class); FPStyleVisibleCell(cell);
        }),method_getTypeEncoding(method));
    }
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
