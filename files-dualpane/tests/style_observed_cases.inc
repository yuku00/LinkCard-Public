// All 119 original equations are present, including low-priority hidden and spacer links.
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
    CGFloat textWidth=f.cell.contentView.bounds.size.width-20-20-6;
    assert(fabs(textWidth-109.33333333333334)<1e-6);
    assert([(NSLayoutConstraint *)cs[1] constant]==27 && [(NSLayoutConstraint *)cs[10] constant]==39);
    int n=nativeWrites; for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell);
    assert(nativeWrites==n && nested==0);
    nativeReentry=nil;
    puts("PASS observed graph: full 119 equations; text 58.333 -> 109.333; status27/content39 preserved; 1000 zero writes");
}
