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
        f.cell.reenter=YES; nativeReentry=f.cell;
        FPStyleVisibleCell(f.cell); assert(nested==0);
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
        assert(nested==0); nativeReentry=nil;
    }
    // Real event hook reuse restores the document before native reconfiguration.
    FPHookCell(UICollectionViewCell.class); FPHookCell(HookChild.class);
    FPHookCell(NSClassFromString(@"Files.DOCItemCollectionListCell"));
    NativeFixture *reused=Native(); reused.sizes[2].constant=60;
    NSLayoutConstraint *keptRatio=Ratio(reused,2.0/3.0,NO);
    reused.cell.reenter=YES; nativeReentry=reused.cell;
    FPStyleVisibleCell(reused.cell); AssertDocument(reused,2.0/3.0,20);
    parentReuse=childReuse=0; [reused.cell prepareForReuse];
    assert(parentReuse==1 && childReuse==1 && nested==0);
    assert(!objc_getAssociatedObject(reused.cell,&FPNativeStyleKey));
    assert(reused.sizes[0].constant==40 && reused.sizes[1].constant==40 && reused.sizes[2].constant==60);
    assert(keptRatio.active && reused.title.font.pointSize==17 && reused.cell.accessories.count==3);
    reused.title.text=@"Reused document.pdf"; reused.cell.cellContent=[NSObject new];
    FPStyleVisibleCell(reused.cell); AssertDocument(reused,2.0/3.0,20);
    nativeReentry=nil;
    // Slot, image, and text capabilities have separate safety gates.
    NativeFixture *f=Native(); f.sizes[2].constant=60; Ratio(f,2.0/3.0,NO);
    Constraint(f.slot,f.slot,NSLayoutAttributeWidth,f.row,NSLayoutAttributeWidth,-244);
    FPStyleVisibleCell(f.cell);
    NSDictionary *state=objc_getAssociatedObject(f.cell,&FPNativeStyleKey);
    assert(state && ![state[@"geometry"] boolValue]);
    assert(f.sizes[0].constant==40 && fabs(f.sizes[1].constant-40.0/3.0)<0.00001 && f.sizes[2].constant==20);
    assert([f.row customSpacingAfterView:f.slot]==12 && f.edges[0].constant==2 && f.title.font.pointSize==14);
    int n=nativeWrites; for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell); assert(nativeWrites==n);
    f=Native(); f.sizes[2].constant=60; Ratio(f,2.0/3.0,NO);
    Constraint(f.slot,f.image,NSLayoutAttributeWidth,f.row,NSLayoutAttributeWidth,-244);
    FPStyleVisibleCell(f.cell); state=objc_getAssociatedObject(f.cell,&FPNativeStyleKey);
    assert(state && ![state[@"geometry"] boolValue] && [state[@"constraints"] count]==0);
    assert(f.sizes[0].constant==40 && f.sizes[1].constant==40 && f.sizes[2].constant==60);
    assert(f.title.font.pointSize==14 && [f.row customSpacingAfterView:f.slot]==12);
    f=Native(); f.sizes[2].constant=60; Ratio(f,2.0/3.0,NO); f.cell.traitCollection=@3;
    FPStyleVisibleCell(f.cell); state=objc_getAssociatedObject(f.cell,&FPNativeStyleKey);
    assert([state[@"geometry"] boolValue] && [state[@"labels"] count]==0 && f.sizes[0].constant==20 && f.title.font.pointSize==17);
    n=nativeWrites; for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell); assert(nativeWrites==n);
    f=Native(); f.sizes[2].constant=60; Ratio(f,2.0/3.0,NO); f.cell.selected=NO; id background=f.cell.backgroundConfiguration;
    f.cell.bounds=CGRectMake(0,0,320,44); FPStyleVisibleCell(f.cell);
    assert(!f.cell.isSelected && f.cell.backgroundConfiguration==background && f.cell.bounds.size.height==44);
    f=Native(); f.sizes[2].constant=60; Ratio(f,2.0/3.0,NO); f.cell.bounds=CGRectMake(0,0,320,43); AssertUnsupported(f);
    // Async native ratio replacement must invalidate the cached plan even with the same pixels.
    f=Native(); NSLayoutConstraint *old=Ratio(f,2.0/3.0,NO); FPStyleVisibleCell(f.cell);
    old.active=NO; Ratio(f,1.5,YES); FPStyleVisibleCell(f.cell); AssertDocument(f,1.5,20);
    f=Native(); f.sizes[2].constant=60; Ratio(f,2.0/3.0,NO); [f.slot addSubview:[UIImageView new]];
    FPStyleVisibleCell(f.cell); AssertDocument(f,2.0/3.0,20); // Unknown image sibling is not selected or modified.
    f=Native(); object_setClass(f.image,UIImageView.class); AssertUnsupported(f);
    NativeFixture *folder=Native(); FPStyleVisibleCell(folder.cell); AssertNative(folder);
    puts("PASS independent capabilities: image-only, fonts-only, oversized-font skip, 44pt gate, unselected state, replaced native ratio, no generic UIImageView matching");
    puts("PASS documents: portrait, landscape preview, blank DOCFittingImageView, width-coupled slot, direct image slot, height-coupled slot; unchanged native ratios and selection; 1000 zero writes; restore; folder still compact");
}
