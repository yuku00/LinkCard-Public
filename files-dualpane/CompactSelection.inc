// Public list accessories only: no recursive circle/image/button hiding.
static char FPAccessoriesKey, FPFilteredAccessoriesKey, FPSelectionViewKey;
static UIAccessibilityTraits FPSelectionTraits(UIAccessibilityTraits traits, BOOL selected) {
    return selected ? traits|UIAccessibilityTraitSelected : traits&~UIAccessibilityTraitSelected;
}
static NSArray<UICellAccessory *> *FPWithoutMultiselect(NSArray<UICellAccessory *> *accessories) {
    NSMutableArray *result=[NSMutableArray new];
    for(UICellAccessory *accessory in accessories)
        if(![accessory isKindOfClass:UICellAccessoryMultiselect.class] && ![accessory isKindOfClass:UICellAccessoryDisclosureIndicator.class]) [result addObject:accessory];
    return result;
}
static void FPSelectionVisual(UICollectionViewCell *cell, BOOL compact) {
    UIView *highlight=objc_getAssociatedObject(cell,&FPSelectionViewKey);
    if(!compact) {
        [highlight removeFromSuperview];
        objc_setAssociatedObject(cell,&FPSelectionViewKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSArray *original=objc_getAssociatedObject(cell,&FPAccessoriesKey);
        NSArray *filtered=objc_getAssociatedObject(cell,&FPFilteredAccessoriesKey);
        objc_setAssociatedObject(cell,&FPAccessoriesKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell,&FPFilteredAccessoriesKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(original && [cell isKindOfClass:UICollectionViewListCell.class] && [((UICollectionViewListCell *)cell).accessories isEqual:filtered]) ((UICollectionViewListCell *)cell).accessories=original;
        return;
    }
    if([cell isKindOfClass:UICollectionViewListCell.class]) {
        UICollectionViewListCell *list=(id)cell;
        NSArray *filtered=FPWithoutMultiselect(list.accessories);
        if(filtered.count!=list.accessories.count) {
            objc_setAssociatedObject(cell,&FPAccessoriesKey,list.accessories,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            list.accessories=filtered;
            objc_setAssociatedObject(cell,&FPFilteredAccessoriesKey,filtered,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if(!highlight) {
        highlight=[UIView new]; highlight.userInteractionEnabled=NO; highlight.isAccessibilityElement=NO;
        highlight.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [cell insertSubview:highlight belowSubview:cell.contentView];
        objc_setAssociatedObject(cell,&FPSelectionViewKey,highlight,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    highlight.frame=cell.bounds;
    highlight.backgroundColor=[cell.tintColor colorWithAlphaComponent:cell.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark ? 0.28 : 0.16];
    highlight.hidden=!cell.isSelected;
    cell.accessibilityTraits=FPSelectionTraits(cell.accessibilityTraits,cell.isSelected);
}
