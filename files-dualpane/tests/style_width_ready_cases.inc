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
static void WidthLimitCase(BOOL label, BOOL maximum) {
    NativeFixture *f=TrailingFixture(NO,NO,NO);
    UIView *target=label ? f.title : f.title.superview;
    NSLayoutConstraint *cap=Constraint(target,target,NSLayoutAttributeWidth,nil,0,120);
    cap.relation=maximum ? NSLayoutRelationLessThanOrEqual : NSLayoutRelationEqual;
    CGFloat before=TextWidth(f.title,f);
    f.cell.reenter=YES; nativeReentry=f.cell; FPStyleVisibleCell(f.cell);
    assert(fabs(TextWidth(f.title,f)-240)<0.00001);
    AssertTextLimits(target,240,f.cell.contentView);
    assert(!cap.active && cap.constant==120 && nested==0);
    int n=nativeWrites,a=accessoryWrites,b=backgroundWrites,w=writes;
    for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell);
    assert(n==nativeWrites && a==accessoryWrites && b==backgroundWrites && w==writes);
    [f.cell prepareForReuse]; assert(cap.active && cap.constant==120);
    FPStyleVisibleCell(f.cell); assert(!cap.active);
    SetScope(f.cell,NO); FPStyleVisibleCell(f.cell);
    assert(cap.active && cap.constant==120 && TextWidth(f.title,f)==before);
    nativeReentry=nil;
}
static void SiblingCase(void) {
    for(int reverse=0;reverse<2;reverse++) {
        NativeFixture *f=TrailingFixture(NO,NO,NO); UIView *text=f.title.superview;
        for(NSLayoutConstraint *c in text.constraints) if(c.firstItem==f.title || c.secondItem==f.title) c.active=NO;
        NSLayoutConstraint *same=Constraint(text,reverse ? f.detail : f.title,NSLayoutAttributeRight,reverse ? f.title : f.detail,NSLayoutAttributeRight,0);
        CGFloat before=TextWidth(f.title,f); f.cell.reenter=YES; nativeReentry=f.cell;
        FPStyleVisibleCell(f.cell);
        assert(fabs(TextWidth(f.title,f)-240)<0.00001 && fabs(TextWidth(f.detail,f)-240)<0.00001);
        assert(same.active && same.constant==0 && nested==0);
        int n=nativeWrites; for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell); assert(n==nativeWrites && same.constant==0);
        SetScope(f.cell,NO); FPStyleVisibleCell(f.cell); assert(TextWidth(f.title,f)==before && same.constant==0);
        nativeReentry=nil;
    }
}
static void StatusCase(void) {
    NativeFixture *f=TrailingFixture(NO,NO,NO); UIView *text=f.title.superview;
    for(NSLayoutConstraint *c in f.row.constraints) if(c.firstItem==text && c.firstAttribute==NSLayoutAttributeTrailing) c.active=NO;
    UIView *status=[UIView new]; [f.row addArrangedSubview:status];
    NSLayoutConstraint *width=Constraint(status,status,NSLayoutAttributeWidth,nil,0,26);
    NSLayoutConstraint *right=Constraint(f.row,status,NSLayoutAttributeTrailing,f.row,NSLayoutAttributeTrailing,0);
    NSLayoutConstraint *gap=Constraint(f.row,text,NSLayoutAttributeTrailing,status,NSLayoutAttributeLeading,-24);
    NSLayoutConstraint *cap=Constraint(text,text,NSLayoutAttributeWidth,nil,0,120);
    CGFloat before=TextWidth(f.title,f); f.cell.reenter=YES; nativeReentry=f.cell;
    FPStyleVisibleCell(f.cell);
    assert(fabs(TextWidth(f.title,f)-204)<0.00001 && fabs(TextWidth(f.detail,f)-204)<0.00001);
    assert(!cap.active && gap.constant==-10 && width.active && width.constant==26 && right.constant==0 && nested==0);
    int n=nativeWrites; for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell); assert(n==nativeWrites);
    width.constant=42; FPStyleVisibleCell(f.cell);
    assert(fabs(TextWidth(f.title,f)-188)<0.00001 && width.constant==42 && right.constant==0);
    SetScope(f.cell,NO); FPStyleVisibleCell(f.cell); assert(cap.active && gap.constant==-24 && width.constant==42);
    width.constant=26; assert(TextWidth(f.title,f)==before); nativeReentry=nil;
    // An unproved trailing item must not release a text cap or move its right edge.
    f=TrailingFixture(NO,NO,NO); text=f.title.superview;
    [f.row addArrangedSubview:[UIView new]]; cap=Constraint(text,text,NSLayoutAttributeWidth,nil,0,120);
    before=TextWidth(f.title,f); FPStyleVisibleCell(f.cell); assert(cap.active && TextWidth(f.title,f)==before);
}
static void ReadyCase(void) {
    NativeFixture *f=TrailingFixture(YES,NO,NO); f.sizes[2].constant=60; Ratio(f,2.0/3.0,NO);
    f.title.bounds=CGRectZero; f.detail.bounds=CGRectZero;
    int queued=readyQueued; FPStyleVisibleCell(f.cell); assert(f.title.font.pointSize==17 && readyQueued==queued+1);
    int n=nativeWrites; for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell); assert(n==nativeWrites && readyQueued==queued+1);
    f.title.bounds=CGRectMake(0,0,200,36); f.detail.bounds=CGRectMake(0,0,180,18);
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
    assert(f.title.font.pointSize==14 && f.detail.font.pointSize==13 && readyQueued==queued+1);
    n=nativeWrites; for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell); assert(n==nativeWrites);
    SetScope(f.cell,NO); FPStyleVisibleCell(f.cell); assert(f.title.font.pointSize==17 && f.sizes[2].constant==60);
    // A late ticket may not style the replacement identity, nor dispatch a frame loop.
    f=TrailingFixture(YES,NO,NO); f.sizes[2].constant=60; Ratio(f,2.0/3.0,NO); f.title.bounds=CGRectZero;
    queued=readyQueued; FPStyleVisibleCell(f.cell); f.cell.cellContent=[NSObject new];
    f.title.bounds=CGRectMake(0,0,200,36); n=nativeWrites;
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
    assert(n==nativeWrites && f.title.font.pointSize==17 && readyQueued==queued+1);
    f=TrailingFixture(YES,NO,NO); f.sizes[2].constant=60; Ratio(f,2.0/3.0,NO); f.title.bounds=CGRectZero;
    queued=readyQueued; FPStyleVisibleCell(f.cell);
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
    assert(readyQueued==queued+1); n=nativeWrites;
    for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell); assert(n==nativeWrites && readyQueued==queued+1);
}
static void WidthReadyCases(void) {
    const char *only=getenv("FILES_STYLE_CASE");
    if(!only || !strcmp(only,"width")) { WidthLimitCase(NO,NO); WidthLimitCase(YES,NO); puts("PASS width: slot/label equality released and restored; 1000 zero setters; reentry/reuse"); }
    if(!only || !strcmp(only,"max")) { WidthLimitCase(NO,YES); WidthLimitCase(YES,YES); puts("PASS max: slot/label maximum released and restored; 1000 zero setters; reentry/reuse"); }
    if(!only || !strcmp(only,"sibling")) { SiblingCase(); puts("PASS sibling: both same-right orientations; no cumulative padding; 1000 zero setters; restore"); }
    if(!only || !strcmp(only,"status")) { StatusCase(); puts("PASS status.leading: proved provider width/right; dynamic width; safe cap release; unknown tail refusal; restore"); }
    if(!only || !strcmp(only,"delayedready")) { ReadyCase(); puts("PASS delayedready: one main queue retry; identity guard; no per-frame loop; restore; 1000 zero setters"); }
}
