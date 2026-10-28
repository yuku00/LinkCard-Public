// Explicit dimension fixtures, not a claim about every device/provider hierarchy.
static NSLayoutConstraint *Ratio(NativeFixture *f, CGFloat ratio, BOOL reversed) {
    NSLayoutConstraint *c=[NSLayoutConstraint constraintWithItem:f.image attribute:reversed ? NSLayoutAttributeHeight : NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:f.image attribute:reversed ? NSLayoutAttributeWidth : NSLayoutAttributeHeight multiplier:reversed ? 1/ratio : ratio constant:0];
    [f.image.constraints addObject:c]; c.active=YES; return c;
}
static CGFloat Dimension(id item, NSLayoutAttribute attr, NativeFixture *f, CGFloat width, CGFloat height, CGFloat slotWidth) {
    if(item==f.image) return attr==NSLayoutAttributeWidth ? width : height;
    assert(item==f.slot); return attr==NSLayoutAttributeWidth ? slotWidth : height;
}
static void AssertDocument(NativeFixture *f, CGFloat ratio, CGFloat slotWidth) {
    assert(objc_getAssociatedObject(f.cell,&FPNativeStyleKey));
    CGFloat w=20*MIN(1,ratio), h=20*MIN(1,1/ratio);
    // Evaluate the real planned equations, including untouched native ratio and size links.
    for(UIView *owner=f.image;owner;owner=owner.superview) {
        for(NSLayoutConstraint *c in owner.constraints) {
            if(!c.active || (c.firstItem!=f.image && c.firstItem!=f.slot) ||
               (c.firstAttribute!=NSLayoutAttributeWidth && c.firstAttribute!=NSLayoutAttributeHeight)) continue;
            CGFloat lhs=Dimension(c.firstItem,c.firstAttribute,f,w,h,slotWidth);
            CGFloat rhs=c.secondItem ? c.multiplier*Dimension(c.secondItem,c.secondAttribute,f,w,h,slotWidth)+c.constant : c.constant;
            assert(fabs(lhs-rhs)<0.00001);
        }
        if(owner==f.cell.contentView) break;
    }
    for(NSLayoutConstraint *c in f.edges) assert(c.constant==-6);
    assert([f.row customSpacingAfterView:f.slot]==6);
    assert(f.title.font.pointSize==14 && f.detail.font.pointSize==13);
    assert(f.title.numberOfLines*f.title.font.lineHeight<=f.title.bounds.size.height);
    assert(f.cell.bounds.size.height>=44 && f.cell.accessories.count==1);
    assert(f.cell.isSelected && f.cell.backgroundConfiguration.backgroundColor.alpha==0.18);
}
static void DocumentCases(void) {
    for(int variant=0;variant<6;variant++) {
        NativeFixture *f=Native(); CGFloat r=variant==1 ? 1.5 : 2.0/3.0;
        f.sizes[1].constant=40; f.sizes[2].constant=40/r;
        if(variant==2) { object_setClass(f.image,NSClassFromString(@"DOCFittingImageView")); f.image.image=nil; }
        if(variant==3) Constraint(f.slot,f.image,NSLayoutAttributeWidth,f.slot,NSLayoutAttributeWidth,0);
        if(variant==4) {
            UIView *old=f.slot; [f.row.arrangedSubviews replaceObjectAtIndex:0 withObject:f.image];
            [f.row addSubview:f.image]; [f.row.subviews removeObjectIdenticalTo:old]; old.superview=nil;
            f.slot=f.image; f.cell.thumbnailView=f.image; f.sizes[0].active=NO;
        }
        if(variant==5) {
            Constraint(f.slot,f.slot,NSLayoutAttributeHeight,nil,0,40/r);
            Constraint(f.slot,f.image,NSLayoutAttributeHeight,f.slot,NSLayoutAttributeHeight,0);
        }
        NSLayoutConstraint *ratio=Ratio(f,r,variant==1); CGFloat originalMultiplier=ratio.multiplier;
        id pixels=f.image.image; CGRect bounds=f.cell.bounds;
        FPStyleVisibleCell(f.cell);
        AssertDocument(f,r,(variant==3 || variant==4) ? 20*MIN(1,r) : 20);
        assert(ratio.active && ratio.constant==0 && ratio.multiplier==originalMultiplier);
        assert(f.image.image==pixels && CGRectEqualToRect(f.cell.bounds,bounds));
        int n=nativeWrites,a=accessoryWrites,b=backgroundWrites;
        for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell);
        assert(nativeWrites==n && accessoryWrites==a && backgroundWrites==b);
        SetScope(f.cell,NO); FPStyleVisibleCell(f.cell);
        assert(f.sizes[1].constant==40 && f.sizes[2].constant==40/r);
        assert(ratio.active && ratio.multiplier==originalMultiplier && f.cell.isSelected);
        assert([f.row customSpacingAfterView:f.slot]==12 && f.title.font.pointSize==17);
    }
    NativeFixture *folder=Native(); FPStyleVisibleCell(folder.cell); AssertNative(folder);
    puts("PASS documents: portrait, landscape preview, blank DOCFittingImageView, width-coupled slot, direct image slot, height-coupled slot; unchanged native ratios and selection; 1000 zero writes; restore; folder still compact");
}
