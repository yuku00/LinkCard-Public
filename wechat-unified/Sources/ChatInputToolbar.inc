// Only the observed direct-child chain is accepted; ambiguous or foreign owners fall back to the navigation menu.
static __attribute__((unused)) UIView *WUInputToolForOwner(UIViewController *owner) {
    UIView *root=owner.viewIfLoaded; Class toolClass=NSClassFromString(@"MMInputToolView");
    if(!root || !toolClass) return nil;
    UIView *found=nil;
    for(UIView *tool in root.subviews) if([tool isKindOfClass:toolClass] && Chat(tool)==owner) {
        if(found) return nil;
        found=tool;
    }
    return found;
}
static __attribute__((unused)) UIView *WUInputBarForOwner(UIViewController *owner) {
    UIView *tool=WUInputToolForOwner(owner);
    Class containerClass=NSClassFromString(@"InputToolContainerView"), barClass=NSClassFromString(@"InputToolViewBar");
    if(!tool || !containerClass || !barClass) return nil;
    UIView *found=nil;
    for(UIView *container in tool.subviews) if([container isKindOfClass:containerClass])
        for(UIView *bar in container.subviews) if([bar isKindOfClass:barClass]) { if(found) return nil; found=bar; }
    return found;
}
@interface WUInputToolbar : UIView
@property(nonatomic,copy) BOOL (^current)(void);
- (instancetype)initWithEntries:(NSArray<NSDictionary *> *)entries;
@end
@implementation WUInputToolbar
- (instancetype)initWithEntries:(NSArray<NSDictionary *> *)entries {
    if((self=[super initWithFrame:CGRectZero])) {
        self.backgroundColor=UIColor.secondarySystemBackgroundColor;
        UIScrollView *scroll=[UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints=NO; scroll.showsHorizontalScrollIndicator=NO; [self addSubview:scroll];
        UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisHorizontal; stack.spacing=8; stack.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor], [scroll.topAnchor constraintEqualToAnchor:self.topAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor], [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:8], [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-8], [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor], [stack.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor]]];
        NSDictionary *symbols=@{@"所选消息链接":@"link", @"当前会话搜索":@"magnifyingglass", @"当前会话统计":@"chart.bar", @"整合设置":@"gearshape", @"消息仓库":@"archivebox", @"所选语音转发":@"waveform", @"本地语音包":@"waveform", @"所选表情保存图库":@"face.smiling", @"所选图片 → 微信表情编辑":@"photo", @"本地表情分组 / 资源库":@"square.grid.2x2", @"半屏朋友圈":@"person.2"};
        for(NSDictionary *entry in entries) {
            UIButtonConfiguration *configuration=[UIButtonConfiguration plainButtonConfiguration];
            configuration.title=entry[@"title"]; NSString *symbol=symbols[entry[@"title"]]; if(symbol) configuration.image=[UIImage systemImageNamed:symbol];
            configuration.contentInsets=NSDirectionalEdgeInsetsMake(0,12,0,12); configuration.imagePadding=8;
            UIButton *button=[UIButton buttonWithConfiguration:configuration primaryAction:nil];
            button.tintColor=UIColor.labelColor; button.backgroundColor=UIColor.systemBackgroundColor; button.layer.cornerRadius=22;
            button.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]; button.titleLabel.adjustsFontForContentSizeCategory=YES; button.accessibilityLabel=entry[@"title"];
            [button.widthAnchor constraintGreaterThanOrEqualToConstant:44].active=YES; void (^run)(void)=entry[@"run"];
            __weak WUInputToolbar *weakToolbar=self;
            [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action){
                WUInputToolbar *toolbar=weakToolbar;
                @try { if(toolbar && (!toolbar.current || toolbar.current()) && run) run(); } @catch(__unused NSException *e) {}
            }] forControlEvents:UIControlEventTouchUpInside]; [stack addArrangedSubview:button];
        }
    } return self;
}
@end
