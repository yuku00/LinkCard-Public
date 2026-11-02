// Local, app-owned action panel; never changes the keyboard or host input view.
@interface WUChatGridController : UIViewController
@property(nonatomic,copy) NSArray<NSDictionary *> *entries;
@property(nonatomic) NSUInteger columns;
@end
@implementation WUChatGridController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"聊天工具"; self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    UIScrollView *scroll=[UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:scroll];
    UIStackView *rows=[UIStackView new]; rows.axis=UILayoutConstraintAxisVertical; rows.spacing=10; rows.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:rows];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [rows.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16], [rows.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [rows.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16], [rows.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],
        [rows.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]
    ]];
    NSUInteger columns=MAX(2,MIN(4,self.columns));
    for(NSUInteger i=0;i<self.entries.count;i+=columns) {
        UIStackView *row=[UIStackView new]; row.axis=UILayoutConstraintAxisHorizontal; row.spacing=10; row.distribution=UIStackViewDistributionFillEqually;
        for(NSUInteger j=0;j<columns;j++) {
            if(i+j>=self.entries.count) { [row addArrangedSubview:[UIView new]]; continue; }
            NSDictionary *entry=self.entries[i+j]; UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
            [button setTitle:entry[@"title"] forState:UIControlStateNormal]; button.titleLabel.numberOfLines=0; button.titleLabel.textAlignment=NSTextAlignmentCenter;
            button.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; button.titleLabel.adjustsFontForContentSizeCategory=YES;
            button.backgroundColor=UIColor.secondarySystemBackgroundColor; button.layer.cornerRadius=10; button.contentEdgeInsets=UIEdgeInsetsMake(12,6,12,6);
            [button.heightAnchor constraintGreaterThanOrEqualToConstant:60].active=YES;
            __weak WUChatGridController *weak=self; void (^run)(void)=entry[@"run"];
            [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action){
                WUChatGridController *panel=weak; if(!panel) return;
                [panel dismissViewControllerAnimated:YES completion:^{ if(run) run(); }];
            }] forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:button];
        }
        [rows addArrangedSubview:row];
    }
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
@end
