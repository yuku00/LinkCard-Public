// Only the known Files thumbnail and its public horizontal arranged-subview slot.
// Never shrink arbitrary UIImageViews (disclosure, status and progress accessories).
static char FPImageStateKey;
static void FPFindThumbnails(UIView *view, NSMutableArray *result) {
    Class cls=NSClassFromString(@"DOCThumbnailFittingImageView");
    if(cls && [view isKindOfClass:cls]) { [result addObject:view]; return; }
    for(UIView *child in view.subviews) FPFindThumbnails(child,result);
}
static UIView *FPThumbnailSlot(UIView *image, UIView *root) {
    for(UIView *v=image;v && v!=root;v=v.superview) {
        if([v.superview isKindOfClass:UIStackView.class]) {
            UIStackView *stack=(id)v.superview;
            if(stack.axis==UILayoutConstraintAxisHorizontal && [stack.arrangedSubviews containsObject:v]) return v;
        }
    }
    return image;
}
static BOOL FPCompactImages(UIView *root, BOOL compact) {
    NSMutableDictionary *state=objc_getAssociatedObject(root,&FPImageStateKey);
    if(!compact) {
        for(NSLayoutConstraint *c in state[@"added"]) c.active=NO;
        for(NSArray *pair in state[@"constraints"]) ((NSLayoutConstraint *)pair[0]).active=[pair[1] boolValue];
        for(NSArray *pair in state[@"spacing"]) [(UIStackView *)pair[0] setCustomSpacing:[pair[2] doubleValue] afterView:pair[1]];
        for(NSArray *pair in state[@"geometry"]) { UIView *v=pair[0]; v.bounds=[pair[1] CGRectValue]; v.center=[pair[2] CGPointValue]; }
        objc_setAssociatedObject(root,&FPImageStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return NO;
    }
    if(!state) {
        NSMutableArray *images=[NSMutableArray new]; FPFindThumbnails(root,images);
        if(!images.count) return NO;
        state=[@{@"images":images,@"constraints":[NSMutableArray new],@"added":[NSMutableArray new],@"spacing":[NSMutableArray new],@"geometry":[NSMutableArray new]} mutableCopy];
        NSMutableSet *slots=[NSMutableSet new];
        for(UIView *image in images) {
            UIView *slot=FPThumbnailSlot(image,root); [slots addObject:slot];
            for(UIView *v in (slot==image ? @[image] : @[image,slot])) {
                [state[@"geometry"] addObject:@[v,[NSValue valueWithCGRect:v.bounds],[NSValue valueWithCGPoint:v.center]]];
                // Replace explicit/proportional WIDTH sizing of this exact thumbnail slot.
                // Leave positional/height constraints and all other native controls alone.
                for(UIView *owner=v;owner;owner=owner.superview) {
                    for(NSLayoutConstraint *c in owner.constraints) {
                        if(c.active && c.firstItem==v && c.firstAttribute==NSLayoutAttributeWidth && c.relation==NSLayoutRelationEqual) {
                            [state[@"constraints"] addObject:@[c,@YES]]; c.active=NO;
                        }
                    }
                    if(owner==root) break;
                }
                if(!v.translatesAutoresizingMaskIntoConstraints) {
                    NSLayoutConstraint *width=[v.widthAnchor constraintEqualToConstant:20];
                    width.priority=999; width.active=YES; [state[@"added"] addObject:width];
                }
            }
            if([slot.superview isKindOfClass:UIStackView.class]) {
                UIStackView *stack=(id)slot.superview;
                [state[@"spacing"] addObject:@[stack,slot,@([stack customSpacingAfterView:slot])]];
                [stack setCustomSpacing:6 afterView:slot];
            }
        }
        state[@"slots"]=slots.allObjects;
        objc_setAssociatedObject(root,&FPImageStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Frame fallback after native layout; never force a synchronous layout pass.
    for(UIView *slot in state[@"slots"]) {
        CGRect b=slot.bounds; b.size.width=20; slot.bounds=b;
    }
    for(UIView *image in state[@"images"]) {
        CGRect b=image.bounds; CGFloat scale=MIN(1,MIN(20/MAX(1,b.size.width),20/MAX(1,b.size.height)));
        b.size=CGSizeMake(b.size.width*scale,b.size.height*scale); image.bounds=b;
        UIView *slot=FPThumbnailSlot(image,root);
        if(slot!=image) image.center=[slot convertPoint:CGPointMake(CGRectGetMidX(slot.bounds),CGRectGetMidY(slot.bounds)) toView:image.superview];
    }
    return [state[@"spacing"] count]>0;
}
