// 0.5 only resized UIListContentConfiguration; legacy DOCFittingImageView was untouched.
static char FPImageConstraintsKey, FPImageBoundsKey;
static void FPCompactImages(UIView *view, BOOL compact) {
    Class fitting=NSClassFromString(@"DOCFittingImageView");
    if(fitting && [view isKindOfClass:fitting]) {
        NSMutableArray *saved=objc_getAssociatedObject(view,&FPImageConstraintsKey);
        if(!compact) {
            NSValue *bounds=objc_getAssociatedObject(view,&FPImageBoundsKey);
            if(bounds) view.bounds=bounds.CGRectValue;
            objc_setAssociatedObject(view,&FPImageBoundsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            for(NSArray *pair in saved) ((NSLayoutConstraint *)pair[0]).constant=[pair[1] doubleValue];
            objc_setAssociatedObject(view,&FPImageConstraintsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            if(!saved) { saved=[NSMutableArray new]; objc_setAssociatedObject(view,&FPImageConstraintsKey,saved,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            // Adjust the native image's own explicit dimensions, not the row/UI scale.
            for(UIView *owner=view;owner;owner=owner.superview) {
                for(NSLayoutConstraint *c in owner.constraints) {
                    if(c.firstItem!=view || c.secondItem || c.relation!=NSLayoutRelationEqual ||
                       (c.firstAttribute!=NSLayoutAttributeWidth && c.firstAttribute!=NSLayoutAttributeHeight) || c.constant<=22) continue;
                    BOOL known=NO; for(NSArray *pair in saved) if(pair[0]==c) known=YES;
                    if(!known) [saved addObject:@[c,@(c.constant)]];
                    c.constant=22;
                }
                if([owner isKindOfClass:UICollectionViewCell.class]) break;
            }
            // shortcut: frame-based native thumbnail layout has no dimension constraints.
            // Keep its center/row geometry; change only the icon bounds (no UI transform).
            if(!saved.count && (view.bounds.size.width>22 || view.bounds.size.height>22)) {
                if(!objc_getAssociatedObject(view,&FPImageBoundsKey)) objc_setAssociatedObject(view,&FPImageBoundsKey,[NSValue valueWithCGRect:view.bounds],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                CGRect bounds=view.bounds; CGFloat ratio=MIN(22/bounds.size.width,22/bounds.size.height);
                bounds.size=CGSizeMake(bounds.size.width*ratio,bounds.size.height*ratio); view.bounds=bounds;
            }
        }
    }
    for(UIView *child in view.subviews) FPCompactImages(child,compact);
}
