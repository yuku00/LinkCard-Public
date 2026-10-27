// The graph below is an explicit known DOC slot fixture. It does not discover device views.
@interface NativeFixture : NSObject
@property UICollectionViewListCell *cell;
@property UIStackView *row;
@property UIView *slot;
@property UIImageView *image;
@property UILabel *title, *detail;
@property NSArray<NSLayoutConstraint *> *sizes, *edges;
@end
@implementation NativeFixture @end
static NSLayoutConstraint *Constraint(UIView *owner,id first,NSLayoutAttribute a,id second,NSLayoutAttribute b,CGFloat constant) {
    NSLayoutConstraint *c=[NSLayoutConstraint constraintWithItem:first attribute:a relatedBy:NSLayoutRelationEqual toItem:second attribute:b multiplier:1 constant:constant];
    [owner.constraints addObject:c]; c.active=YES; return c;
}
static NativeFixture *Native(void) {
    NativeFixture *f=[NativeFixture new]; f.cell=NewCell(NSClassFromString(@"Files.DOCItemCollectionListCell"));
    f.row=[UIStackView new]; f.slot=[UIView new]; f.image=[NSClassFromString(@"DOCThumbnailFittingImageView") new];
    f.image.image=[NSObject new]; f.title=[UILabel new]; f.title.text=@"A long provider filename.txt";
    f.detail=[UILabel new]; f.detail.text=@"1 KB"; f.detail.bounds=CGRectMake(0,0,180,18);
    UIView *text=[UIView new]; [text addSubview:f.title]; [text addSubview:f.detail];
    [f.cell.contentView addSubview:f.row]; [f.row addArrangedSubview:f.slot]; [f.row addArrangedSubview:text]; [f.slot addSubview:f.image];
    f.cell.titleLabel=f.title; f.cell.subtitleLabel=f.detail; f.cell.thumbnailView=f.slot; f.cell.cellContent=[NSObject new];
    f.cell.dateLabel=[NSDate date]; // A legal object getter need not return UILabel; size getter returns nil.
    f.sizes=@[Constraint(f.slot,f.slot,NSLayoutAttributeWidth,nil,0,40), Constraint(f.image,f.image,NSLayoutAttributeWidth,nil,0,40), Constraint(f.image,f.image,NSLayoutAttributeHeight,nil,0,40)];
    UIView *root=f.cell.contentView; root.directionalLayoutMargins=(NSDirectionalEdgeInsets){0,16,0,16};
    f.edges=@[Constraint(root,f.row,NSLayoutAttributeLeading,root.layoutMarginsGuide,NSLayoutAttributeLeading,2), Constraint(root,root.layoutMarginsGuide,NSLayoutAttributeTrailing,f.row,NSLayoutAttributeTrailing,2)];
    f.cell.accessories=@[[UICellAccessoryMultiselect new],[UICellAccessory new],[UICellAccessoryDisclosureIndicator new]];
    f.cell.selected=YES; f.cell.backgroundConfiguration=[UIBackgroundConfiguration new]; return f;
}
static void AssertNative(NativeFixture *f) {
    assert([objc_getAssociatedObject(f.cell,&FPStyleResultKey) unsignedIntegerValue]&FPStyleNativeApplied);
    assert(f.cell.accessories.count==1 && f.cell.isSelected && f.cell.backgroundConfiguration.backgroundColor.alpha==0.18);
    for(NSLayoutConstraint *c in f.sizes) assert(c.constant==20 && c.active);
    for(NSLayoutConstraint *c in f.edges) assert(c.constant==-6);
    assert([f.row customSpacingAfterView:f.slot]==6 && f.title.font.pointSize==14 && f.detail.font.pointSize==13);
    assert(f.title.numberOfLines==2 && f.title.numberOfLines*f.title.font.lineHeight<=f.title.bounds.size.height);
    assert(f.detail.numberOfLines*f.detail.font.lineHeight<=f.detail.bounds.size.height);
}
static void AssertUnsupported(NativeFixture *f) {
    int n=nativeWrites; FPStyleVisibleCell(f.cell);
    assert(!objc_getAssociatedObject(f.cell,&FPNativeStyleKey) && nativeWrites==n);
    assert([objc_getAssociatedObject(f.cell,&FPStyleResultKey) unsignedIntegerValue]&FPStyleContentUnsupported);
    assert(f.cell.accessories.count==1); // Independent gate must still run for nil/custom content.
}
static void NativeCases(void) {
    for(int custom=0;custom<2;custom++) {
        NativeFixture *f=Native(); f.cell.contentConfiguration=custom ? @"provider custom content" : nil;
        f.cell.reenter=YES; nativeReentry=f.cell;
        int w=writes; FPStyleVisibleCell(f.cell); AssertNative(f); assert(writes==w && nested==0);
        NSArray *identity=FPNativeIdentity(f.cell); NSMutableArray *same=[identity mutableCopy];
        same[10]=[NSString stringWithFormat:@"%@",identity[10]]; assert(FPNativeIdentityMatches(identity,same));
        same[9]=[UILabel new]; assert(!FPNativeIdentityMatches(identity,same)); // Last object, not first text.
        same=[identity mutableCopy]; same[10]=@"other filename"; assert(!FPNativeIdentityMatches(identity,same));
        same=[identity mutableCopy]; same[0]=[NSObject new]; assert(!FPNativeIdentityMatches(identity,same));
        int n=nativeWrites,a=accessoryWrites,b=backgroundWrites,c=copies;
        for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell);
        assert(nativeWrites==n && accessoryWrites==a && backgroundWrites==b && writes==w && copies==c);
        SetScope(f.cell,NO); FPStyleVisibleCell(f.cell);
        assert(f.title.font.pointSize==17 && f.title.numberOfLines==1 && !f.title.adjustsFontForContentSizeCategory);
        assert(f.cell.accessories.count==3 && [f.row customSpacingAfterView:f.slot]==12);
        for(NSLayoutConstraint *size in f.sizes) assert(size.constant==40);
        for(NSLayoutConstraint *edge in f.edges) assert(edge.constant==2);
        n=nativeWrites; a=accessoryWrites; b=backgroundWrites;
        for(int i=0;i<1000;i++) FPStyleVisibleCell(f.cell);
        assert(nativeWrites==n && accessoryWrites==a && backgroundWrites==b);
        nativeReentry=nil;
    }
    NativeFixture *f=Native(); f.cell.bounds=CGRectMake(0,0,320,27); AssertUnsupported(f);
    f=Native(); f.title.bounds=CGRectMake(0,0,200,12); AssertUnsupported(f);
    f=Native(); f.cell.traitCollection=@3; AssertUnsupported(f); // Dynamic Type must not overflow a fixed native row.
    f=Native(); f.title.bounds=CGRectMake(0,0,200,18); FPStyleVisibleCell(f.cell); assert(f.title.numberOfLines==1);
    f=Native(); f.slot.translatesAutoresizingMaskIntoConstraints=YES; AssertUnsupported(f);
    f=Native(); Constraint(f.slot,f.slot,NSLayoutAttributeWidth,f.row,NSLayoutAttributeWidth,0); AssertUnsupported(f);
    f=Native(); f.edges[0].active=NO; AssertUnsupported(f);
    f=Native(); Constraint(f.row,f.row,NSLayoutAttributeWidth,nil,0,250); AssertUnsupported(f);
    f=Native(); Constraint(f.cell.contentView,f.row,NSLayoutAttributeLeading,f.slot,NSLayoutAttributeLeading,0); AssertUnsupported(f);
    f=Native(); Constraint(f.slot,f.image,NSLayoutAttributeWidth,f.slot,NSLayoutAttributeWidth,4); AssertUnsupported(f);
    f=Native(); [f.slot addSubview:[NSClassFromString(@"DOCThumbnailFittingImageView") new]]; AssertUnsupported(f);
    f=Native(); f.row.axis=UILayoutConstraintAxisVertical; AssertUnsupported(f);
    f=Native(); f.cell.renaming=YES; AssertUnsupported(f);
    // Known equality sizing link and direct root edge constraints are compatible.
    f=Native(); f.sizes[1].active=NO;
    Constraint(f.slot,f.image,NSLayoutAttributeWidth,f.slot,NSLayoutAttributeWidth,0);
    for(NSLayoutConstraint *c in f.edges) c.active=NO;
    NSLayoutConstraint *l=Constraint(f.cell.contentView,f.row,NSLayoutAttributeLeading,f.cell.contentView,NSLayoutAttributeLeading,18);
    NSLayoutConstraint *t=Constraint(f.cell.contentView,f.row,NSLayoutAttributeTrailing,f.cell.contentView,NSLayoutAttributeTrailing,-18);
    FPStyleVisibleCell(f.cell); assert(objc_getAssociatedObject(f.cell,&FPNativeStyleKey) && l.constant==10 && t.constant==-10);
    NSArray *planned=[objc_getAssociatedObject(f.cell,&FPNativeStyleKey) objectForKey:@"constraints"];
    NSMutableArray *added=[NSMutableArray new]; for(NSDictionary *e in planned) if([e[@"added"] boolValue]) [added addObject:e[@"target"]];
    assert(added.count==1 && ((NSLayoutConstraint *)added[0]).active);
    SetScope(f.cell,NO); FPStyleVisibleCell(f.cell); assert(!((NSLayoutConstraint *)added[0]).active && l.constant==18 && t.constant==-18);
    int n=nativeWrites; FPStyleVisibleCell(f.cell); assert(nativeWrites==n);
    // Typed runtime scalar/wrong-return ABIs never invoke an unsafe object getter.
    Class bad=NamedClass(@"HostBadTitleABI",NSClassFromString(@"Files.DOCItemCollectionListCell"));
    __block int calls=0; class_addMethod(bad,@selector(accessibilityTitleLabel),imp_implementationWithBlock(^NSInteger(id object){ calls++; return 7; }),"q@:");
    f=Native(); object_setClass(f.cell,bad); AssertUnsupported(f); assert(calls==0);
    Class badDate=NamedClass(@"HostBadDateABI",NSClassFromString(@"Files.DOCItemCollectionListCell"));
    class_addMethod(badDate,@selector(accessibilityDateLabel),imp_implementationWithBlock(^double(id object){ calls++; return 1; }),"d@:");
    f=Native(); object_setClass(f.cell,badDate); AssertUnsupported(f); assert(calls==0);
    Class badRename=NamedClass(@"HostBadRenameABI",NSClassFromString(@"Files.DOCItemCollectionListCell"));
    class_addMethod(badRename,@selector(accessibilityIsRenaming),imp_implementationWithBlock(^id(id object){ calls++; return nil; }),"@@:");
    f=Native(); object_setClass(f.cell,badRename); AssertUnsupported(f); assert(calls==0);
    Class typed=NamedClass(@"HostTypedTitleABI",NSClassFromString(@"Files.DOCItemCollectionListCell"));
    class_addMethod(typed,@selector(accessibilityTitleLabel),imp_implementationWithBlock(^id(id object){ calls++; return nil; }),"@\"UILabel\"@:");
    f=Native(); object_setClass(f.cell,typed);
    if(!ABI(typed,@"accessibilityTitleLabel","@@:")) { AssertUnsupported(f); assert(calls==0); }
    else { AssertUnsupported(f); assert(calls==1); } // Foundation may canonicalize object annotations.
    puts("PASS native production: nil/custom DOC content; independent accessories/background; typed getter ABI unsupported; NSDate/nil detail getters; identity object/text boundary; 1000 zero writes; scope restore once; known size/edge constraints; height/Dynamic Type no-fit fallback");
}
static void ScopeAndHookCases(void) {
    NativeFixture *f=Native(); UICollectionView *cv=(id)f.cell.superview;
    assert(IsPaneListCell(f.cell));
    ((HostController *)cv.delegate).listMode=NO; assert(!IsPaneListCell(f.cell)); ((HostController *)cv.delegate).listMode=YES;
    f.cell.bounds=CGRectMake(0,0,100,72); assert(!IsPaneListCell(f.cell)); f.cell.bounds=CGRectMake(0,0,320,72);
    SetScope(f.cell,NO); assert(!IsPaneListCell(f.cell)); SetScope(f.cell,YES);
    UIViewController *middle=[UIViewController new]; middle.parentViewController=hostPane;
    ((HostController *)cv.delegate).parentViewController=middle; assert(IsPaneListCell(f.cell));
    cv.nextResponder=nil; assert(!IsPaneListCell(f.cell)); cv.nextResponder=hostPane;
    id original=cv.delegate; cv.delegate=[HostController new]; ((HostController *)cv.delegate).parentViewController=hostPane; assert(!IsPaneListCell(f.cell)); cv.delegate=original;
    cv.delegate=[NSClassFromString(@"Files.DOCSidebarViewController") new]; SetScope(f.cell,YES);
    assert(!IsPaneListCell(f.cell)); f.cell.contentConfiguration=@"custom"; assert(!IsPaneListCell(f.cell));
    f.cell.contentConfiguration=[UIListContentConfiguration new]; assert(IsPaneListCell(f.cell));
    FPStyleVisibleCell(f.cell); assert(!objc_getAssociatedObject(f.cell,&FPNativeStyleKey));
    assert([objc_getAssociatedObject(f.cell,&FPStyleResultKey) unsignedIntegerValue]&FPStylePublicApplied);
    // Actual dynamic subclasses/overrides, not a cell.scope Boolean stand-in.
    Class childController=NamedClass(@"HostDOCControllerChild",NSClassFromString(@"Files.DOCItemCollectionViewController"));
    SEL display=@selector(collectionView:willDisplayCell:forItemAtIndexPath:);
    class_addMethod(childController,display,imp_implementationWithBlock(^(id owner,UICollectionView *view,UICollectionViewCell *cell,NSIndexPath *path){
        childDisplays++;
        IMP parent=class_getMethodImplementation(NSClassFromString(@"Files.DOCItemCollectionViewController"),display);
        ((void(*)(id,SEL,id,id,id))parent)(owner,display,view,cell,path);
    }),"v@:@@@");
    FPHookDisplay(NSClassFromString(@"Files.DOCItemCollectionViewController")); FPHookDisplay(childController); FPHookDisplay(childController);
    Class inheritedController=NamedClass(@"HostDOCControllerGrandchild",childController);
    IMP displayBefore=class_getMethodImplementation(inheritedController,display); FPHookDisplay(inheritedController);
    assert(class_getMethodImplementation(inheritedController,display)==displayBefore);
    FPHookCell(UICollectionViewCell.class); FPHookCell(HookChild.class); FPHookCell(NSClassFromString(@"Files.DOCItemCollectionListCell"));
    f=Native(); cv=(id)f.cell.superview; cv.delegate=[inheritedController new]; SetScope(f.cell,YES);
    f.cell.reenter=YES; nativeReentry=f.cell;
    parentDisplays=childDisplays=0;
    [(HostController *)cv.delegate collectionView:cv willDisplayCell:f.cell forItemAtIndexPath:[NSIndexPath indexPathWithIndex:0]];
    assert(parentDisplays==1 && childDisplays==1); AssertNative(f);
    int n=nativeWrites,w=writes,a=accessoryWrites,b=backgroundWrites;
    parentUpdates=childUpdates=bridgeUpdates=0;
    [f.cell updateConfigurationUsingState:[UICellConfigurationState new]];
    assert(parentUpdates==1 && childUpdates==1 && bridgeUpdates==1 && nativeWrites==n && writes==w);
    [f.cell _bridgedUpdateConfigurationUsingState:[UICellConfigurationState new]]; assert(bridgeUpdates==2);
    for(int i=0;i<1000;i++) [f.cell updateConfigurationUsingState:nil];
    assert(parentUpdates==1001 && childUpdates==1001 && bridgeUpdates==1002 && nativeWrites==n && accessoryWrites==a && backgroundWrites==b);
    parentReuse=childReuse=0; [f.cell prepareForReuse];
    assert(parentReuse==1 && childReuse==1 && f.title.font.pointSize==17 && f.cell.accessories.count==3);
    assert(!objc_getAssociatedObject(f.cell,&FPNativeStyleKey));
    n=nativeWrites; StyleCell(f.cell,NO); assert(nativeWrites==n);
    // Native owner replaces labels/content before exit: stale snapshots must not overwrite it.
    nativeReentry=nil; f=Native(); FPStyleVisibleCell(f.cell);
    UILabel *old=f.title,*replacement=[UILabel new]; replacement.font=[UIFont systemFontOfSize:29]; replacement.text=@"replacement";
    [old.superview addSubview:replacement]; f.cell.titleLabel=replacement; f.cell.cellContent=[NSObject new];
    SetScope(f.cell,NO); n=nativeWrites; FPStyleVisibleCell(f.cell);
    assert(replacement.font.pointSize==29 && old.font.pointSize==14 && nativeWrites==n);
    assert(!objc_getAssociatedObject(f.cell,&FPNativeStyleKey)); FPStyleVisibleCell(f.cell); assert(nativeWrites==n);
    // Same-view text changes are also a new identity, never an excuse to restore stale native state.
    f=Native(); FPStyleVisibleCell(f.cell); f.title.text=@"different document"; f.title.font=[UIFont systemFontOfSize:22];
    SetScope(f.cell,NO); n=nativeWrites; FPStyleVisibleCell(f.cell); assert(f.title.font.pointSize==22 && nativeWrites==n);
    // Fixed public row: choose one name line or decline if name+detail cannot fit.
    UICollectionViewCell *public=NewCell(NSClassFromString(@"Files.DOCItemCollectionCell"));
    UIListContentConfiguration *config=[UIListContentConfiguration new]; config.secondaryText=@"details"; public.contentConfiguration=config;
    public.bounds=CGRectMake(0,0,320,44); FPStyleVisibleCell(public);
    assert(((UIListContentConfiguration *)public.contentConfiguration).textProperties.numberOfLines==1);
    public.bounds=CGRectMake(0,0,320,30); FPStyleVisibleCell(public);
    assert(!objc_getAssociatedObject(public,&CellStyleKey));
    assert([objc_getAssociatedObject(public,&FPStyleResultKey) unsignedIntegerValue]&FPStyleContentUnsupported);
    FPRestorePaneStyles(hostPane);
    puts("PASS production scope/hooks: responder+controller ancestry, DOC subclasses, list mode, width, sidebar public-only; parent/child/bridge original exactly once; repeated hooks no duplicates; reuse and replacement identity boundaries");
}
int main(void) { @autoreleasepool {
    RegisterHostClasses(); PublicCases(); NativeCases(); ScopeAndHookCases();
    puts("LIMIT Foundation/CoreGraphics AutoLayout doubles inspect production plans and writes, not UIKit solving/rendering, private device ABI availability, or a real-device stability result");
} return 0; }
