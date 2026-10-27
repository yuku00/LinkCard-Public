// Public content configuration only. Never rewrite native labels, constraints or frames.
static char CellStyleKey, FPCellBusyKey, FPCellResettingKey;
static BOOL FPCompactConfigurationMatches(UIListContentConfiguration *config) {
    return CGSizeEqualToSize(config.imageProperties.maximumSize,CGSizeMake(20,20)) &&
        CGSizeEqualToSize(config.imageProperties.reservedLayoutSize,CGSizeMake(20,20)) &&
        config.imageToTextPadding==6 && config.directionalLayoutMargins.leading==10 &&
        config.directionalLayoutMargins.trailing==10 && config.axesPreservingSuperviewLayoutMargins==0;
}
static void StyleCell(UICollectionViewCell *cell, BOOL compact) {
    // Busy is not a scope exit. Set the guard before any setter can synchronously reenter.
    if(objc_getAssociatedObject(cell,&FPCellBusyKey)) return;
    objc_setAssociatedObject(cell,&FPCellBusyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        NSDictionary *saved=objc_getAssociatedObject(cell,&CellStyleKey);
        UIListContentConfiguration *current=(id)cell.contentConfiguration;
        if(![current isKindOfClass:UIListContentConfiguration.class]) {
            objc_setAssociatedObject(cell,&CellStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); return;
        }
        // Native replacement owns its content and styling; an old snapshot must never win.
        if(saved && current!=saved[@"applied"]) {
            objc_setAssociatedObject(cell,&CellStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); saved=nil;
        }
        if(!compact) {
            if(!saved) return;
            UIListContentConfiguration *config=[current copy], *original=saved[@"original"];
            config.imageProperties.maximumSize=original.imageProperties.maximumSize;
            config.imageProperties.reservedLayoutSize=original.imageProperties.reservedLayoutSize;
            config.imageToTextPadding=original.imageToTextPadding;
            config.directionalLayoutMargins=original.directionalLayoutMargins;
            config.axesPreservingSuperviewLayoutMargins=original.axesPreservingSuperviewLayoutMargins;
            objc_setAssociatedObject(cell,&CellStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            cell.contentConfiguration=config; return;
        }
        if(FPCompactConfigurationMatches(current)) return;
        UIListContentConfiguration *config=[current copy];
        UIListContentConfiguration *original=saved[@"original"] ?: [current copy];
        config.imageProperties.maximumSize=CGSizeMake(20,20);
        config.imageProperties.reservedLayoutSize=CGSizeMake(20,20);
        config.imageToTextPadding=6;
        NSDirectionalEdgeInsets margins=config.directionalLayoutMargins;
        margins.leading=10; margins.trailing=10; config.directionalLayoutMargins=margins;
        config.axesPreservingSuperviewLayoutMargins=0;
        cell.contentConfiguration=config;
        objc_setAssociatedObject(cell,&CellStyleKey,@{@"original":original,@"applied":cell.contentConfiguration},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @finally {
        objc_setAssociatedObject(cell,&FPCellBusyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
