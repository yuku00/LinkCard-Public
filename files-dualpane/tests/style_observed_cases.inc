// All 119 original equations are present, including low-priority hidden and spacer links.
static CGFloat ObservedTextWidth(NativeFixture *f, NSArray *cs) {
    CGFloat slotWidth=0;
    for(NSLayoutConstraint *c in f.slot.constraints) if(c.active && c.firstItem==f.slot && c.firstAttribute==NSLayoutAttributeWidth && !c.secondItem) slotWidth=c.constant;
    assert(slotWidth==20);
    CGFloat left=f.cell.contentView.directionalLayoutMargins.leading+[(NSLayoutConstraint *)cs[25] constant];
    CGFloat right=f.cell.contentView.bounds.size.width-f.cell.contentView.directionalLayoutMargins.trailing-[(NSLayoutConstraint *)cs[26] constant];
    assert(left==10 && fabs(right-(f.cell.contentView.bounds.size.width-10))<1e-6);
    assert([(NSLayoutConstraint *)cs[56] constant]==6);
    assert([(NSLayoutConstraint *)cs[87] active] && [(NSLayoutConstraint *)cs[89] active] && [(NSLayoutConstraint *)cs[90] active]);
    assert(fabs([(NSLayoutConstraint *)cs[85] constant]-20*[(NSLayoutConstraint *)cs[87] multiplier])<1e-6);
    assert([(NSLayoutConstraint *)cs[86] constant]==20);
    return right-left-slotWidth-[(NSLayoutConstraint *)cs[56] constant]-[(NSLayoutConstraint *)cs[57] constant]-[(NSLayoutConstraint *)cs[102] constant];
}
static void ObservedStable(NativeFixture *f) {
    id state=objc_getAssociatedObject(f.cell,&FPNativeStyleKey);
    int n=nativeWrites,a=accessoryWrites,b=backgroundWrites;
    for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell);
    assert(nativeWrites==n && accessoryWrites==a && backgroundWrites==b && nested==0);
    assert(objc_getAssociatedObject(f.cell,&FPNativeStyleKey)==state);
}
// Replay UIKit replacing a native equation without retaining the old object.
static NSLayoutConstraint *ObservedRebuild(UIView *owner, NSMutableArray *cs, NSUInteger index, CGFloat constant) {
    NSLayoutConstraint *old=cs[index];
    NSLayoutConstraint *replacement=[NSLayoutConstraint constraintWithItem:old.firstItem attribute:old.firstAttribute relatedBy:old.relation toItem:old.secondItem attribute:old.secondAttribute multiplier:old.multiplier constant:constant];
    replacement.priority=old.priority; old.active=NO; [owner.constraints removeObject:old];
    [owner.constraints insertObject:replacement atIndex:0]; replacement.active=YES; cs[index]=replacement;
    return replacement;
}
static void ObservedCases(void) {
    NSMutableDictionary *o; NSMutableArray *cs; NativeFixture *f=Observed(&o,&cs);
    assert(cs.count==119 && f.cell.accessories.count==1);
    f.cell.reenter=YES; nativeReentry=f.cell; FPStyleVisibleCell(f.cell);
    NSDictionary *state=objc_getAssociatedObject(f.cell,&FPNativeStyleKey);
    if(![state[@"geometry"] boolValue] || ![state[@"trailing"] boolValue]) {
        NSDictionary *d=objc_getAssociatedObject(f.cell,&FPLayoutDecisionKey);
        NSLog(@"Observed graph rejection %@",d);
    }
    assert([state[@"geometry"] boolValue] && [state[@"trailing"] boolValue]);
    assert(![(NSLayoutConstraint *)cs[88] active]);
    assert([(NSLayoutConstraint *)cs[29] constant]==-16);
    assert([(NSLayoutConstraint *)cs[57] constant]==0);
    assert([(NSLayoutConstraint *)cs[25] constant]==-6 && [(NSLayoutConstraint *)cs[26] constant]==2);
    CGFloat textWidth=ObservedTextWidth(f,cs);
    assert(fabs(textWidth-109.33333333333334)<1e-6);
    assert([(NSLayoutConstraint *)cs[1] constant]==27 && [(NSLayoutConstraint *)cs[10] constant]==39);
    ObservedStable(f);
    // Equivalent UISV regeneration and ordering changes must not restore/reapply.
    nativeReentry=nil;
    ObservedRebuild(f.row,cs,52,0);
    ObservedRebuild(f.row,cs,56,6);
    ObservedRebuild(f.row,cs,57,0);
    nativeReentry=f.cell;
    ObservedStable(f);
    assert(objc_getAssociatedObject(f.cell,&FPNativeStyleKey)==state);
    assert(fabs(ObservedTextWidth(f,cs)-109.33333333333334)<1e-6);
    // Visible tags recover their exact original stack spacing, not a guessed 10pt.
    UIView *tags=o[@19]; tags.bounds=CGRectMake(0,0,24,12);
    [(NSLayoutConstraint *)cs[102] setConstant:24]; [(NSLayoutConstraint *)cs[103] setConstant:12];
    FPStyleVisibleCell(f.cell); assert([(NSLayoutConstraint *)cs[57] constant]==16);
    assert(fabs(ObservedTextWidth(f,cs)-69.33333333333334)<1e-6); ObservedStable(f);
    tags.bounds=CGRectZero; [(NSLayoutConstraint *)cs[102] setConstant:0]; [(NSLayoutConstraint *)cs[103] setConstant:0];
    FPStyleVisibleCell(f.cell); assert(fabs(ObservedTextWidth(f,cs)-109.33333333333334)<1e-6); ObservedStable(f);
    // External provider grows by 15pt; UIKit's reserved content delta is untouched.
    [(NSLayoutConstraint *)cs[1] setConstant:42]; [(NSLayoutConstraint *)cs[109] setConstant:42]; [(NSLayoutConstraint *)cs[10] setConstant:54];
    f.cell.contentView.bounds=CGRectMake(0,0,140.33333333333334,61);
    FPStyleVisibleCell(f.cell); assert([(NSLayoutConstraint *)cs[10] constant]==54 && [(NSLayoutConstraint *)cs[1] constant]==42);
    assert(fabs(ObservedTextWidth(f,cs)-94.33333333333334)<1e-6); ObservedStable(f);
    // External height remains native-owned while width stays independently compact.
    f.cell.bounds=CGRectMake(0,0,194.33333333333334,71); f.cell.contentView.bounds=CGRectMake(0,0,140.33333333333334,71);
    f.slot.bounds=CGRectMake(0,0,20,55); [(NSLayoutConstraint *)cs[14] setConstant:71];
    FPStyleVisibleCell(f.cell); assert([(NSLayoutConstraint *)cs[29] constant]==-16);
    assert(f.cell.contentView.bounds.size.height+[(NSLayoutConstraint *)cs[29] constant]==55); ObservedStable(f);
    // A real unsupported equation is partial, and only its later configuration change replans.
    NSLayoutConstraint *foreign=Constraint(f.slot,f.slot,NSLayoutAttributeWidth,f.row,NSLayoutAttributeWidth,17);
    FPStyleVisibleCell(f.cell); state=objc_getAssociatedObject(f.cell,&FPNativeStyleKey);
    assert([state[@"quality"] isEqual:@"partial"] && ![state[@"geometry"] boolValue]); ObservedStable(f);
    foreign.active=NO; FPStyleVisibleCell(f.cell); state=objc_getAssociatedObject(f.cell,&FPNativeStyleKey);
    assert([state[@"quality"] isEqual:@"exact"]); ObservedStable(f);
    FPHookCell(UICollectionViewCell.class); FPHookCell(HookChild.class); FPHookCell(NSClassFromString(@"Files.DOCItemCollectionListCell"));
    [f.cell prepareForReuse]; assert(!objc_getAssociatedObject(f.cell,&FPNativeStyleKey));
    assert([(NSLayoutConstraint *)cs[88] active] && [(NSLayoutConstraint *)cs[29] constant]==-16);
    assert([(NSLayoutConstraint *)cs[57] constant]==16 && [(NSLayoutConstraint *)cs[56] constant]==12);
    assert([(NSLayoutConstraint *)cs[25] constant]==0 && [(NSLayoutConstraint *)cs[26] constant]==0);
    assert([(NSLayoutConstraint *)cs[10] constant]==54 && [(NSLayoutConstraint *)cs[1] constant]==42);
    f.cell.cellContent=[NSObject new]; f.title.text=@"recycled anonymous fixture";
    FPStyleVisibleCell(f.cell); assert(fabs(ObservedTextWidth(f,cs)-94.33333333333334)<1e-6); ObservedStable(f);
    nativeReentry=nil;
    // New native inset value is compacted once, then restored to the NEW value.
    f=Observed(&o,&cs); FPStyleVisibleCell(f.cell);
    NSLayoutConstraint *newInset=ObservedRebuild(f.cell.contentView,cs,25,3);
    FPStyleVisibleCell(f.cell); assert(newInset.active && newInset.constant==-6); ObservedStable(f);
    [f.cell prepareForReuse]; assert(newInset.active && newInset.constant==3);
    assert([(NSLayoutConstraint *)cs[88] active] && [(NSLayoutConstraint *)cs[29] constant]==-16);
    // Nonzero internal-guide equations remain unsupported; they are not aliases.
    f=Observed(&o,&cs); [(NSLayoutConstraint *)cs[70] setConstant:1]; FPStyleVisibleCell(f.cell);
    state=objc_getAssociatedObject(f.cell,&FPNativeStyleKey); assert(![state[@"geometry"] boolValue] && ![state[@"trailing"] boolValue]); ObservedStable(f);
    puts("PASS observed full production graph: text58.333->109.333; tags24+gap16 ->69.333; status42/delta54 ->94.333; slotheight45->55; partial/exact event invalidation; reuse restore; reentry1000 zero writes");
}
