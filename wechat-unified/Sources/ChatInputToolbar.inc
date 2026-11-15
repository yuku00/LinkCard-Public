// Only the observed direct-child chain is accepted; ambiguous or foreign owners fall back to the navigation menu.
static __attribute__((unused)) UIView *WUInputBarForOwner(UIViewController *owner) {
    UIView *root=owner.viewIfLoaded; if(!root) return nil;
    Class toolClass=NSClassFromString(@"MMInputToolView"), containerClass=NSClassFromString(@"InputToolContainerView"), barClass=NSClassFromString(@"InputToolViewBar");
    if(!toolClass || !containerClass || !barClass) return nil;
    UIView *found=nil;
    for(UIView *tool in root.subviews) if([tool isKindOfClass:toolClass] && Chat(tool)==owner)
        for(UIView *container in tool.subviews) if([container isKindOfClass:containerClass])
            for(UIView *bar in container.subviews) if([bar isKindOfClass:barClass]) { if(found) return nil; found=bar; }
    return found;
}
@interface WUInputToolbar : UIView
- (instancetype)initWithEntries:(NSArray<NSDictionary *> *)entries;
@end
@implementation WUInputToolbar
- (instancetype)initWithEntries:(NSArray<NSDictionary *> *)entries {
    if((self=[super initWithFrame:CGRectZero])) {
        self.backgroundColor=UIColor.secondarySystemBackgroundColor;
        UIScrollView *scroll=[UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints=NO; scroll.showsHorizontalScrollIndicator=NO; [self addSubview:scroll];
        UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisHorizontal; stack.spacing=8; stack.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor], [scroll.topAnchor constraintEqualToAnchor:self.topAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor], [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:8], [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-8], [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor], [stack.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor]]];
        for(NSDictionary *entry in entries) {
            UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:entry[@"title"] forState:UIControlStateNormal]; button.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; button.titleLabel.adjustsFontForContentSizeCategory=YES; button.accessibilityLabel=entry[@"title"];
            [button.widthAnchor constraintGreaterThanOrEqualToConstant:44].active=YES; void (^run)(void)=entry[@"run"];
            [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action){ if(run) run(); }] forControlEvents:UIControlEventTouchUpInside]; [stack addArrangedSubview:button];
        }
    } return self;
}
@end
