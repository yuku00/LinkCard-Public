// Content, accessories and selection background have independent capability gates.
static char CellStyleKey, FPCellBusyKey, FPCellResettingKey, FPAccessoriesKey, FPBackgroundKey, FPStyleResultKey;
typedef NS_OPTIONS(NSUInteger, FPStyleResult) {
    FPStyleOutOfScope=0, FPStyleAccessoriesApplied=1, FPStyleBackgroundApplied=2,
    FPStylePublicApplied=4, FPStyleNativeApplied=8, FPStyleContentUnsupported=16
};
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
    NSMutableDictionary *state=[@{@"original":current,@"applied":filtered} mutableCopy];
    objc_setAssociatedObject(cell,&FPAccessoriesKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    list.accessories=filtered;
    state[@"applied"]=list.accessories;
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
    NSMutableDictionary *state=[@{@"original":original,@"applied":config} mutableCopy];
    objc_setAssociatedObject(cell,&FPBackgroundKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    cell.backgroundConfiguration=config;
    state[@"applied"]=cell.backgroundConfiguration;
}
static UIFont *FPCompactFont(UICollectionViewCell *cell, BOOL secondary) {
    return [[UIFontMetrics metricsForTextStyle:secondary ? UIFontTextStyleCaption1 : UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:secondary ? 13 : 14] compatibleWithTraitCollection:cell.traitCollection];
}
#include "NativeCompact.inc"
static NSInteger FPPublicNameLines(UIListContentConfiguration *config, UICollectionViewCell *cell) {
    CGFloat detail=(config.secondaryText.length || config.secondaryAttributedText.length) ? FPCompactFont(cell,YES).lineHeight : 0;
    return FPCompactNameLines(MAX(0,cell.bounds.size.height-8),FPCompactFont(cell,NO).lineHeight,detail);
}
static BOOL FPPublicFits(UIListContentConfiguration *config, UICollectionViewCell *cell) {
    CGFloat detail=(config.secondaryText.length || config.secondaryAttributedText.length) ? FPCompactFont(cell,YES).lineHeight : 0;
    return cell.bounds.size.height>=MAX(20,FPCompactFont(cell,NO).lineHeight+detail)+8;
}
static BOOL FPCompactConfigurationMatches(UIListContentConfiguration *config, UICollectionViewCell *cell) {
    return CGSizeEqualToSize(config.imageProperties.maximumSize,CGSizeMake(20,20)) &&
        CGSizeEqualToSize(config.imageProperties.reservedLayoutSize,CGSizeMake(20,20)) &&
        config.imageToTextPadding==6 && config.directionalLayoutMargins.leading==10 &&
        config.directionalLayoutMargins.trailing==10 && config.directionalLayoutMargins.top==4 && config.directionalLayoutMargins.bottom==4 && config.axesPreservingSuperviewLayoutMargins==0 &&
        config.textProperties.numberOfLines==FPPublicNameLines(config,cell) && config.secondaryTextProperties.numberOfLines==1 &&
        config.textProperties.lineBreakMode==NSLineBreakByTruncatingTail && config.secondaryTextProperties.lineBreakMode==NSLineBreakByTruncatingTail &&
        [config.textProperties.font isEqual:FPCompactFont(cell,NO)] &&
        [config.secondaryTextProperties.font isEqual:FPCompactFont(cell,YES)] &&
        config.textProperties.adjustsFontForContentSizeCategory && config.secondaryTextProperties.adjustsFontForContentSizeCategory;
}
static void StyleCell(UICollectionViewCell *cell, BOOL compact) {
    // Busy is not a scope exit. Set the guard before any setter can synchronously reenter.
    if(objc_getAssociatedObject(cell,&FPCellBusyKey)) return;
    objc_setAssociatedObject(cell,&FPCellBusyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    FPStyleResult result=FPStyleOutOfScope;
    @try {
        NSDictionary *saved=objc_getAssociatedObject(cell,&CellStyleKey);
        UIListContentConfiguration *current=(id)cell.contentConfiguration;
        BOOL publicContent=[current isKindOfClass:UIListContentConfiguration.class];
        FPCompactAccessories(cell,compact);
        FPCompactBackground(cell,compact);
        BOOL nativeApplied=FPCompactNative(cell,compact);
        if(compact) {
            if([cell isKindOfClass:UICollectionViewListCell.class]) result|=FPStyleAccessoriesApplied;
            if(objc_getAssociatedObject(cell,&FPBackgroundKey)) result|=FPStyleBackgroundApplied;
            if(nativeApplied) result|=FPStyleNativeApplied;
        }
        if(nativeApplied) {
            objc_setAssociatedObject(cell,&CellStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); return;
        }
        if(!publicContent) {
            if(compact) result|=FPStyleContentUnsupported;
            objc_setAssociatedObject(cell,&CellStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); return;
        }
        // Native replacement owns its content and styling; an old snapshot must never win.
        if(saved && current!=saved[@"applied"]) {
            objc_setAssociatedObject(cell,&CellStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); saved=nil;
        }
        BOOL fits=compact && FPPublicFits(current,cell);
        if(compact) result|=fits ? FPStylePublicApplied : FPStyleContentUnsupported;
        if(!compact || !fits) {
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
            config.textProperties.numberOfLines=original.textProperties.numberOfLines;
            config.secondaryTextProperties.numberOfLines=original.secondaryTextProperties.numberOfLines;
            config.textProperties.lineBreakMode=original.textProperties.lineBreakMode;
            config.secondaryTextProperties.lineBreakMode=original.secondaryTextProperties.lineBreakMode;
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
        margins.leading=10; margins.trailing=10; margins.top=4; margins.bottom=4; config.directionalLayoutMargins=margins;
        config.axesPreservingSuperviewLayoutMargins=0;
        config.textProperties.font=FPCompactFont(cell,NO);
        config.secondaryTextProperties.font=FPCompactFont(cell,YES);
        config.textProperties.adjustsFontForContentSizeCategory=YES;
        config.secondaryTextProperties.adjustsFontForContentSizeCategory=YES;
        config.textProperties.numberOfLines=FPPublicNameLines(config,cell);
        config.secondaryTextProperties.numberOfLines=1;
        config.textProperties.lineBreakMode=NSLineBreakByTruncatingTail;
        config.secondaryTextProperties.lineBreakMode=NSLineBreakByTruncatingTail;
        NSMutableDictionary *state=[@{@"original":original,@"applied":config} mutableCopy];
        objc_setAssociatedObject(cell,&CellStyleKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.contentConfiguration=config;
        state[@"applied"]=cell.contentConfiguration;
    } @finally {
        NSNumber *previous=objc_getAssociatedObject(cell,&FPStyleResultKey);
        if(!previous || previous.unsignedIntegerValue!=result) objc_setAssociatedObject(cell,&FPStyleResultKey,@(result),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell,&FPCellBusyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
