// 0.5 only resized UIListContentConfiguration; legacy DOCFittingImageView was untouched.
static char FPImageConstraintsKey, FPImageBoundsKey, FPImageCenterKey;
static void FPCompactImages(UIView *view, BOOL compact) {
    Class fitting=NSClassFromString(@"DOCFittingImageView");
    if((fitting && [view isKindOfClass:fitting]) || ([view isKindOfClass:UIImageView.class] && (objc_getAssociatedObject(view,&FPImageCenterKey) || (view.bounds.size.width>25 && view.bounds.size.height>25)))) {
        NSMutableArray *saved=objc_getAssociatedObject(view,&FPImageConstraintsKey);
        if(!compact) {
            NSValue *center=objc_getAssociatedObject(view,&FPImageCenterKey); if(center) view.center=center.CGPointValue;
            objc_setAssociatedObject(view,&FPImageCenterKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSValue *bounds=objc_getAssociatedObject(view,&FPImageBoundsKey);
            if(bounds) view.bounds=bounds.CGRectValue;
            objc_setAssociatedObject(view,&FPImageBoundsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            for(NSArray *pair in saved) ((NSLayoutConstraint *)pair[0]).constant=[pair[1] doubleValue];
            objc_setAssociatedObject(view,&FPImageConstraintsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            UIView *cell=view; while(cell && ![cell isKindOfClass:UICollectionViewCell.class]) cell=cell.superview;
            if(cell) {
                if(!objc_getAssociatedObject(view,&FPImageCenterKey)) objc_setAssociatedObject(view,&FPImageCenterKey,[NSValue valueWithCGPoint:view.center],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                CGPoint center=[view.superview convertPoint:view.center toView:cell]; center.x=16;
                view.center=[cell convertPoint:center toView:view.superview];
            }
            if(!saved) { saved=[NSMutableArray new]; objc_setAssociatedObject(view,&FPImageConstraintsKey,saved,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            // Adjust the native image's own explicit dimensions, not the row/UI scale.
            for(UIView *owner=view;owner;owner=owner.superview) {
                for(NSLayoutConstraint *c in owner.constraints) {
                    if(c.firstItem!=view || c.secondItem || c.relation!=NSLayoutRelationEqual ||
                       (c.firstAttribute!=NSLayoutAttributeWidth && c.firstAttribute!=NSLayoutAttributeHeight) || c.constant<=20) continue;
                    BOOL known=NO; for(NSArray *pair in saved) if(pair[0]==c) known=YES;
                    if(!known) [saved addObject:@[c,@(c.constant)]];
                    c.constant=20;
                }
                if([owner isKindOfClass:UICollectionViewCell.class]) break;
            }
            // shortcut: frame-based native thumbnail layout has no dimension constraints.
            // Keep its center/row geometry; change only the icon bounds (no UI transform).
            if(!saved.count && (view.bounds.size.width>20 || view.bounds.size.height>20)) {
                if(!objc_getAssociatedObject(view,&FPImageBoundsKey)) objc_setAssociatedObject(view,&FPImageBoundsKey,[NSValue valueWithCGRect:view.bounds],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                CGRect bounds=view.bounds; CGFloat ratio=MIN(20/bounds.size.width,20/bounds.size.height);
                bounds.size=CGSizeMake(bounds.size.width*ratio,bounds.size.height*ratio); view.bounds=bounds;
            }
        }
    }
    for(UIView *child in view.subviews) FPCompactImages(child,compact);
}
