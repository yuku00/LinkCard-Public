// Public margins remove inherited readable/accessory gutters after accessories are removed.
// Provider accessories keep their own native layout; never extend text over their views.
static char FPContentMarginsKey;
static void FPContentMargins(UICollectionViewCell *cell, BOOL compact) {
    NSArray *saved=objc_getAssociatedObject(cell,&FPContentMarginsKey);
    if(!compact) {
        if(saved) {
            cell.directionalLayoutMargins=[saved[0] directionalEdgeInsetsValue];
            cell.contentView.directionalLayoutMargins=[saved[1] directionalEdgeInsetsValue];
            cell.contentView.preservesSuperviewLayoutMargins=[saved[2] boolValue];
            objc_setAssociatedObject(cell,&FPContentMarginsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if(!saved) objc_setAssociatedObject(cell,&FPContentMarginsKey,@[
        [NSValue valueWithDirectionalEdgeInsets:cell.directionalLayoutMargins],
        [NSValue valueWithDirectionalEdgeInsets:cell.contentView.directionalLayoutMargins],
        @(cell.contentView.preservesSuperviewLayoutMargins)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDirectionalEdgeInsets zero=NSDirectionalEdgeInsetsMake(0,0,0,0);
    if(!NSDirectionalEdgeInsetsEqualToDirectionalEdgeInsets(cell.directionalLayoutMargins,zero)) cell.directionalLayoutMargins=zero;
    if(!NSDirectionalEdgeInsetsEqualToDirectionalEdgeInsets(cell.contentView.directionalLayoutMargins,zero)) cell.contentView.directionalLayoutMargins=zero;
    cell.contentView.preservesSuperviewLayoutMargins=NO;
}
