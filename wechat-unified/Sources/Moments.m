#import "WU.h"
#import "MomentsLogic.h"
// Host construction is evidenced at WCRefine 0x18895a0; no old-library call or network prefetch.
static BOOL Current(UIViewController *owner, NSString *account, NSString *session, NSUInteger gen) {
    NSString *now=WUCurrentAccount();
    return owner.viewIfLoaded.window.isKeyWindow && (!owner.navigationController || owner.navigationController.topViewController==owner) && WUMomentsContext(account,session,gen,now,WUChatSession(owner),WUContextGeneration(),WUEnabled(@"convenientMoments"),UIApplication.sharedApplication.applicationState==UIApplicationStateActive);
}
static UIView *Responder(UIView *view, NSUInteger depth) {
    if(!view || depth>32) return nil;
    if(view.isFirstResponder) return view;
    for(UIView *child in view.subviews) { UIView *r=Responder(child,depth+1); if(r) return r; }
    return nil;
}
@interface WUMomentsPresentation : UIPresentationController
@property(nonatomic,strong) UIView *shade;
@end
@implementation WUMomentsPresentation
- (CGRect)frameOfPresentedViewInContainerView {
    CGRect b=self.containerView.bounds; CGFloat h=WUMomentsHeight(CGRectGetHeight(b));
    return CGRectMake(CGRectGetMinX(b),CGRectGetMaxY(b)-h,CGRectGetWidth(b),h);
}
- (BOOL)shouldRemovePresentersView { return NO; }
- (void)presentationTransitionWillBegin {
    self.shade=[[UIView alloc] initWithFrame:self.containerView.bounds]; self.shade.backgroundColor=[UIColor colorWithWhite:0 alpha:0.28];
    self.shade.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.containerView insertSubview:self.shade atIndex:0];
}
- (void)containerViewWillLayoutSubviews { [super containerViewWillLayoutSubviews]; self.shade.frame=self.containerView.bounds; self.presentedView.frame=self.frameOfPresentedViewInContainerView; }
- (void)presentationTransitionDidEnd:(BOOL)completed { if(!completed) [self.shade removeFromSuperview]; }
- (void)dismissalTransitionDidEnd:(BOOL)completed { if(completed) [self.shade removeFromSuperview]; }
@end
@interface WUMomentsSheet : UIViewController <UIViewControllerTransitioningDelegate>
@property(nonatomic,strong) UINavigationController *content;
@property(nonatomic,weak) UIViewController *chat;
@property(nonatomic,weak) UIView *previousResponder;
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSString *session;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,strong) NSTimer *watch;
@property(nonatomic) BOOL closing;
- (void)closeRestoring:(BOOL)restore;
@end
static NSHashTable<WUMomentsSheet *> *sheets;
@implementation WUMomentsSheet
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source {
    return [[WUMomentsPresentation alloc] initWithPresentedViewController:presented presentingViewController:presenting];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.view.layer.cornerRadius=18; self.view.layer.maskedCorners=kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner; self.view.clipsToBounds=YES;
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem]; [close setTitle:@"关闭朋友圈" forState:UIControlStateNormal];
    close.accessibilityLabel=@"关闭半屏朋友圈并返回聊天"; [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    close.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:close];
    UIButton *drafts=[UIButton buttonWithType:UIButtonTypeSystem]; [drafts setTitle:@"草稿/存文字" forState:UIControlStateNormal];
    [drafts addTarget:self action:@selector(draftsTapped) forControlEvents:UIControlEventTouchUpInside]; drafts.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:drafts];
    [NSLayoutConstraint activateConstraints:@[[drafts.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],[drafts.topAnchor constraintEqualToAnchor:self.view.topAnchor],[drafts.heightAnchor constraintEqualToConstant:44],[drafts.trailingAnchor constraintLessThanOrEqualToAnchor:close.leadingAnchor constant:-8]]];
    [self addChildViewController:self.content]; UIView *body=self.content.view; body.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:body];
    [NSLayoutConstraint activateConstraints:@[[close.topAnchor constraintEqualToAnchor:self.view.topAnchor],[close.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],[close.heightAnchor constraintEqualToConstant:44],[body.topAnchor constraintEqualToAnchor:close.bottomAnchor],[body.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[body.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[body.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    [self.content didMoveToParentViewController:self];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; [self.watch invalidate]; __weak WUMomentsSheet *weak=self;
    self.watch=[NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer){ WUMomentsSheet *s=weak; if(!s) { [timer invalidate]; return; } if(!Current(s.chat,s.account,s.session,s.generation)) [s closeRestoring:NO]; }];
}
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; if(self.isBeingDismissed || !self.presentingViewController) { [self.watch invalidate]; self.watch=nil; } }
- (void)dealloc { [_watch invalidate]; }
- (void)draftsTapped { if(!self.closing && Current(self.chat,self.account,self.session,self.generation)) WUMomentsDraftsAction(self.content,self.account,self.generation); }
- (void)closeTapped { [self closeRestoring:YES]; }
- (void)closeRestoring:(BOOL)restore {
    if(self.closing) return; self.closing=YES; [self.watch invalidate]; self.watch=nil;
    UIViewController *chat=self.chat; UIView *input=self.previousResponder;
    UIViewController *presenter=self.presentingViewController;
    if(!presenter || presenter.presentedViewController!=self) return;
    NSString *a=self.account, *s=self.session; NSUInteger g=self.generation;
    // Dismiss the entire owned presentation, including any host detail it presented.
    [presenter dismissViewControllerAnimated:NO completion:^{
        [chat.viewIfLoaded setNeedsLayout]; [chat.viewIfLoaded layoutIfNeeded];
        if(restore && Current(chat,a,s,g) && !chat.presentedViewController && input.window && [input isDescendantOfView:chat.view] && !Responder(chat.view.window,0)) [input becomeFirstResponder];
    }];
}
@end
BOOL WUMomentsAvailable(void) {
    Class c=NSClassFromString(@"WCTimeLineViewController");
    return c && [c isSubclassOfClass:UIViewController.class] && WUMatches(class_getInstanceMethod(c,@selector(init)),"@",@[]);
}
BOOL WUIsMomentsSheet(UIViewController *v) { return [v isKindOfClass:WUMomentsSheet.class]; }
BOOL WUOpenMoments(UIViewController *chat) {
    if(!NSThread.isMainThread || !WUMomentsAvailable() || chat.presentedViewController) return NO;
    NSString *a=WUCurrentAccount(), *s=WUChatSession(chat); NSUInteger g=WUContextGeneration();
    if(!Current(chat,a,s,g)) return NO;
    @try {
        UIViewController *host=[[NSClassFromString(@"WCTimeLineViewController") alloc] init];
        if(!host || host.parentViewController || host.presentingViewController || !Current(chat,a,s,g)) return NO;
        WUMomentsSheet *sheet=[WUMomentsSheet new]; sheet.chat=chat; sheet.account=a; sheet.session=s; sheet.generation=g;
        sheet.content=[[UINavigationController alloc] initWithRootViewController:host];
        sheet.previousResponder=Responder(chat.view,0); [sheet.previousResponder resignFirstResponder];
        sheet.modalPresentationStyle=UIModalPresentationCustom; sheet.transitioningDelegate=sheet;
        [sheets addObject:sheet]; [chat presentViewController:sheet animated:NO completion:nil]; return YES;
    } @catch(NSException *e) { return NO; }
}

@interface WUMomentsInput : NSObject
@property(nonatomic,weak) UIViewController *chat;
@property(nonatomic,weak) UITextView *input;
@property(nonatomic,strong) id token;
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSString *session;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL consuming;
- (void)changed;
@end
@implementation WUMomentsInput
- (void)dealloc { if(_token) [NSNotificationCenter.defaultCenter removeObserver:_token]; }
- (void)changed {
    UITextView *text=self.input; UIViewController *chat=self.chat;
    if(self.consuming || !Current(chat,self.account,self.session,self.generation) || chat.presentedViewController || !WUMomentsCommand(text.text,text.markedTextRange!=nil,text.isFirstResponder,[text isDescendantOfView:chat.view])) return;
    self.consuming=YES;
    @try {
        // Exact command only, never prefix matching. Clear synchronously before any presentation.
        text.text=@""; text.selectedRange=NSMakeRange(0,0);
        id<UITextViewDelegate> delegate=text.delegate;
        if([delegate respondsToSelector:@selector(textViewDidChange:)]) [delegate textViewDidChange:text];
        [NSNotificationCenter.defaultCenter postNotificationName:UITextViewTextDidChangeNotification object:text];
        if(!WUOpenMoments(chat) && chat.viewIfLoaded.window && !chat.presentedViewController) {
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"朋友圈暂不可用" message:@"rp 已作为本地命令消费，未发送给联系人。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [chat presentViewController:alert animated:YES completion:nil];
        }
    } @catch(NSException *e) { /* No send or command replay on failure. */ }
    self.consuming=NO;
}
@end
static char inputKey;
static UITextView *ChatInput(UIView *view, BOOL inGrow, NSUInteger depth, NSUInteger *budget) {
    if(!view || depth>24 || !*budget) return nil; (*budget)--;
    Class grow=NSClassFromString(@"MMGrowTextView"); inGrow=inGrow || (grow && [view isKindOfClass:grow]);
    if(inGrow && [view isKindOfClass:UITextView.class] && [(UITextView *)view isEditable]) return (id)view;
    for(UIView *child in view.subviews) { UITextView *found=ChatInput(child,inGrow,depth+1,budget); if(found) return found; }
    return nil;
}
void WURefreshMomentsInput(UIViewController *chat) {
    if(!NSThread.isMainThread) return;
    objc_setAssociatedObject(chat,&inputKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(!WUEnabled(@"convenientMoments") || !chat.viewIfLoaded.window || chat.presentedViewController) return;
    NSUInteger budget=500; UITextView *text=ChatInput(chat.view,NO,0,&budget); if(!text) return;
    WUMomentsInput *binding=[WUMomentsInput new]; binding.chat=chat; binding.input=text;
    binding.account=WUCurrentAccount(); binding.session=WUChatSession(chat); binding.generation=WUContextGeneration();
    __weak WUMomentsInput *weak=binding;
    // Object-scoped observation, not a global text hook or replacement delegate.
    binding.token=[NSNotificationCenter.defaultCenter addObserverForName:UITextViewTextDidChangeNotification object:text queue:nil usingBlock:^(NSNotification *n){ if(NSThread.isMainThread) [weak changed]; }];
    objc_setAssociatedObject(chat,&inputKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void WUCancelMoments(void) { for(WUMomentsSheet *s in sheets.allObjects) [s closeRestoring:NO]; }
void WUInstallMoments(void) {
    static dispatch_once_t once; dispatch_once(&once,^{ sheets=[NSHashTable weakObjectsHashTable]; });
}
