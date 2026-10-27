// Public configurations/accessories only. Never rewrite native labels, constraints or frames.
static char CellStyleKey, FPCellBusyKey, FPCellResettingKey, FPAccessoriesKey, FPBackgroundKey;
static void FPCompactAccessories(UICollectionViewCell *cell, BOOL compact) {
    if(![cell isKindOfClass:UICollectionViewListCell.class]) return;
    UICollectionViewListCell *list=(id)cell;
    NSArray *current=list.accessories;
    NSDictionary *saved=objc_getAssociatedObject(cell,&FPAccessoriesKey);
    if(saved && current!=saved[@"applied"]) {
        objc_setAssociatedObject(cell,&FPAccessoriesKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); saved=nil;
    }
    if(!compact) {
        if(saved) {
            objc_setAssociatedObject(cell,&FPAccessoriesKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            list.accessories=saved[@"original"];
        }
        return;
    }
    if(saved) return;
    NSMutableArray *filtered=nil;
    for(UICellAccessory *accessory in current) {
        if([accessory isKindOfClass:UICellAccessoryMultiselect.class] || [accessory isKindOfClass:UICellAccessoryDisclosureIndicator.class]) {
            if(!filtered) filtered=[current mutableCopy];
            [filtered removeObjectIdenticalTo:accessory];
        }
    }
    if(!filtered) return;
    list.accessories=filtered;
    objc_setAssociatedObject(cell,&FPAccessoriesKey,@{@"original":current,@"applied":list.accessories},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void FPCompactBackground(UICollectionViewCell *cell, BOOL compact) {
    UIBackgroundConfiguration *current=cell.backgroundConfiguration;
    NSDictionary *saved=objc_getAssociatedObject(cell,&FPBackgroundKey);
    if(saved && current!=saved[@"applied"]) {
        objc_setAssociatedObject(cell,&FPBackgroundKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); saved=nil;
    }
    if(!compact || !cell.isSelected) {
        if(saved) {
            objc_setAssociatedObject(cell,&FPBackgroundKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            cell.backgroundConfiguration=saved[@"original"]==NSNull.null ? nil : saved[@"original"];
        }
        return;
    }
    UIColor *color=[cell.tintColor colorWithAlphaComponent:0.18];
    if(saved && [current.backgroundColor isEqual:color]) return;
    id original=saved[@"original"] ?: current ?: NSNull.null;
    UIBackgroundConfiguration *config=[current copy] ?: [UIBackgroundConfiguration clearConfiguration];
    config.backgroundColor=color;
    cell.backgroundConfiguration=config;
    objc_setAssociatedObject(cell,&FPBackgroundKey,@{@"original":original,@"applied":cell.backgroundConfiguration},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static UIFont *FPCompactFont(UICollectionViewCell *cell, BOOL secondary) {
    return [[UIFontMetrics metricsForTextStyle:secondary ? UIFontTextStyleCaption1 : UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:secondary ? 13 : 14] compatibleWithTraitCollection:cell.traitCollection];
}
static BOOL FPCompactConfigurationMatches(UIListContentConfiguration *config, UICollectionViewCell *cell) {
    return CGSizeEqualToSize(config.imageProperties.maximumSize,CGSizeMake(20,20)) &&
        CGSizeEqualToSize(config.imageProperties.reservedLayoutSize,CGSizeMake(20,20)) &&
        config.imageToTextPadding==6 && config.directionalLayoutMargins.leading==10 &&
        config.directionalLayoutMargins.trailing==10 && config.axesPreservingSuperviewLayoutMargins==0 &&
        [config.textProperties.font isEqual:FPCompactFont(cell,NO)] &&
        [config.secondaryTextProperties.font isEqual:FPCompactFont(cell,YES)] &&
        config.textProperties.adjustsFontForContentSizeCategory && config.secondaryTextProperties.adjustsFontForContentSizeCategory;
}
static void StyleCell(UICollectionViewCell *cell, BOOL compact) {
    // Busy is not a scope exit. Set the guard before any setter can synchronously reenter.
    if(objc_getAssociatedObject(cell,&FPCellBusyKey)) return;
    objc_setAssociatedObject(cell,&FPCellBusyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        NSDictionary *saved=objc_getAssociatedObject(cell,&CellStyleKey);
        UIListContentConfiguration *current=(id)cell.contentConfiguration;
        BOOL publicContent=[current isKindOfClass:UIListContentConfiguration.class];
        FPCompactAccessories(cell,compact && publicContent);
        FPCompactBackground(cell,compact && publicContent);
        if(!publicContent) {
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
            config.textProperties.font=original.textProperties.font;
            config.secondaryTextProperties.font=original.secondaryTextProperties.font;
            config.textProperties.adjustsFontForContentSizeCategory=original.textProperties.adjustsFontForContentSizeCategory;
            config.secondaryTextProperties.adjustsFontForContentSizeCategory=original.secondaryTextProperties.adjustsFontForContentSizeCategory;
            objc_setAssociatedObject(cell,&CellStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            cell.contentConfiguration=config; return;
        }
        if(FPCompactConfigurationMatches(current,cell)) return;
        UIListContentConfiguration *config=[current copy];
        UIListContentConfiguration *original=saved[@"original"] ?: [current copy];
        config.imageProperties.maximumSize=CGSizeMake(20,20);
        config.imageProperties.reservedLayoutSize=CGSizeMake(20,20);
        config.imageToTextPadding=6;
        NSDirectionalEdgeInsets margins=config.directionalLayoutMargins;
        margins.leading=10; margins.trailing=10; config.directionalLayoutMargins=margins;
        config.axesPreservingSuperviewLayoutMargins=0;
        config.textProperties.font=FPCompactFont(cell,NO);
        config.secondaryTextProperties.font=FPCompactFont(cell,YES);
        config.textProperties.adjustsFontForContentSizeCategory=YES;
        config.secondaryTextProperties.adjustsFontForContentSizeCategory=YES;
        cell.contentConfiguration=config;
        objc_setAssociatedObject(cell,&CellStyleKey,@{@"original":original,@"applied":cell.contentConfiguration},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @finally {
        objc_setAssociatedObject(cell,&FPCellBusyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
