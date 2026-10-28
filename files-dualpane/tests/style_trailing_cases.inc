// Known native DOC getter identities; equations are evaluated, not simulated frames.
static CGFloat TrailingValue(id item, NativeFixture *f, NSMutableSet *seen) {
    if(item==f.cell.contentView) return 320;
    if(item==f.cell.contentView.layoutMarginsGuide) return 304;
    NSValue *key=[NSValue valueWithPointer:(__bridge const void *)item];
    assert(![seen containsObject:key]); [seen addObject:key];
    UIView *owner=[item isKindOfClass:UILayoutGuide.class] ? [(UILayoutGuide *)item owningView] : item;
    for(;owner;owner=owner.superview) {
        for(NSLayoutConstraint *c in owner.constraints) {
            if(!c.active || c.relation!=NSLayoutRelationEqual || c.multiplier!=1 || c.firstAttribute!=NSLayoutAttributeTrailing || c.secondAttribute!=NSLayoutAttributeTrailing) continue;
            id other=c.firstItem==item ? c.secondItem : c.secondItem==item ? c.firstItem : nil;
            if(!other || ([other isKindOfClass:UIView.class] && [item isKindOfClass:UIView.class] && [(UIView *)other isDescendantOfView:item])) continue;
            if(c.firstItem==item) return TrailingValue(c.secondItem,f,seen)+c.constant;
            if(c.secondItem==item) return TrailingValue(c.firstItem,f,seen)-c.constant;
        }
        if(owner==f.cell.contentView) break;
    }
    assert(!"missing native trailing equation"); return NAN;
}
static CGFloat TextWidth(UILabel *label, NativeFixture *f) {
    return TrailingValue(label,f,[NSMutableSet new])-70;
}
static NativeFixture *TrailingFixture(BOOL folder, BOOL provider, BOOL disclosure) {
    NativeFixture *f=Native(); UIView *text=f.title.superview, *root=f.cell.contentView;
    Constraint(text,f.title,NSLayoutAttributeTrailing,text,NSLayoutAttributeTrailing,-8);
    Constraint(text,text,NSLayoutAttributeTrailing,f.detail,NSLayoutAttributeTrailing,8);
    Constraint(f.row,text,NSLayoutAttributeTrailing,f.row,NSLayoutAttributeTrailing,folder ? 0 : -24);
    f.cell.accessories=provider ? @[[UICellAccessory new]] : @[];
    if(disclosure) f.cell.accessories=[f.cell.accessories arrayByAddingObject:[UICellAccessoryDisclosureIndicator new]];
    if(!folder) {
        f.title.text=@"Ordinary document with native trailing reservation.pdf";
        f.edges[0].active=NO; // Leading is unrelated; do not require a direct root edge.
        f.edges[1].active=NO;
        UILayoutGuide *guide=[UILayoutGuide new]; guide.owningView=root;
        NSLayoutConstraint *boundary=Constraint(root,guide,NSLayoutAttributeTrailing,root,NSLayoutAttributeTrailing,provider ? -36 : -28);
        NSLayoutConstraint *edge=Constraint(root,f.row,NSLayoutAttributeTrailing,guide,NSLayoutAttributeTrailing,-6);
        f.edges=@[boundary,edge];
        // Unsupported image width is not permission to reject a proven text trailing path.
        Constraint(f.slot,f.image,NSLayoutAttributeWidth,f.row,NSLayoutAttributeWidth,-244);
    }
    return f;
}
static void TrailingCases(void) {
    for(int folder=0;folder<2;folder++) for(int disclosure=0;disclosure<2;disclosure++) for(int provider=0;provider<2;provider++) {
        // Folder's existing direct-root path remains unchanged; UIKit owns external accessory width.
        if(folder && provider) continue;
        NativeFixture *f=TrailingFixture(folder,provider,disclosure);
        CGFloat before=TextWidth(f.title,f), detailBefore=TextWidth(f.detail,f);
        f.cell.reenter=YES; nativeReentry=f.cell;
        FPStyleVisibleCell(f.cell);
        CGFloat expected=provider ? 274 : 310;
        assert(fabs(TextWidth(f.title,f)-(expected-70))<0.00001);
        assert(fabs(TextWidth(f.detail,f)-(expected-70))<0.00001);
        assert(TextWidth(f.title,f)>before && TextWidth(f.detail,f)>detailBefore);
        assert(f.cell.accessories.count==(NSUInteger)provider && nested==0);
        if(!folder) { assert(f.sizes[1].constant==40); assert(f.edges[0].constant==(provider ? -36 : -28)); }
        int n=nativeWrites,a=accessoryWrites,b=backgroundWrites,w=writes;
        for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell);
        assert(n==nativeWrites && a==accessoryWrites && b==backgroundWrites && w==writes);
        // Selected/unselected configuration does not restore an old geometry snapshot.
        f.cell.selected=NO; FPStyleVisibleCell(f.cell); assert(fabs(TextWidth(f.title,f)-(expected-70))<0.00001);
        f.cell.selected=YES; FPStyleVisibleCell(f.cell); assert(fabs(TextWidth(f.detail,f)-(expected-70))<0.00001);
        if(provider) {
            f.edges[0].constant=-52; FPStyleVisibleCell(f.cell);
            assert(fabs(TextWidth(f.title,f)-(258-70))<0.00001 && f.edges[0].constant==-52);
            f.edges[0].constant=-36; FPStyleVisibleCell(f.cell);
        }
        SetScope(f.cell,NO); FPStyleVisibleCell(f.cell);
        assert(fabs(TextWidth(f.title,f)-before)<0.00001 && fabs(TextWidth(f.detail,f)-detailBefore)<0.00001);
        assert(f.cell.accessories.count==(NSUInteger)(provider+disclosure));
        n=nativeWrites; for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell); assert(n==nativeWrites);
        nativeReentry=nil;
    }
    NativeFixture *f=TrailingFixture(NO,NO,YES); FPStyleVisibleCell(f.cell);
    NSLayoutConstraint *nativeEdge=f.edges[1]; nativeEdge.constant=-19;
    f.title.text=@"Reconfigured document"; f.cell.cellContent=[NSObject new];
    SetScope(f.cell,NO); FPStyleVisibleCell(f.cell); assert(nativeEdge.constant==-19);
    // Reuse invokes the production reset hook before native ownership changes.
    f=TrailingFixture(NO,NO,YES); FPStyleVisibleCell(f.cell);
    [f.cell prepareForReuse]; assert(f.edges[1].constant==-6 && f.cell.accessories.count==1);
    f.title.text=@"Next document"; f.cell.cellContent=[NSObject new]; FPStyleVisibleCell(f.cell);
    assert(fabs(TextWidth(f.title,f)-240)<0.00001);
    puts("PASS native trailing equations: file/folder title+subtitle width growth; disclosure/no-disclosure reserved gap; 10pt edge; real provider boundary width preserved and updated; independent image/leading gate; selected/mode/reuse restore; synchronous reentry; 1000 zero writes");
}
