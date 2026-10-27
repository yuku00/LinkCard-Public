// Sidebar-only public UIKit styling. No UILabel/UIAppearance or global cell hooks.
// Evidence: Files.DOCSidebarViewController and nested DOCSidebarItemCell icon providers.
static char FPSidebarStyleKey, FPSidebarBusyKey, FPSidebarTitleKey;
static BOOL FPSidebarScope(BOOL pane, BOOL sidebar, BOOL resetting) { return pane && sidebar && !resetting; }
static NSInteger FPSidebarLines(CGFloat textWidth, CGFloat availableWidth, CGFloat height, CGFloat line) {
    (void)textWidth; (void)availableWidth; (void)height; (void)line; return 1;
}
static CGFloat FPSidebarHeight(CGFloat line, NSInteger lines) { return MAX(44,ceil(line*lines+8)); }
static UIViewController *FPSidebarOwner(UIResponder *r) {
    Class cls=NSClassFromString(@"Files.DOCSidebarViewController");
    for(;r;r=r.nextResponder) if(cls && [r isKindOfClass:cls]) return (id)r;
    return nil;
}
static BOOL FPSidebarCellScope(UICollectionViewCell *cell) {
    UIViewController *owner=FPSidebarOwner(cell);
    return FPSidebarScope(PaneForResponder(cell)!=nil,owner && InExperiment(owner),[objc_getAssociatedObject(cell,&FPSidebarBusyKey) boolValue]);
}
static void FPSidebarStyle(UICollectionViewCell *cell, BOOL compact) {
    FPDisclosure(cell,compact);
    FPContentMargins(cell,compact);
    UIListContentConfiguration *saved=objc_getAssociatedObject(cell,&FPSidebarStyleKey);
    if(!compact && !saved) return;
    if(![cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) {
        objc_setAssociatedObject(cell,&FPSidebarStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); return;
    }
    UIListContentConfiguration *config=[(UIListContentConfiguration *)cell.contentConfiguration copy];
    if(!compact) {
        // Restore only properties we own: native text/image/provider state may have changed.
        config.textProperties.font=saved.textProperties.font;
        config.textProperties.numberOfLines=saved.textProperties.numberOfLines;
        config.textProperties.lineBreakMode=saved.textProperties.lineBreakMode;
        config.imageProperties.maximumSize=saved.imageProperties.maximumSize;
        config.imageProperties.reservedLayoutSize=saved.imageProperties.reservedLayoutSize;
        config.axesPreservingSuperviewLayoutMargins=saved.axesPreservingSuperviewLayoutMargins;
        config.directionalLayoutMargins=saved.directionalLayoutMargins;
        config.imageToTextPadding=saved.imageToTextPadding;
        objc_setAssociatedObject(cell,&FPSidebarStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.contentConfiguration=config; return;
    }
    UIFont *font=FPCellFont(cell,14);
    NSString *text=config.text ?: config.attributedText.string ?: @"";
    CGFloat textWidth=[text sizeWithAttributes:@{NSFontAttributeName:font}].width;
    // contentView already excludes native accessories; do not change their hit areas.
    CGFloat available=MAX(0,cell.contentView.bounds.size.width-12-(config.image ? 26 : 0));
    NSInteger lines=FPSidebarLines(textWidth,available,cell.bounds.size.height,font.lineHeight);
    NSDirectionalEdgeInsets margins=NSDirectionalEdgeInsetsMake(4,6,4,6);
    if([config.textProperties.font isEqual:font] && config.textProperties.numberOfLines==lines && config.textProperties.lineBreakMode==NSLineBreakByTruncatingTail && CGSizeEqualToSize(config.imageProperties.maximumSize,CGSizeMake(20,20)) && CGSizeEqualToSize(config.imageProperties.reservedLayoutSize,CGSizeMake(20,20)) && NSDirectionalEdgeInsetsEqualToDirectionalEdgeInsets(config.directionalLayoutMargins,margins) && config.imageToTextPadding==6 && config.axesPreservingSuperviewLayoutMargins==0) return;
    if(!saved) objc_setAssociatedObject(cell,&FPSidebarStyleKey,[config copy],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    config.textProperties.font=font; config.textProperties.numberOfLines=lines;
    config.textProperties.lineBreakMode=NSLineBreakByTruncatingTail;
    config.imageProperties.maximumSize=CGSizeMake(20,20); config.imageProperties.reservedLayoutSize=CGSizeMake(20,20);
    config.axesPreservingSuperviewLayoutMargins=0;
    config.directionalLayoutMargins=margins; config.imageToTextPadding=6;
    cell.contentConfiguration=config;
}
static void FPSidebarTitle(UIViewController *owner, BOOL compact) {
    NSNumber *saved=objc_getAssociatedObject(owner,&FPSidebarTitleKey);
    if(compact) {
        if(!saved) objc_setAssociatedObject(owner,&FPSidebarTitleKey,@(owner.navigationItem.largeTitleDisplayMode),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(owner.navigationItem.largeTitleDisplayMode!=UINavigationItemLargeTitleDisplayModeNever)
            owner.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    } else if(saved) {
        owner.navigationItem.largeTitleDisplayMode=saved.integerValue;
        objc_setAssociatedObject(owner,&FPSidebarTitleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static void FPSidebarHookCell(Class cls) {
    static NSMutableSet *classes; if(!classes) classes=[NSMutableSet new];
    NSString *key=NSStringFromClass(cls); if([classes containsObject:key]) return;
    // A parent already hooked covers subclasses; avoid chaining the same policy twice.
    for(Class p=class_getSuperclass(cls);p;p=class_getSuperclass(p)) if([classes containsObject:NSStringFromClass(p)]) return;
    [classes addObject:key];
    SEL layout=@selector(layoutSubviews); Method lm=class_getInstanceMethod(cls,layout); IMP lo=method_getImplementation(lm);
    class_replaceMethod(cls,layout,imp_implementationWithBlock(^(UICollectionViewCell *cell){
        if([objc_getAssociatedObject(cell,&FPSidebarBusyKey) boolValue]) { ((void(*)(id,SEL))lo)(cell,layout); return; }
        BOOL compact=FPSidebarCellScope(cell);
        objc_setAssociatedObject(cell,&FPSidebarBusyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(!compact) FPSidebarStyle(cell,NO);
        ((void(*)(id,SEL))lo)(cell,layout); FPSidebarStyle(cell,compact);
        objc_setAssociatedObject(cell,&FPSidebarBusyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }),method_getTypeEncoding(lm));
    SEL reuse=@selector(prepareForReuse); Method rm=class_getInstanceMethod(cls,reuse); IMP ro=method_getImplementation(rm);
    class_replaceMethod(cls,reuse,imp_implementationWithBlock(^(UICollectionViewCell *cell){
        objc_setAssociatedObject(cell,&FPSidebarBusyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        FPSidebarStyle(cell,NO); ((void(*)(id,SEL))ro)(cell,reuse);
        objc_setAssociatedObject(cell,&FPSidebarBusyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }),method_getTypeEncoding(rm));
    SEL fit=@selector(preferredLayoutAttributesFittingAttributes:); Method fm=class_getInstanceMethod(cls,fit); IMP fo=method_getImplementation(fm);
    class_replaceMethod(cls,fit,imp_implementationWithBlock(^id(UICollectionViewCell *cell,UICollectionViewLayoutAttributes *attributes){
        UICollectionViewLayoutAttributes *result=((id(*)(id,SEL,id))fo)(cell,fit,attributes);
        if(!FPSidebarCellScope(cell) || ![cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) return result;
        FPSidebarStyle(cell,YES);
        UIListContentConfiguration *config=(id)cell.contentConfiguration;
        result=[result copy]; CGSize size=result.size;
        size.height=FPSidebarHeight(FPCellFont(cell,14).lineHeight,config.textProperties.numberOfLines);
        result.size=size; return result;
    }),method_getTypeEncoding(fm));
}
static void FPSidebarUpdate(UIViewController *owner, BOOL compact) {
    FPSidebarTitle(owner,compact);
    id collection=Get(owner,@"collectionView"); if(![collection isKindOfClass:UICollectionView.class]) return;
    for(UICollectionViewCell *cell in [(UICollectionView *)collection visibleCells]) {
        if(compact && [cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) FPSidebarHookCell(cell.class);
        FPSidebarStyle(cell,compact && FPSidebarCellScope(cell));
    }
}
static void InstallSidebarStyling(void) {
    Class cls=NSClassFromString(@"Files.DOCSidebarViewController");
    if(!cls || ![cls isSubclassOfClass:UIViewController.class]) return;
    SEL layout=@selector(viewDidLayoutSubviews);
    if(ABI(cls,NSStringFromSelector(layout),"v@:")) {
        Method m=class_getInstanceMethod(cls,layout); IMP old=method_getImplementation(m);
        class_replaceMethod(cls,layout,imp_implementationWithBlock(^(UIViewController *owner){
            ((void(*)(id,SEL))old)(owner,layout); FPSidebarUpdate(owner,InExperiment(owner));
        }),method_getTypeEncoding(m));
    }
    SEL appear=@selector(viewWillAppear:);
    if(ABI(cls,NSStringFromSelector(appear),"v@:B")) {
        Method m=class_getInstanceMethod(cls,appear); IMP old=method_getImplementation(m);
        class_replaceMethod(cls,appear,imp_implementationWithBlock(^(UIViewController *owner,BOOL animated){
            FPSidebarTitle(owner,InExperiment(owner)); ((void(*)(id,SEL,BOOL))old)(owner,appear,animated);
            FPSidebarUpdate(owner,InExperiment(owner));
        }),method_getTypeEncoding(m));
    }
    SEL move=@selector(willMoveToParentViewController:);
    if(ABI(cls,NSStringFromSelector(move),"v@:@")) {
        Method m=class_getInstanceMethod(cls,move); IMP old=method_getImplementation(m);
        class_replaceMethod(cls,move,imp_implementationWithBlock(^(UIViewController *owner,UIViewController *parent){
            if(!InExperiment(parent)) FPSidebarUpdate(owner,NO);
            ((void(*)(id,SEL,id))old)(owner,move,parent);
        }),method_getTypeEncoding(m));
    }
}
