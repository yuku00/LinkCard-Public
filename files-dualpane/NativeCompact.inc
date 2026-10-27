// DOC's verified accessibility getters + the known horizontal thumbnail slot.
// No Swift ivar access, label-tree guessing, frame repair or layout callback.
static char FPNativeStyleKey;
static BOOL FPClassInChain(id object, NSString *name) {
    Class expected=NSClassFromString(name);
    if(!expected) return NO;
    for(Class c=object_getClass(object);c;c=class_getSuperclass(c)) if(c==expected) return YES;
    return NO;
}
static id FPNativeGet(id object, NSString *name) {
    if(!object || !ABI(object_getClass(object),name,"@@:")) return nil;
    SEL selector=NSSelectorFromString(name);
    return ((id(*)(id,SEL))[object methodForSelector:selector])(object,selector);
}
static void FPCollectKnownThumbnails(UIView *view, NSUInteger depth, NSMutableArray *matches) {
    if(matches.count>1) return;
    if(FPClassInChain(view,@"DOCThumbnailFittingImageView")) { [matches addObject:view]; return; }
    if(depth) for(UIView *child in view.subviews) FPCollectKnownThumbnails(child,depth-1,matches);
}
static UIView *FPKnownThumbnail(UIView *view, NSUInteger depth) {
    NSMutableArray *matches=[NSMutableArray new]; FPCollectKnownThumbnails(view,depth,matches);
    return matches.count==1 ? matches.firstObject : nil;
}
static UIView *FPArrangedSlot(UIView *view, UIStackView *row) {
    for(UIView *v=view;v && v!=row;v=v.superview)
        if(v.superview==row && [row.arrangedSubviews containsObject:v]) return v;
    return nil;
}
static NSInteger FPCompactNameLines(CGFloat height, CGFloat nameLine, CGFloat detailLine) {
    return height-detailLine>=2*nameLine ? 2 : 1;
}
static NSArray *FPNativeIdentity(UICollectionViewCell *cell) {
    // Missing optional getters are fine; a present but incompatible ABI is unsupported.
    for(NSString *getter in @[@"cellContent",@"accessibilityTitleLabel",@"accessibilityThumbnailView",@"accessibilitySubtitleLabel",@"accessibilityDateLabel",@"accessibilitySizeLabel"])
        if(class_getInstanceMethod(object_getClass(cell),NSSelectorFromString(getter)) && !ABI(object_getClass(cell),getter,"@@:")) return nil;
    // Object identities and text guard against reuse/reconfiguration of the same views.
    id title=FPNativeGet(cell,@"accessibilityTitleLabel");
    id thumbnail=FPNativeGet(cell,@"accessibilityThumbnailView");
    if(![title isKindOfClass:UILabel.class] || ![thumbnail isKindOfClass:UIView.class]) return nil;
    UILabel *label=title;
    UIView *image=FPKnownThumbnail(thumbnail,4), *slot=nil; UIStackView *row=nil;
    for(UIView *v=image;v && v!=cell.contentView;v=v.superview) {
        if([v.superview isKindOfClass:UIStackView.class]) {
            UIStackView *candidate=(id)v.superview;
            if(candidate.axis==UILayoutConstraintAxisHorizontal && [candidate.arrangedSubviews containsObject:v]) { slot=v; row=candidate; break; }
        }
    }
    id pixels=[image isKindOfClass:UIImageView.class] ? [(UIImageView *)image image] : nil;
    NSMutableArray *identity=[NSMutableArray arrayWithArray:@[FPNativeGet(cell,@"cellContent") ?: NSNull.null,title,thumbnail,image ?: NSNull.null,pixels ?: NSNull.null,row ?: NSNull.null,slot ?: NSNull.null]];
    NSMutableArray *strings=[NSMutableArray arrayWithObjects:[label.text copy] ?: @"",@(label.hidden),nil];
    for(NSString *getter in @[@"accessibilitySubtitleLabel",@"accessibilityDateLabel",@"accessibilitySizeLabel"]) {
        id detail=FPNativeGet(cell,getter);
        if(![detail isKindOfClass:UILabel.class]) detail=nil;
        [identity addObject:detail ?: NSNull.null]; [strings addObject:[[(UILabel *)detail text] copy] ?: @""];
        [strings addObject:@([(UILabel *)detail isHidden])];
    }
    [identity addObjectsFromArray:strings]; return identity;
}
static BOOL FPNativeIdentityMatches(NSArray *a, NSArray *b) {
    if(!a || !b || a.count!=b.count) return NO;
    for(NSUInteger i=0;i<10;i++) if(a[i]!=b[i]) return NO;
    for(NSUInteger i=10;i<a.count;i++) if(![a[i] isEqual:b[i]]) return NO;
    return YES;
}
static void FPRestoreNative(UICollectionViewCell *cell, BOOL restore) {
    NSDictionary *state=objc_getAssociatedObject(cell,&FPNativeStyleKey);
    if(!state) return;
    objc_setAssociatedObject(cell,&FPNativeStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    restore=restore && FPNativeIdentityMatches(state[@"identity"],FPNativeIdentity(cell));
    for(NSDictionary *entry in state[@"constraints"]) {
        NSLayoutConstraint *c=entry[@"target"];
        if([entry[@"added"] boolValue]) { if(c.active) c.active=NO; }
        else if(restore && c.active && c.constant==[entry[@"value"] doubleValue]) c.constant=[entry[@"original"] doubleValue];
    }
    if(!restore) return;
    UIStackView *row=state[@"row"]; UIView *slot=state[@"slot"];
    if([row customSpacingAfterView:slot]==6) [row setCustomSpacing:[state[@"spacing"] doubleValue] afterView:slot];
    for(NSDictionary *entry in state[@"labels"]) {
        UILabel *label=entry[@"target"];
        if([label.font isEqual:entry[@"font"]]) label.font=entry[@"originalFont"];
        if(label.numberOfLines==[entry[@"lines"] integerValue]) label.numberOfLines=[entry[@"originalLines"] integerValue];
        if(label.lineBreakMode==NSLineBreakByTruncatingTail) label.lineBreakMode=[entry[@"originalBreak"] integerValue];
        if(label.adjustsFontForContentSizeCategory) label.adjustsFontForContentSizeCategory=[entry[@"originalDynamic"] boolValue];
    }
}
static BOOL FPNativeStateMatches(NSDictionary *state, UICollectionViewCell *cell, NSArray *identity) {
    if(!FPNativeIdentityMatches(state[@"identity"],identity) || !CGSizeEqualToSize([state[@"size"] CGSizeValue],cell.bounds.size) ||
       [state[@"leadingMargin"] doubleValue]!=cell.contentView.directionalLayoutMargins.leading || [state[@"trailingMargin"] doubleValue]!=cell.contentView.directionalLayoutMargins.trailing ||
       ![state[@"font"] isEqual:FPCompactFont(cell,NO)] || ![state[@"detailFont"] isEqual:FPCompactFont(cell,YES)]) return NO;
    UIStackView *row=state[@"row"];
    if([row customSpacingAfterView:state[@"slot"]]!=6) return NO;
    for(NSDictionary *entry in state[@"constraints"]) {
        NSLayoutConstraint *c=entry[@"target"];
        if(!c.active || c.constant!=[entry[@"value"] doubleValue]) return NO;
    }
    for(NSDictionary *entry in state[@"labels"]) {
        UILabel *label=entry[@"target"]; UIFont *font=entry[@"font"];
        CGFloat height=MIN(label.bounds.size.height,cell.bounds.size.height-8);
        NSInteger lines=label==identity[1] ? FPCompactNameLines(height,font.lineHeight,0) : 1;
        if(height<font.lineHeight || lines!=[entry[@"lines"] integerValue] || ![label isDescendantOfView:row] ||
           ![label.font isEqual:font] || label.numberOfLines!=[entry[@"lines"] integerValue] ||
           label.lineBreakMode!=NSLineBreakByTruncatingTail || !label.adjustsFontForContentSizeCategory) return NO;
    }
    return YES;
}
// Constant sizes and equality links inside this exact thumbnail/slot pair only.
static BOOL FPPlanDimension(UIView *view, NSLayoutAttribute attribute, UIView *root, UIView *slot, UIView *image, NSMutableArray *changes) {
    if(view.translatesAutoresizingMaskIntoConstraints) return NO;
    BOOL found=NO;
    for(UIView *owner=view;owner;owner=owner.superview) {
        for(NSLayoutConstraint *c in owner.constraints) {
            if(!c.active) continue;
            BOOL first=c.firstItem==view && c.firstAttribute==attribute;
            BOOL second=c.secondItem==view && c.secondAttribute==attribute;
            if(!first && !second) continue;
            BOOL firstKnown=(c.firstAttribute==NSLayoutAttributeWidth && (c.firstItem==slot || c.firstItem==image)) || (c.firstAttribute==NSLayoutAttributeHeight && c.firstItem==image);
            BOOL secondKnown=(c.secondAttribute==NSLayoutAttributeWidth && (c.secondItem==slot || c.secondItem==image)) || (c.secondAttribute==NSLayoutAttributeHeight && c.secondItem==image);
            if(firstKnown && secondKnown && c.relation==NSLayoutRelationEqual && c.multiplier==1 && c.constant==0) continue;
            if(!first || c.secondItem || c.relation!=NSLayoutRelationEqual || c.multiplier!=1) return NO;
            found=YES;
            [changes addObject:@{@"target":c,@"original":@(c.constant),@"value":@20,@"added":@NO}];
        }
        if(owner==root) break;
    }
    if(!found) {
        NSLayoutConstraint *c=[NSLayoutConstraint constraintWithItem:view attribute:attribute relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:20];
        [changes addObject:@{@"target":c,@"original":@20,@"value":@20,@"added":@YES}];
    }
    return YES;
}
static BOOL FPPlanEdges(UIStackView *row, UIView *root, NSMutableArray *changes) {
    BOOL leading=NO,trailing=NO;
    for(UIView *owner=row;owner;owner=owner.superview) {
        for(NSLayoutConstraint *c in owner.constraints) {
            if(!c.active) continue;
            BOOL first=c.firstItem==row, second=c.secondItem==row;
            if(!first && !second) continue;
            id other=first ? c.secondItem : c.firstItem;
            NSLayoutAttribute edge=first ? c.firstAttribute : c.secondAttribute;
            NSLayoutAttribute otherEdge=first ? c.secondAttribute : c.firstAttribute;
            // A fixed/foreign horizontal link may conflict with the new insets. Do not guess.
            if(edge==NSLayoutAttributeWidth || edge==NSLayoutAttributeLeft || edge==NSLayoutAttributeRight) return NO;
            if(edge!=NSLayoutAttributeLeading && edge!=NSLayoutAttributeTrailing) continue;
            if(edge!=otherEdge || c.relation!=NSLayoutRelationEqual || c.multiplier!=1 ||
               (other!=root && other!=root.layoutMarginsGuide)) return NO;
            CGFloat inset=10;
            if(other==root.layoutMarginsGuide) inset-=edge==NSLayoutAttributeLeading ? root.directionalLayoutMargins.leading : root.directionalLayoutMargins.trailing;
            CGFloat value=(edge==NSLayoutAttributeLeading ? inset : -inset)*(first ? 1 : -1);
            [changes addObject:@{@"target":c,@"original":@(c.constant),@"value":@(value),@"added":@NO}];
            if(edge==NSLayoutAttributeLeading) leading=YES; else trailing=YES;
        }
        if(owner==root) break;
    }
    return leading && trailing;
}
static BOOL FPCompactNative(UICollectionViewCell *cell, BOOL compact) {
    NSDictionary *saved=objc_getAssociatedObject(cell,&FPNativeStyleKey);
    if(!compact) { FPRestoreNative(cell,YES); return NO; }
    UICollectionView *collection=nil;
    for(UIView *v=cell.superview;v;v=v.superview) if([v isKindOfClass:UICollectionView.class]) { collection=(id)v; break; }
    // Sidebar deliberately uses only its reliable public configuration, never DOC slot surgery.
    if(!FPClassInChain(collection.delegate,@"Files.DOCItemCollectionViewController") || FPClassInChain(collection.delegate,@"Files.DOCSidebarViewController")) {
        FPRestoreNative(cell,YES); return NO;
    }
    if(!FPClassInChain(cell,@"Files.DOCItemCollectionListCell") && !FPClassInChain(cell,@"Files.DOCItemCollectionCell")) return NO;
    BOOL hasRenaming=class_getInstanceMethod(object_getClass(cell),NSSelectorFromString(@"accessibilityIsRenaming"))!=NULL;
    if(hasRenaming && (!ABI(object_getClass(cell),@"accessibilityIsRenaming","B@:") ||
       ((BOOL(*)(id,SEL))[cell methodForSelector:NSSelectorFromString(@"accessibilityIsRenaming")])(cell,NSSelectorFromString(@"accessibilityIsRenaming")))) {
        FPRestoreNative(cell,YES); return NO;
    }
    NSArray *identity=FPNativeIdentity(cell);
    if(saved && FPNativeStateMatches(saved,cell,identity)) return YES;
    if(saved) FPRestoreNative(cell,YES);
    if(!identity) return NO;
    UIView *root=cell.contentView, *image=identity[3]==NSNull.null ? nil : identity[3];
    UILabel *title=identity[1];
    if(!image || ![image isDescendantOfView:root] || ![title isDescendantOfView:root]) return NO;
    UIView *slot=identity[6]==NSNull.null ? nil : identity[6];
    UIStackView *row=identity[5]==NSNull.null ? nil : identity[5];
    UIView *textSlot=FPArrangedSlot(title,row);
    if(!row || !textSlot || [row.arrangedSubviews indexOfObjectIdenticalTo:textSlot]!=[row.arrangedSubviews indexOfObjectIdenticalTo:slot]+1 ||
       row.distribution!=UIStackViewDistributionFill || cell.bounds.size.height<28 ||
       (row.layoutMarginsRelativeArrangement && (row.directionalLayoutMargins.leading!=0 || row.directionalLayoutMargins.trailing!=0))) return NO;
    UIFont *font=FPCompactFont(cell,NO), *detail=FPCompactFont(cell,YES);
    NSMutableArray *labels=[NSMutableArray new]; NSMutableArray *targets=[NSMutableArray arrayWithObject:title];
    for(NSString *getter in @[@"accessibilitySubtitleLabel",@"accessibilityDateLabel",@"accessibilitySizeLabel"]) {
        id label=FPNativeGet(cell,getter);
        if([label isKindOfClass:UILabel.class] && [label isDescendantOfView:row] && ![targets containsObject:label]) [targets addObject:label];
    }
    for(UILabel *label in targets) {
        if(label.hidden || !label.text.length) continue;
        UIFont *targetFont=label==title ? font : detail;
        CGFloat height=MIN(label.bounds.size.height,cell.bounds.size.height-8);
        // Fixed native rows must actually fit their chosen line count; do not force self-sizing.
        if(height<targetFont.lineHeight || label.bounds.size.width<=0) return NO;
        NSInteger lines=label==title ? FPCompactNameLines(height,targetFont.lineHeight,0) : 1;
        [labels addObject:@{@"target":label,@"originalFont":label.font,@"font":targetFont,@"originalLines":@(label.numberOfLines),@"lines":@(lines),
            @"originalBreak":@(label.lineBreakMode),@"originalDynamic":@(label.adjustsFontForContentSizeCategory)}];
    }
    if(!labels.count) return NO;
    NSMutableArray *constraints=[NSMutableArray new];
    if(!FPPlanDimension(slot,NSLayoutAttributeWidth,root,slot,image,constraints) ||
       (image!=slot && !FPPlanDimension(image,NSLayoutAttributeWidth,root,slot,image,constraints)) ||
       !FPPlanDimension(image,NSLayoutAttributeHeight,root,slot,image,constraints) || !FPPlanEdges(row,root,constraints)) return NO;
    NSDictionary *state=@{@"identity":identity,@"row":row,@"slot":slot,@"spacing":@([row customSpacingAfterView:slot]),
        @"constraints":constraints,@"labels":labels,@"size":[NSValue valueWithCGSize:cell.bounds.size],@"font":font,@"detailFont":detail,
        @"leadingMargin":@(root.directionalLayoutMargins.leading),@"trailingMargin":@(root.directionalLayoutMargins.trailing)};
    // Commit the entire plan BEFORE any native layout setter can reenter configuration.
    objc_setAssociatedObject(cell,&FPNativeStyleKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for(NSDictionary *entry in constraints) {
        NSLayoutConstraint *c=entry[@"target"];
        if([entry[@"added"] boolValue]) { c.priority=999; c.active=YES; }
        else if(c.constant!=[entry[@"value"] doubleValue]) c.constant=[entry[@"value"] doubleValue];
    }
    if([row customSpacingAfterView:slot]!=6) [row setCustomSpacing:6 afterView:slot];
    for(NSDictionary *entry in labels) {
        UILabel *label=entry[@"target"];
        if(![label.font isEqual:entry[@"font"]]) label.font=entry[@"font"];
        if(label.numberOfLines!=[entry[@"lines"] integerValue]) label.numberOfLines=[entry[@"lines"] integerValue];
        if(label.lineBreakMode!=NSLineBreakByTruncatingTail) label.lineBreakMode=NSLineBreakByTruncatingTail;
        if(!label.adjustsFontForContentSizeCategory) label.adjustsFontForContentSizeCategory=YES;
    }
    return YES;
}
