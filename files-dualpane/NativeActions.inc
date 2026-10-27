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
static char CellStyleKey;
static BOOL IsPaneListCell(UICollectionViewCell *cell) {
    if(!PaneForResponder(cell)) return NO;
    UICollectionView *collection=nil;
    for(UIView *v=cell.superview;v;v=v.superview) if([v isKindOfClass:UICollectionView.class]) { collection=(id)v; break; }
    if(!collection || !InExperiment(collection.delegate)) return NO;
    id controller=collection.delegate; SEL list=NSSelectorFromString(@"accessibilityIsInListMode");
    if(!ABI([controller class],NSStringFromSelector(list),"B@:") || !((BOOL(*)(id,SEL))[controller methodForSelector:list])(controller,list)) return NO;
    return cell.bounds.size.width>=collection.bounds.size.width*0.75;
}
static void ImproveCell(UICollectionViewCell *cell) {
    NSDictionary *saved=objc_getAssociatedObject(cell,&CellStyleKey);
    BOOL compact=IsPaneListCell(cell);
    FPCompactImages(cell.contentView,compact);
    if(!compact) {
        if(saved[@"config"]) {
            UIListContentConfiguration *config=[(UIListContentConfiguration *)cell.contentConfiguration copy];
            if([config isKindOfClass:UIListContentConfiguration.class]) {
                UIListContentConfiguration *original=saved[@"config"];
                config.textProperties.numberOfLines=original.textProperties.numberOfLines;
                config.textProperties.lineBreakMode=original.textProperties.lineBreakMode;
                config.imageProperties.maximumSize=original.imageProperties.maximumSize;
                cell.contentConfiguration=config;
            }
        }
        UILabel *label=saved[@"label"];
        if(label) { label.numberOfLines=[saved[@"lines"] integerValue]; label.lineBreakMode=[saved[@"break"] integerValue]; label.preferredMaxLayoutWidth=[saved[@"width"] doubleValue]; }
        objc_setAssociatedObject(cell,&CellStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); return;
    }
    // Only full-width native list rows, never sidebar, grids or original Files.
    if([cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) {
        UIListContentConfiguration *config=[(UIListContentConfiguration *)cell.contentConfiguration copy];
        if(!saved) objc_setAssociatedObject(cell,&CellStyleKey,@{@"config":[config copy]},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(config.textProperties.numberOfLines!=3 || config.imageProperties.maximumSize.width!=22) {
            config.textProperties.numberOfLines=3;
            config.textProperties.lineBreakMode=NSLineBreakByTruncatingTail;
            config.imageProperties.maximumSize=CGSizeMake(22,22);
            cell.contentConfiguration=config;
        }
        return;
    }
    // Legacy native cells: modify actual public UILabel objects, not Swift ivars.
    NSMutableArray<UILabel *> *labels=[NSMutableArray new]; CollectLabels(cell.contentView,labels);
    UILabel *name=nil; CGFloat top=CGFLOAT_MAX;
    for(UILabel *label in labels) {
        CGRect frame=[label convertRect:label.bounds toView:cell.contentView];
        if(label.text.length && label.font.pointSize>=13 && frame.size.width>50 && frame.origin.y<top) { name=label; top=frame.origin.y; }
    }
    if(name) {
        if(!saved) objc_setAssociatedObject(cell,&CellStyleKey,@{@"label":name,@"lines":@(name.numberOfLines),@"break":@(name.lineBreakMode),@"width":@(name.preferredMaxLayoutWidth)},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(name.numberOfLines!=3 || name.preferredMaxLayoutWidth!=name.bounds.size.width) { name.numberOfLines=3; name.lineBreakMode=NSLineBreakByTruncatingTail; name.preferredMaxLayoutWidth=name.bounds.size.width; [name invalidateIntrinsicContentSize]; }
    }
}
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
            class_replaceMethod(cls,layout,imp_implementationWithBlock(^(UICollectionViewCell *v){ ((void(*)(id,SEL))lo)(v,layout); ImproveCell(v); }),method_getTypeEncoding(lm));
            SEL fit=@selector(preferredLayoutAttributesFittingAttributes:); Method fm=class_getInstanceMethod(cls,fit); IMP fo=method_getImplementation(fm);
            class_replaceMethod(cls,fit,imp_implementationWithBlock(^id(UICollectionViewCell *v,UICollectionViewLayoutAttributes *attributes){
                UICollectionViewLayoutAttributes *result=((id(*)(id,SEL,id))fo)(v,fit,attributes);
                if(!IsPaneListCell(v) || attributes.size.width<160 || attributes.size.height>120) return result;
                ImproveCell(v);
                CGSize size=[v.contentView systemLayoutSizeFittingSize:CGSizeMake(attributes.size.width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
                result=[result copy]; CGSize value=result.size; value.height=MAX(value.height,MIN(120,ceil(size.height))); result.size=value; return result;
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
