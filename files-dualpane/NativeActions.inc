// Native actions deliberately retain Files' provider-aware implementation.
static FPBrowserPane *PaneForResponder(UIResponder *r) {
    for(;r;r=r.nextResponder) if([r isKindOfClass:FPBrowserPane.class]) return (id)r;
    return nil;
}
static void CollectLabels(UIView *v, NSMutableArray<UILabel *> *labels) {
    if([v isKindOfClass:UILabel.class]) [labels addObject:(id)v];
    for(UIView *child in v.subviews) CollectLabels(child,labels);
}
#include "CompactImages.inc"
#include "CompactSelection.inc"
#include "CompactCells.inc"
static void InstallNativeActions(void) {
    Class c=NSClassFromString(@"Files.DOCItemCollectionViewController");
    SEL display=NSSelectorFromString(@"collectionView:willDisplayCell:forItemAtIndexPath:");
    if(ABI(c,NSStringFromSelector(display),"v@:@@@")) {
        Method method=class_getInstanceMethod(c,display); IMP old=method_getImplementation(method);
        class_replaceMethod(c,display,imp_implementationWithBlock(^(id s,UICollectionView *cv,UICollectionViewCell *cell,NSIndexPath *path){
            ((void(*)(id,SEL,id,id,id))old)(s,display,cv,cell,path);
            if(!InExperiment(s)) return;
            ImproveCell(cell);
            // Install on the real cell class encountered at runtime. No class-name guessing.
            Class cls=cell.class;
            static NSMutableSet *classes; if(!classes) classes=[NSMutableSet new];
            NSString *key=NSStringFromClass(cls); if([classes containsObject:key]) return; [classes addObject:key];
            SEL layout=@selector(layoutSubviews); Method lm=class_getInstanceMethod(cls,layout); IMP lo=method_getImplementation(lm);
            class_replaceMethod(cls,layout,imp_implementationWithBlock(^(UICollectionViewCell *v){
                BOOL hadStyle=objc_getAssociatedObject(v,&CellStyleKey)!=nil || objc_getAssociatedObject(v,&FPSelectionViewKey)!=nil;
                // Restore BEFORE native preview layout. Call the original exactly once.
                if(hadStyle && !IsPaneListCell(v)) StyleCell(v,NO);
                ((void(*)(id,SEL))lo)(v,layout); ImproveCell(v);
            }),method_getTypeEncoding(lm));
            SEL reuse=@selector(prepareForReuse); Method rm=class_getInstanceMethod(cls,reuse); IMP ro=method_getImplementation(rm);
            class_replaceMethod(cls,reuse,imp_implementationWithBlock(^(UICollectionViewCell *v){
                objc_setAssociatedObject(v,&FPCellResettingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                StyleCell(v,NO); ((void(*)(id,SEL))ro)(v,reuse);
                objc_setAssociatedObject(v,&FPCellResettingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }),method_getTypeEncoding(rm));
            SEL selected=@selector(setSelected:); Method sm=class_getInstanceMethod(cls,selected); IMP so=method_getImplementation(sm);
            class_replaceMethod(cls,selected,imp_implementationWithBlock(^(UICollectionViewCell *v,BOOL value){
                ((void(*)(id,SEL,BOOL))so)(v,selected,value);
                FPSelectionVisual(v,IsPaneListCell(v));
            }),method_getTypeEncoding(sm));
            SEL fit=@selector(preferredLayoutAttributesFittingAttributes:); Method fm=class_getInstanceMethod(cls,fit); IMP fo=method_getImplementation(fm);
            class_replaceMethod(cls,fit,imp_implementationWithBlock(^id(UICollectionViewCell *v,UICollectionViewLayoutAttributes *attributes){
                UICollectionViewLayoutAttributes *result=((id(*)(id,SEL,id))fo)(v,fit,attributes);
                if(!IsPaneListCell(v) || attributes.size.width<120) return result;
                ImproveCell(v);
                result=[result copy]; CGSize value=result.size;
                value.height=FPCompactRowHeight(FPCellFont(v,13).lineHeight,FPCellFont(v,11).lineHeight);
                result.size=value; return result;
            }),method_getTypeEncoding(fm));
        }),method_getTypeEncoding(method));
    }
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
