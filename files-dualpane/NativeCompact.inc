#include <math.h>
// DOC's verified accessibility getters + the known horizontal thumbnail slot.
// No Swift ivar access, label-tree guessing, frame repair or layout callback.
static char FPNativeStyleKey, FPNativeReadyKey, FPLayoutDecisionKey;
static NSMutableDictionary *FPLayoutDecision;
static BOOL FPLayoutReject(NSString *stage, NSString *reason) {
    if(FPLayoutDecision && !FPLayoutDecision[stage]) FPLayoutDecision[stage]=reason;
    return NO;
}
static void FPStyleVisibleCell(UICollectionViewCell *cell);
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
    if(FPClassInChain(view,@"DOCThumbnailFittingImageView") || FPClassInChain(view,@"DOCFittingImageView")) { [matches addObject:view]; return; }
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
        else if([entry[@"disabled"] boolValue]) { if(restore && !c.active && c.constant==[entry[@"value"] doubleValue]) c.active=YES; }
        else if(restore && c.active && c.constant==[entry[@"value"] doubleValue]) c.constant=[entry[@"original"] doubleValue];
    }
    if(!restore) return;
    UIStackView *row=state[@"row"]; UIView *slot=state[@"slot"];
    if([state[@"geometry"] boolValue] && [row customSpacingAfterView:slot]==6) [row setCustomSpacing:[state[@"spacing"] doubleValue] afterView:slot];
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
       ![state[@"font"] isEqual:FPCompactFont(cell,NO)] || ![state[@"detailFont"] isEqual:FPCompactFont(cell,YES)]) return FPLayoutReject(@"cacheMiss",@"FPNativeStateMatches_01");
    for(UIView *view in state[@"pendingViews"]) if(view.bounds.size.width>0 && view.bounds.size.height>0) return FPLayoutReject(@"cacheMiss",@"FPNativeStateMatches_02");
    if([state[@"trailing"] boolValue]) {
        if(cell.contentView.effectiveUserInterfaceLayoutDirection!=UIUserInterfaceLayoutDirectionLeftToRight) return FPLayoutReject(@"cacheMiss",@"FPNativeStateMatches_03");
        NSArray *accessories=[cell isKindOfClass:UICollectionViewListCell.class] ? [(UICollectionViewListCell *)cell accessories] : @[];
        if(![state[@"accessories"] isEqual:accessories]) return FPLayoutReject(@"cacheMiss",@"FPNativeStateMatches_04");
        for(NSDictionary *entry in state[@"watch"]) {
            UIStackView *stack=entry[@"stack"];
            if(stack) { if(stack.axis!=UILayoutConstraintAxisVertical || stack.alignment!=UIStackViewAlignmentFill || stack.layoutMarginsRelativeArrangement) return FPLayoutReject(@"cacheMiss",@"FPNativeStateMatches_05"); continue; }
            NSLayoutConstraint *c=entry[@"target"];
            if(!c.active || c.firstItem!=entry[@"first"] || (c.secondItem ?: NSNull.null)!=entry[@"second"] || c.constant!=[entry[@"constant"] doubleValue] || c.multiplier!=1 || c.relation!=NSLayoutRelationEqual) return FPLayoutReject(@"cacheMiss",@"FPNativeStateMatches_06");
        }
    }
    UIStackView *row=state[@"row"];
    if([state[@"geometry"] boolValue] && [row customSpacingAfterView:state[@"slot"]]!=6) return FPLayoutReject(@"cacheMiss",@"FPNativeStateMatches_07");
    for(NSDictionary *entry in state[@"constraints"]) {
        NSLayoutConstraint *c=entry[@"target"];
        if(c.active==[entry[@"disabled"] boolValue] || c.constant!=[entry[@"value"] doubleValue]) return FPLayoutReject(@"cacheMiss",@"FPNativeStateMatches_08");
    }
    for(NSDictionary *entry in state[@"labels"]) {
        UILabel *label=entry[@"target"]; UIFont *font=entry[@"font"];
        CGFloat height=MIN(label.bounds.size.height,cell.bounds.size.height-8);
        NSInteger lines=label==identity[1] ? FPCompactNameLines(height,font.lineHeight,0) : 1;
        if(height<font.lineHeight || lines!=[entry[@"lines"] integerValue] || ![label isDescendantOfView:row] ||
           ![label.font isEqual:font] || label.numberOfLines!=[entry[@"lines"] integerValue] ||
           label.lineBreakMode!=NSLineBreakByTruncatingTail || !label.adjustsFontForContentSizeCategory) return FPLayoutReject(@"cacheMiss",@"FPNativeStateMatches_09");
    }
    return YES;
}
// Constant sizes and equality links inside this exact thumbnail/slot pair only.
static BOOL FPPlanDimension(UIView *view, NSLayoutAttribute attribute, UIView *root, UIView *slot, UIView *image, NSMutableArray *changes) {
    if(view.translatesAutoresizingMaskIntoConstraints) return FPLayoutReject(@"geometryReject",@"FPPlanDimension_01");
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
            if(!first || c.secondItem || c.relation!=NSLayoutRelationEqual || c.multiplier!=1) return FPLayoutReject(@"geometryReject",@"FPPlanDimension_02");
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
// Only the evidenced fitting image's own width/height ratio is authoritative.
static CGFloat FPDocumentAspect(UIView *image, UIView *root) {
    CGFloat ratio=0;
    for(UIView *owner=image;owner;owner=owner.superview) {
        for(NSLayoutConstraint *c in owner.constraints) {
            if(!c.active || c.firstItem!=image || c.secondItem!=image ||
               !((c.firstAttribute==NSLayoutAttributeWidth && c.secondAttribute==NSLayoutAttributeHeight) ||
                 (c.firstAttribute==NSLayoutAttributeHeight && c.secondAttribute==NSLayoutAttributeWidth))) continue;
            if(c.relation!=NSLayoutRelationEqual || c.constant!=0 || !isfinite(c.multiplier) || c.multiplier<=0) return 0;
            CGFloat value=c.firstAttribute==NSLayoutAttributeWidth ? c.multiplier : 1/c.multiplier;
            if(ratio && fabs(ratio-value)>0.000001) return 0;
            ratio=value;
        }
        if(owner==root) break;
    }
    return ratio;
}
static CGFloat FPDocumentDimension(id item, NSLayoutAttribute attribute, UIView *slot, UIView *image, CGSize fitted, CGSize slotSize, BOOL slotHeight) {
    if(attribute!=NSLayoutAttributeWidth && attribute!=NSLayoutAttributeHeight) return -1;
    if(item==image) return attribute==NSLayoutAttributeWidth ? fitted.width : fitted.height;
    if(item==slot && (attribute==NSLayoutAttributeWidth || slotHeight)) return attribute==NSLayoutAttributeWidth ? slotSize.width : slotSize.height;
    return -1;
}
static BOOL FPPlanDocumentDimensions(UIView *root, UIView *slot, UIView *image, CGFloat ratio, NSMutableArray *changes) {
    if(!ratio || slot.translatesAutoresizingMaskIntoConstraints || image.translatesAutoresizingMaskIntoConstraints) return FPLayoutReject(@"geometryReject",@"FPPlanDocumentDimensions_01");
    CGSize fitted=CGSizeMake(20*MIN(1,ratio),20*MIN(1,1/ratio)), slotSize=CGSizeMake(20,20);
    BOOL slotHeight=NO;
    NSMutableArray *links=[NSMutableArray new];
    for(UIView *owner=image;owner;owner=owner.superview) {
        for(NSLayoutConstraint *c in owner.constraints) {
            if(!c.active) continue;
            if((c.firstItem==slot && c.secondItem==image) || (c.firstItem==image && c.secondItem==slot)) {
                if(c.relation==NSLayoutRelationEqual && c.multiplier==1 && c.constant==0 && c.firstAttribute==c.secondAttribute) {
                    if(c.firstAttribute==NSLayoutAttributeWidth) slotSize.width=fitted.width;
                    if(c.firstAttribute==NSLayoutAttributeHeight) { slotSize.height=fitted.height; slotHeight=YES; }
                }
            }
            [links addObject:c];
        }
        if(owner==root) break;
    }
    // Plan the image and its coupled slot together; never squeeze a slot around an unshrinkable image.
    NSMutableArray *dimensions=[NSMutableArray arrayWithObjects:@[image,@(NSLayoutAttributeWidth),@(fitted.width)],@[image,@(NSLayoutAttributeHeight),@(fitted.height)],nil];
    if(slot!=image) {
        [dimensions addObject:@[slot,@(NSLayoutAttributeWidth),@(slotSize.width)]];
        if(slotHeight) [dimensions addObject:@[slot,@(NSLayoutAttributeHeight),@(slotSize.height)]];
    }
    NSMutableSet *fixed=[NSMutableSet new];
    for(NSLayoutConstraint *c in links) {
        CGFloat first=FPDocumentDimension(c.firstItem,c.firstAttribute,slot,image,fitted,slotSize,slotHeight);
        CGFloat second=FPDocumentDimension(c.secondItem,c.secondAttribute,slot,image,fitted,slotSize,slotHeight);
        if(first<0 && second<0) continue;
        if(c.relation!=NSLayoutRelationEqual || !isfinite(c.multiplier) || c.multiplier<=0) return FPLayoutReject(@"geometryReject",@"FPPlanDocumentDimensions_02");
        if(first>=0 && !c.secondItem && c.multiplier==1) {
            [changes addObject:@{@"target":c,@"original":@(c.constant),@"value":@(first),@"added":@NO}];
            [fixed addObject:@[c.firstItem,@(c.firstAttribute)]];
        } else if(first>=0 && second>=0 && c.constant==0 && fabs(first-c.multiplier*second)<0.000001) {
            // Retain and watch the native aspect/equality constraint; never deactivate it.
            [changes addObject:@{@"target":c,@"original":@0,@"value":@0,@"added":@NO}];
        } else return FPLayoutReject(@"geometryReject",@"FPPlanDocumentDimensions_03");
    }
    for(NSArray *dimension in dimensions) {
        UIView *view=dimension[0]; NSLayoutAttribute attribute=[dimension[1] integerValue];
        if([fixed containsObject:@[view,@(attribute)]]) continue;
        NSLayoutConstraint *c=[NSLayoutConstraint constraintWithItem:view attribute:attribute relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:[dimension[2] doubleValue]];
        [changes addObject:@{@"target":c,@"original":dimension[2],@"value":dimension[2],@"added":@YES}];
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
            if(edge==NSLayoutAttributeWidth || edge==NSLayoutAttributeLeft || edge==NSLayoutAttributeRight) return FPLayoutReject(@"geometryReject",@"FPPlanEdges_01");
            if(edge!=NSLayoutAttributeLeading && edge!=NSLayoutAttributeTrailing) continue;
            // Stack-to-arranged-child edges are internal, not competing outer insets.
            if(owner==row && [other isKindOfClass:UIView.class] && [(UIView *)other isDescendantOfView:row]) continue;
            if(edge!=otherEdge || c.relation!=NSLayoutRelationEqual || c.multiplier!=1 ||
               (other!=root && other!=root.layoutMarginsGuide)) return FPLayoutReject(@"geometryReject",@"FPPlanEdges_02");
            CGFloat inset=10;
            if(other==root.layoutMarginsGuide) inset-=edge==NSLayoutAttributeLeading ? root.directionalLayoutMargins.leading : root.directionalLayoutMargins.trailing;
            CGFloat value=(edge==NSLayoutAttributeLeading ? inset : -inset)*(first ? 1 : -1);
            [changes addObject:@{@"target":c,@"original":@(c.constant),@"value":@(value),@"added":@NO}];
            if(edge==NSLayoutAttributeLeading) leading=YES; else trailing=YES;
        }
        if(owner==root) break;
    }
    if(!leading || !trailing) return FPLayoutReject(@"geometryReject",@"FPPlanEdges_missing_edge");
    return YES;
}
// Text plans touch only getter-identified labels and their arranged slot.
static BOOL FPTrailingAttribute(NSLayoutAttribute a) {
    return a==NSLayoutAttributeTrailing || a==NSLayoutAttributeRight;
}
static BOOL FPTextWidthPlan(UIView *view, UIView *root, NSArray *known, NSMutableArray *changes) {
    for(UIView *owner=view;owner;owner=owner.superview) {
        for(NSLayoutConstraint *c in owner.constraints) {
            if(!c.active) continue;
            BOOL first=c.firstItem==view && c.firstAttribute==NSLayoutAttributeWidth;
            BOOL second=c.secondItem==view && c.secondAttribute==NSLayoutAttributeWidth;
            if(!first && !second) continue;
            if(![known containsObject:view] || !first || c.secondItem || c.multiplier!=1 ||
               (c.relation!=NSLayoutRelationEqual && c.relation!=NSLayoutRelationLessThanOrEqual) || !isfinite(c.constant)) return FPLayoutReject(@"trailingReject",@"FPTextWidthPlan_01");
            BOOL found=NO; for(NSDictionary *e in changes) if(e[@"target"]==c) found=YES;
            if(!found) [changes addObject:@{@"target":c,@"original":@(c.constant),@"value":@(c.constant),@"added":@NO,@"disabled":@YES}];
        }
        if(owner==root) break;
    }
    return YES;
}
static BOOL FPTrailingAncestor(id item, id other, UIView *root) {
    UIView *view=[item isKindOfClass:UILayoutGuide.class] ? [(UILayoutGuide *)item owningView] : item;
    if(![view isKindOfClass:UIView.class]) return NO;
    if([other isKindOfClass:UILayoutGuide.class]) {
        UIView *owner=[(UILayoutGuide *)other owningView];
        return owner && (owner==view || [view isDescendantOfView:owner]) && (owner==root || [owner isDescendantOfView:root]);
    }
    return [other isKindOfClass:UIView.class] && other!=item && [view isDescendantOfView:other] && (other==root || [(UIView *)other isDescendantOfView:root]);
}
static BOOL FPTrailingPath(id item, UIView *stop, UIView *root, NSArray *known, NSMutableArray *changes, NSMutableArray *path, CGFloat *offset, CGFloat *reservation, NSUInteger depth) {
    if(item==stop) { *offset=0; return YES; }
    if(item==stop.layoutMarginsGuide) { *offset=-stop.directionalLayoutMargins.trailing; return YES; }
    if(!depth) return FPLayoutReject(@"trailingReject",@"FPTrailingPath_01");
    UIView *view=[item isKindOfClass:UILayoutGuide.class] ? [(UILayoutGuide *)item owningView] : item;
    if(![view isKindOfClass:UIView.class] || (view!=root && ![view isDescendantOfView:root])) return FPLayoutReject(@"trailingReject",@"FPTrailingPath_02");
    if(item==view && !FPTextWidthPlan(view,root,known,changes)) return FPLayoutReject(@"trailingReject",@"FPTrailingPath_03");
    NSLayoutConstraint *edge=nil; id next=nil; CGFloat sign=0; BOOL provider=NO, siblingEdge=NO;
    for(UIView *owner=view;owner;owner=owner.superview) {
        for(NSLayoutConstraint *c in owner.constraints) {
            if(!c.active) continue;
            BOOL first=c.firstItem==item, second=c.secondItem==item;
            if(!first && !second) continue;
            NSLayoutAttribute a=first ? c.firstAttribute : c.secondAttribute;
            if(!FPTrailingAttribute(a)) continue;
            BOOL traversed=NO; for(NSDictionary *link in path) if(link[@"target"]==c) traversed=YES;
            if(traversed) continue;
            id other=first ? c.secondItem : c.firstItem;
            NSLayoutAttribute otherEdge=first ? c.secondAttribute : c.firstAttribute;
            if([item isKindOfClass:UIView.class] && [other isKindOfClass:UIView.class] && [(UIView *)other isDescendantOfView:item]) continue;
            BOOL sibling=[known containsObject:item] && [known containsObject:other] && [other isKindOfClass:UIView.class] && [(UIView *)other superview]==view.superview;
            BOOL tail=NO;
            if([known containsObject:item] && [other isKindOfClass:UIView.class] && [view.superview isKindOfClass:UIStackView.class]) {
                UIStackView *stack=(id)view.superview;
                NSUInteger i=[stack.arrangedSubviews indexOfObjectIdenticalTo:view], j=[stack.arrangedSubviews indexOfObjectIdenticalTo:other];
                tail=stack.axis==UILayoutConstraintAxisHorizontal && i!=NSNotFound && j!=NSNotFound && j>i && (otherEdge==NSLayoutAttributeLeading || otherEdge==NSLayoutAttributeLeft);
            }
            if((!FPTrailingAncestor(item,other,root) && !sibling && !tail) ||
               (!FPTrailingAttribute(otherEdge) && !tail) || c.relation!=NSLayoutRelationEqual || c.multiplier!=1) return FPLayoutReject(@"trailingReject",@"FPTrailingPath_04");
            if(sibling && !tail && c.constant!=0) return FPLayoutReject(@"trailingReject",@"FPTrailingPath_05");
            if(edge && sibling && !siblingEdge) continue;
            if(edge && !(siblingEdge && !sibling)) return FPLayoutReject(@"trailingReject",@"FPTrailingPath_06");
            edge=c; next=other; sign=first ? 1 : -1; provider=tail; siblingEdge=sibling;
        }
        if(owner==root) break;
    }
    if(!edge) {
        // UIKit owns fill alignment; no manufactured label constraints or stack mutation.
        UIStackView *stack=[view.superview isKindOfClass:UIStackView.class] ? (id)view.superview : nil;
        if(item!=view || ![known containsObject:item] || stack.axis!=UILayoutConstraintAxisVertical || stack.alignment!=UIStackViewAlignmentFill ||
           ![stack.arrangedSubviews containsObject:view] || stack.layoutMarginsRelativeArrangement) return FPLayoutReject(@"trailingReject",@"FPTrailingPath_07");
        [path addObject:@{@"stack":stack}];
        return FPTrailingPath(stack,stop,root,known,changes,path,offset,reservation,depth-1);
    }
    [path addObject:@{@"target":edge,@"sign":@(sign),@"sibling":@(siblingEdge)}];
    CGFloat rest=0;
    if(provider) {
        // A real trailing arranged provider: prove its own width and root/row edge.
        NSLayoutConstraint *width=nil;
        for(UIView *owner=next;owner;owner=owner.superview) {
            for(NSLayoutConstraint *c in owner.constraints) {
                if(!c.active || c.firstItem!=next || c.firstAttribute!=NSLayoutAttributeWidth) continue;
                if(width || c.secondItem || c.relation!=NSLayoutRelationEqual || c.multiplier!=1 || !isfinite(c.constant) || c.constant<=0) return FPLayoutReject(@"trailingReject",@"FPTrailingPath_08");
                width=c;
            }
            if(owner==root) break;
        }
        if(!width) return FPLayoutReject(@"trailingReject",@"FPTrailingPath_09");
        NSMutableArray *providerPath=[NSMutableArray new], *unused=[NSMutableArray new]; CGFloat reserve=0;
        // Width belongs to the provider and is watched, never released.
        NSArray *providerKnown=@[next];
        if(!FPTrailingPath(next,stop,root,providerKnown,unused,providerPath,&rest,&reserve,depth-1) || reserve) return FPLayoutReject(@"trailingReject",@"FPTrailingPath_10");
        for(NSDictionary *link in providerPath) if(link[@"target"]) [path addObject:@{@"target":link[@"target"],@"provider":@YES}];
        [path addObject:@{@"target":width,@"provider":@YES}];
        rest-=width.constant; *reservation=rest;
    } else if(!FPTrailingPath(next,stop,root,known,changes,path,&rest,reservation,depth-1)) return FPLayoutReject(@"trailingReject",@"FPTrailingPath_11");
    *offset=sign*edge.constant+rest; return YES;
}
static void FPTrailingChange(NSMutableArray *changes, NSLayoutConstraint *c, CGFloat value) {
    for(NSUInteger i=0;i<changes.count;i++) if(changes[i][@"target"]==c) {
        NSMutableDictionary *entry=[changes[i] mutableCopy]; entry[@"value"]=@(value); changes[i]=entry; return;
    }
    [changes addObject:@{@"target":c,@"original":@(c.constant),@"value":@(value),@"added":@NO}];
}
static BOOL FPPlanTrailing(UICollectionViewCell *cell, UIStackView *row, UIView *textSlot, NSMutableArray *changes, NSMutableArray *watch) {
    UIView *root=cell.contentView;
    // Physical right and directional trailing are equivalent only in this supported direction.
    if(root.effectiveUserInterfaceLayoutDirection!=UIUserInterfaceLayoutDirectionLeftToRight) return FPLayoutReject(@"trailingReject",@"FPPlanTrailing_01");
    NSMutableArray *known=[NSMutableArray arrayWithObject:textSlot];
    for(NSString *getter in @[@"accessibilityTitleLabel",@"accessibilitySubtitleLabel",@"accessibilityDateLabel",@"accessibilitySizeLabel"]) {
        id label=FPNativeGet(cell,getter);
        if([label isKindOfClass:UILabel.class] && ![(UILabel *)label isHidden] && [label isDescendantOfView:textSlot] && ![known containsObject:label]) [known addObject:label];
    }
    BOOL accessories=[cell isKindOfClass:UICollectionViewListCell.class] && [(UICollectionViewListCell *)cell accessories].count;
    NSMutableArray *items=[NSMutableArray arrayWithObjects:row,textSlot,nil];
    for(id label in known) if(label!=textSlot) [items addObject:label];
    for(id item in items) {
        UIView *stop=item==row ? root : item==textSlot ? row : textSlot;
        NSMutableArray *path=[NSMutableArray new], *local=[NSMutableArray new]; CGFloat offset=0, reservation=0;
        if(!FPTrailingPath(item,stop,root,known,local,path,&offset,&reservation,8)) {
            if(item==row || item==textSlot) return FPLayoutReject(@"trailingReject",@"FPPlanTrailing_02");
            continue; // One unsupported optional label does not reject a verified title.
        }
        // A later arranged item needs a proved provider.leading boundary, not row.trailing.
        if(item==textSlot && row.arrangedSubviews.lastObject!=textSlot && !reservation) return FPLayoutReject(@"trailingReject",@"FPPlanTrailing_03");
        NSDictionary *first=nil; for(NSDictionary *link in path) if(link[@"target"]) { first=link; break; }
        if(first) {
            NSLayoutConstraint *c=first[@"target"]; CGFloat sign=[first[@"sign"] doubleValue];
            CGFloat target=item==row ? -10 : 0;
            id boundary=sign==1 ? c.secondItem : c.firstItem;
            if([first[@"sibling"] boolValue]) target=offset-sign*c.constant;
            if(reservation) target=reservation-10;
            else if(item==row && accessories && [boundary isKindOfClass:UILayoutGuide.class] && boundary!=root.layoutMarginsGuide)
                target += offset-sign*c.constant;
            FPTrailingChange(local,c,c.constant+(target-offset)/sign);
        }
        for(NSDictionary *entry in local) {
            BOOL found=NO; for(NSDictionary *old in changes) if(old[@"target"]==entry[@"target"]) found=YES;
            if(!found) [changes addObject:entry];
        }
        for(NSDictionary *link in path) {
            if(link[@"stack"]) { [watch addObject:link]; continue; }
            NSLayoutConstraint *c=link[@"target"];
            [watch addObject:@{@"target":c,@"first":c.firstItem,@"second":c.secondItem ?: NSNull.null,@"constant":@(c.constant)}];
        }
    }
    return YES;
}

static void FPNativeReadyOnce(UICollectionViewCell *cell, NSArray *identity) {
    NSDictionary *old=objc_getAssociatedObject(cell,&FPNativeReadyKey);
    if(FPNativeIdentityMatches(old[@"identity"],identity)) return;
    NSDictionary *ticket=@{@"identity":identity};
    objc_setAssociatedObject(cell,&FPNativeReadyKey,ticket,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UICollectionViewCell *weakCell=cell;
    dispatch_async(dispatch_get_main_queue(), ^{
        UICollectionViewCell *live=weakCell;
        if(!live || objc_getAssociatedObject(live,&FPNativeReadyKey)!=ticket || !FPNativeIdentityMatches(identity,FPNativeIdentity(live))) return;
        // Ordinary scope/selection/reentry gates still own the retry. No recursive dispatch.
        FPStyleVisibleCell(live);
    });
}
static BOOL FPCompactNativeObserved(UICollectionViewCell *cell, BOOL compact) {
    NSDictionary *saved=objc_getAssociatedObject(cell,&FPNativeStyleKey);
    if(!compact) { objc_setAssociatedObject(cell,&FPNativeReadyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); FPRestoreNative(cell,YES); return FPLayoutReject(@"nativeGate",@"FPCompactNative_01"); }
    UICollectionView *collection=nil;
    for(UIView *v=cell.superview;v;v=v.superview) if([v isKindOfClass:UICollectionView.class]) { collection=(id)v; break; }
    // Sidebar deliberately uses only its reliable public configuration, never DOC slot surgery.
    if(!FPClassInChain(collection.delegate,@"Files.DOCItemCollectionViewController") || FPClassInChain(collection.delegate,@"Files.DOCSidebarViewController")) {
        FPRestoreNative(cell,YES); return FPLayoutReject(@"nativeGate",@"FPCompactNative_02");
    }
    if(!FPClassInChain(cell,@"Files.DOCItemCollectionListCell") && !FPClassInChain(cell,@"Files.DOCItemCollectionCell")) return FPLayoutReject(@"nativeGate",@"FPCompactNative_03");
    BOOL hasRenaming=class_getInstanceMethod(object_getClass(cell),NSSelectorFromString(@"accessibilityIsRenaming"))!=NULL;
    if(hasRenaming && (!ABI(object_getClass(cell),@"accessibilityIsRenaming","B@:") ||
       ((BOOL(*)(id,SEL))[cell methodForSelector:NSSelectorFromString(@"accessibilityIsRenaming")])(cell,NSSelectorFromString(@"accessibilityIsRenaming")))) {
        FPRestoreNative(cell,YES); return FPLayoutReject(@"nativeGate",@"FPCompactNative_04");
    }
    NSArray *identity=FPNativeIdentity(cell);
    if(FPLayoutDecision) FPLayoutDecision[@"cache"] = saved ? @"miss" : @"absent";
    if(saved && FPNativeStateMatches(saved,cell,identity)) {
        if(FPLayoutDecision) { FPLayoutDecision[@"cache"]=@"hit_identity_size_margins_fonts_pending_watch_constraints_labels";
            FPLayoutDecision[@"trailing"]=@"cached_not_replanned"; FPLayoutDecision[@"geometry"]=@"cached_not_replanned";
            FPLayoutDecision[@"pending"]= [saved[@"textPending"] boolValue] ? @"cached_zero_bounds" : @"ready"; }
        return YES;
    }
    if(saved) FPRestoreNative(cell,YES);
    if(!identity) return FPLayoutReject(@"nativeGate",@"FPCompactNative_05");
    UIView *root=cell.contentView, *image=identity[3]==NSNull.null ? nil : identity[3];
    UILabel *title=identity[1];
    if(!image || ![image isDescendantOfView:root] || ![title isDescendantOfView:root]) return FPLayoutReject(@"nativeGate",@"FPCompactNative_06");
    UIView *slot=identity[6]==NSNull.null ? nil : identity[6];
    UIStackView *row=identity[5]==NSNull.null ? nil : identity[5];
    UIView *textSlot=FPArrangedSlot(title,row);
    if(!row || !textSlot || [row.arrangedSubviews indexOfObjectIdenticalTo:textSlot]!=[row.arrangedSubviews indexOfObjectIdenticalTo:slot]+1 ||
       row.distribution!=UIStackViewDistributionFill || cell.bounds.size.height<44 ||
       (row.layoutMarginsRelativeArrangement && (row.directionalLayoutMargins.leading!=0 || row.directionalLayoutMargins.trailing!=0))) return FPLayoutReject(@"nativeGate",@"FPCompactNative_07");
    CGFloat documentAspect=FPDocumentAspect(image,root);
    UIFont *font=FPCompactFont(cell,NO), *detail=FPCompactFont(cell,YES);
    NSMutableArray *labels=[NSMutableArray new]; NSMutableArray *targets=[NSMutableArray arrayWithObject:title];
    for(NSString *getter in @[@"accessibilitySubtitleLabel",@"accessibilityDateLabel",@"accessibilitySizeLabel"]) {
        id label=FPNativeGet(cell,getter);
        if([label isKindOfClass:UILabel.class] && [label isDescendantOfView:row] && ![targets containsObject:label]) [targets addObject:label];
    }
    NSMutableArray *pending=[NSMutableArray new];
    for(UIView *view in @[root,row,textSlot]) if(view.bounds.size.width<=0 || view.bounds.size.height<=0) [pending addObject:view];
    for(UILabel *label in targets) {
        if(label.hidden || !label.text.length) continue;
        UIFont *targetFont=label==title ? font : detail;
        CGFloat height=MIN(label.bounds.size.height,cell.bounds.size.height-8);
        // Fixed native rows must actually fit their chosen line count; do not force self-sizing.
        if(height<targetFont.lineHeight || label.bounds.size.width<=0) {
            if(label.bounds.size.width<=0 || label.bounds.size.height<=0) { [pending addObject:label]; continue; }
            if(documentAspect) continue; // Image/slot sizing does not require a font rewrite.
            return FPLayoutReject(@"nativeGate",@"FPCompactNative_08");
        }
        NSInteger lines=label==title ? FPCompactNameLines(height,targetFont.lineHeight,0) : 1;
        [labels addObject:@{@"target":label,@"originalFont":label.font,@"font":targetFont,@"originalLines":@(label.numberOfLines),@"lines":@(lines),
            @"originalBreak":@(label.lineBreakMode),@"originalDynamic":@(label.adjustsFontForContentSizeCategory)}];
    }
    if(FPLayoutDecision) FPLayoutDecision[@"pending"]=pending.count ? @"zero_bounds" : @"ready";
    if(pending.count) FPNativeReadyOnce(cell,identity);
    if(!labels.count && !documentAspect) return FPLayoutReject(@"nativeGate",@"FPCompactNative_09");
    NSMutableArray *trailing=[NSMutableArray new], *watch=[NSMutableArray new];
    BOOL textEdges=FPPlanTrailing(cell,row,textSlot,trailing,watch);
    textEdges=textEdges && !pending.count;
    if(FPLayoutDecision) FPLayoutDecision[@"trailing"]=textEdges ? @"accepted" : pending.count ? @"rejected_pending" : @"rejected_proof";
    if(!textEdges) { [trailing removeAllObjects]; [watch removeAllObjects]; }
    NSMutableArray *constraints=[NSMutableArray new];
    BOOL geometry;
    if(documentAspect) geometry=FPPlanDocumentDimensions(root,slot,image,documentAspect,constraints);
    else geometry=FPPlanDimension(slot,NSLayoutAttributeWidth,root,slot,image,constraints) &&
       (image==slot || FPPlanDimension(image,NSLayoutAttributeWidth,root,slot,image,constraints)) &&
       FPPlanDimension(image,NSLayoutAttributeHeight,root,slot,image,constraints);
    geometry=geometry && FPPlanEdges(row,root,constraints);
    if(FPLayoutDecision) FPLayoutDecision[@"geometry"]=geometry ? @"accepted" : @"rejected_proof";
    if(!geometry) {
        if(!documentAspect && !textEdges) return FPLayoutReject(@"nativeGate",@"FPCompactNative_10");
        [constraints removeAllObjects];
        // A verified standalone image can fit without shrinking an unsupported outer slot.
        BOOL imageOnly=documentAspect && slot!=image && FPPlanDocumentDimensions(root,image,image,documentAspect,constraints);
        if(FPLayoutDecision) FPLayoutDecision[@"imageOnly"]=imageOnly ? @"accepted" : @"not_applied";
        if(!imageOnly) [constraints removeAllObjects];
        if(!imageOnly && !labels.count) return FPLayoutReject(@"nativeGate",@"FPCompactNative_11");
    }
    for(NSDictionary *entry in trailing) {
        if([entry[@"disabled"] boolValue]) [constraints addObject:entry];
        else FPTrailingChange(constraints,entry[@"target"],[entry[@"value"] doubleValue]);
    }
    NSMutableArray *witnesses=[NSMutableArray new];
    for(NSDictionary *entry in watch) {
        BOOL changed=NO;
        for(NSDictionary *change in constraints) if(change[@"target"]==entry[@"target"]) { changed=YES; break; }
        if(!changed) [witnesses addObject:entry];
    }
    NSArray *accessories=[cell isKindOfClass:UICollectionViewListCell.class] ? [(UICollectionViewListCell *)cell accessories] : @[];
    NSDictionary *state=@{@"pendingViews":pending,@"textPending":@(pending.count>0),@"trailing":@(textEdges),@"watch":witnesses,@"accessories":[accessories copy],@"identity":identity,@"row":row,@"slot":slot,@"spacing":@([row customSpacingAfterView:slot]),@"geometry":@(geometry),
        @"constraints":constraints,@"labels":labels,@"size":[NSValue valueWithCGSize:cell.bounds.size],@"font":font,@"detailFont":detail,
        @"leadingMargin":@(root.directionalLayoutMargins.leading),@"trailingMargin":@(root.directionalLayoutMargins.trailing)};
    // Commit the entire plan BEFORE any native layout setter can reenter configuration.
    objc_setAssociatedObject(cell,&FPNativeStyleKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for(NSDictionary *entry in constraints) {
        NSLayoutConstraint *c=entry[@"target"];
        if([entry[@"disabled"] boolValue]) { if(c.active) c.active=NO; }
        else if([entry[@"added"] boolValue]) { c.priority=999; c.active=YES; }
        else if(c.constant!=[entry[@"value"] doubleValue]) c.constant=[entry[@"value"] doubleValue];
    }
    if(geometry && [row customSpacingAfterView:slot]!=6) [row setCustomSpacing:6 afterView:slot];
    for(NSDictionary *entry in labels) {
        UILabel *label=entry[@"target"];
        if(![label.font isEqual:entry[@"font"]]) label.font=entry[@"font"];
        if(label.numberOfLines!=[entry[@"lines"] integerValue]) label.numberOfLines=[entry[@"lines"] integerValue];
        if(label.lineBreakMode!=NSLineBreakByTruncatingTail) label.lineBreakMode=NSLineBreakByTruncatingTail;
        if(!label.adjustsFontForContentSizeCategory) label.adjustsFontForContentSizeCategory=YES;
    }
    return YES;
}

// One bounded last-decision record per live cell; no history, strings or I/O.
static BOOL FPCompactNative(UICollectionViewCell *cell, BOOL compact) {
    NSMutableDictionary *previous=FPLayoutDecision;
    NSMutableDictionary *decision=[@{@"cache":@"not_reached",@"trailing":@"not_reached",@"geometry":@"not_reached",@"pending":@"not_reached"} mutableCopy];
    FPLayoutDecision=decision;
    @try { BOOL applied=FPCompactNativeObserved(cell,compact); decision[@"nativeApplied"]=@(applied); return applied; }
    @finally {
        if([decision[@"cache"] hasPrefix:@"hit_"]) {
            NSDictionary *old=objc_getAssociatedObject(cell,&FPLayoutDecisionKey);
            decision[@"planDecision"]=old[@"planDecision"] ?: old ?: @{@"status":@"not_observed"};
        }
        objc_setAssociatedObject(cell,&FPLayoutDecisionKey,[decision copy],OBJC_ASSOCIATION_RETAIN_NONATOMIC); FPLayoutDecision=previous;
    }
}
