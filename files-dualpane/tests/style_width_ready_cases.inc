// Width limits are part of the equations: an unchanged cap must fail this fixture.
static void AssertTextLimits(UIView *view, CGFloat available, UIView *root) {
    for(UIView *owner=view;owner;owner=owner.superview) {
        for(NSLayoutConstraint *c in owner.constraints) {
            if(!c.active || c.firstItem!=view || c.firstAttribute!=NSLayoutAttributeWidth || c.secondItem) continue;
            if(c.relation==NSLayoutRelationEqual) assert(fabs(c.constant-available)<0.00001);
            if(c.relation==NSLayoutRelationLessThanOrEqual) assert(available<=c.constant+0.00001);
        }
        if(owner==root) break;
    }
}
static void WidthReadyCases(void) {
    for(int labelMax=0;labelMax<2;labelMax++) {
        NativeFixture *f=TrailingFixture(NO,NO,NO); UIView *text=f.title.superview;
        UIView *target=labelMax ? f.title : text;
        NSLayoutConstraint *cap=Constraint(target,target,NSLayoutAttributeWidth,nil,0,120);
        cap.relation=labelMax ? NSLayoutRelationLessThanOrEqual : NSLayoutRelationEqual;
        f.cell.reenter=YES; nativeReentry=f.cell; FPStyleVisibleCell(f.cell);
        assert(fabs(TextWidth(f.title,f)-240)<0.00001);
        AssertTextLimits(target,240,f.cell.contentView);
        assert(!cap.active && cap.constant==120 && nested==0);
        int n=nativeWrites; for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell); assert(n==nativeWrites);
        SetScope(f.cell,NO); FPStyleVisibleCell(f.cell); assert(cap.active && cap.constant==120);
        nativeReentry=nil;
    }
    puts("PASS fixedslot/labelmax: actual trailing plus active width equations, restore, synchronous reentry, 1000 no prediction writes");
    NativeFixture *f=TrailingFixture(YES,NO,NO); f.sizes[2].constant=60; Ratio(f,2.0/3.0,NO);
    f.title.bounds=CGRectZero; f.detail.bounds=CGRectZero;
    FPStyleVisibleCell(f.cell); assert(f.title.font.pointSize==17);
    f.title.bounds=CGRectMake(0,0,200,36); f.detail.bounds=CGRectMake(0,0,180,18);
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
    assert(f.title.font.pointSize==14 && f.detail.font.pointSize==13);
    int n=nativeWrites; for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell); assert(n==nativeWrites);
    puts("PASS delayedready: zero bounds followed by one main queue retry, no layout hook or repeated writes");
}
