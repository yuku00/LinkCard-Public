// XCTest/iOS only. UIKit is real; WK URL/JS replies and gestures are synthetic.
// No loadRequest/loadHTMLString, Photos, user articles, or external traffic.
#import <XCTest/XCTest.h>
#import "WU.h"
#include "../build/article_ui_matches.inc"
static BOOL feature=YES;
static NSUInteger epoch=1;
static NSString *testAccount=@"synthetic-account";
static NSUInteger chatReads;
NSString *const WUChanged=@"synthetic.article.changed";
id WUValue(NSString *key) { return @YES; }
BOOL WUEnabled(NSString *key) { return feature; }
NSString *WUCurrentAccount(void) { return testAccount; }
NSUInteger WUContextGeneration(void) { return epoch; }
NSUInteger WUContextGenerationSnapshot(void) { return epoch; }
NSString *WUChatSession(UIViewController *owner) { chatReads++; return nil; }
NSDictionary *WUAccountOptions(NSString *account) { return @{}; }
BOOL WUHook(NSString *a,NSString *b,BOOL c,const char *d,NSArray *e,IMP f,IMP *g) { return NO; }
#import "../Sources/WUArticleImage.m"

@interface ArticleWeb : WKWebView
@property(nonatomic,strong) NSURL *syntheticURL;
@property(nonatomic,strong) NSMutableArray *pending;
@end
@implementation ArticleWeb
- (NSURL *)URL { return self.syntheticURL; }
- (BOOL)isLoading { return NO; }
- (void)callAsyncJavaScript:(NSString *)body arguments:(NSDictionary<NSString *,id> *)arguments inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)world completionHandler:(void (^)(id,NSError *))completion {
    if(!self.pending) self.pending=[NSMutableArray array];
    if(completion) [self.pending addObject:@{@"arguments":arguments,@"reply":[completion copy]}];
}
- (void)replyFirst {
    NSDictionary *pending=self.pending.firstObject; [self.pending removeObjectAtIndex:0];
    NSDictionary *args=pending[@"arguments"];
    void (^reply)(id,NSError *)=pending[@"reply"];
    reply(@{@"token":args[@"token"],@"article":args[@"article"],@"source":@"https://mmbiz.qpic.cn/synthetic.png",@"direct":@NO,@"bytes":NSNull.null},nil);
}
@end
@interface ArticlePress : WUArticlePress
@property(nonatomic) UIGestureRecognizerState syntheticState;
@end
@implementation ArticlePress
- (UIGestureRecognizerState)state { return self.syntheticState; }
- (CGPoint)locationInView:(UIView *)view { return CGPointMake(60,80); }
@end
@interface ArticleMenu : UIContextMenuInteraction <UIContextMenuInteractionDelegate>
@property(nonatomic,strong) UIMenu *root;
@end
@implementation ArticleMenu
- (instancetype)init { return [super initWithDelegate:self]; }
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location { return nil; }
- (void)updateVisibleMenuWithBlock:(UIMenu *(^)(UIMenu *))block { self.root=block(self.root); }
@end
@interface EmoticonPickViewController : UIViewController
@property(nonatomic,strong) UIImage *m_image;
@end
@implementation EmoticonPickViewController @end
static void Pump(NSTimeInterval seconds) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
static void OriginalLayout(id web,SEL selector) {}

@interface WUArticleImageTests : XCTestCase
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIViewController *owner;
@property(nonatomic,strong) UINavigationController *nav;
@property(nonatomic,strong) ArticleWeb *web;
@property(nonatomic,strong) WUArticleImage *op;
@property(nonatomic,strong) ArticlePress *press;
@end
@implementation WUArticleImageTests
- (void)setUp {
    [super setUp]; XCTAssertTrue(NSThread.isMainThread);
    feature=YES; epoch++; testAccount=@"synthetic-account"; chatReads=0;
    WUInstallArticleImage();
    self.owner=[UIViewController new]; self.nav=[[UINavigationController alloc] initWithRootViewController:self.owner];
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window.rootViewController=self.nav; [self.window makeKeyAndVisible];
    self.web=[[ArticleWeb alloc] initWithFrame:CGRectMake(0,100,320,400)];
    self.web.syntheticURL=[NSURL URLWithString:@"https://mp.weixin.qq.com/s/synthetic"];
    self.web.scrollView.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    [self.owner.view addSubview:self.web]; [self.web layoutIfNeeded]; Pump(.05);
    self.op=[WUArticleImage new]; self.op.web=self.web; self.op.owner=self.owner;
    self.press=[ArticlePress new]; self.press.syntheticState=UIGestureRecognizerStateBegan; self.press.nativeTouch=YES; self.press.began=Now()-.6; self.op.press=self.press;
    [observers addObject:self.op];
}
- (void)tearDown {
    [self.op reset]; WUCancelImageEntries(); self.window.hidden=YES; self.window.rootViewController=nil;
    self.op=nil; self.web=nil; self.window=nil; self.nav=nil; self.owner=nil; self.press=nil;
    [super tearDown];
}
- (void)select {
    [self.op pressed:self.press]; XCTAssertEqual(self.web.pending.count,1u);
    [self.web replyFirst]; XCTAssertTrue(self.op.selected); XCTAssertTrue([self.op current:NO]);
}
- (void)testNativeGestureGateNoAutomaticRequest {
    self.press.nativeTouch=NO; [self.op pressed:self.press]; XCTAssertEqual(self.web.pending.count,0u);
    self.press.nativeTouch=YES; self.press.syntheticState=UIGestureRecognizerStatePossible; [self.op pressed:self.press]; XCTAssertEqual(self.web.pending.count,0u);
    self.press.syntheticState=UIGestureRecognizerStateBegan; self.press.began=Now(); [self.op pressed:self.press]; XCTAssertEqual(self.web.pending.count,0u);
    self.press.began=Now()-.6; [self select]; XCTAssertNil(self.op.fetch); XCTAssertFalse(self.op.reading); XCTAssertNil(self.op.prompt);
    XCTAssertFalse([self.press canPreventGestureRecognizer:[UIGestureRecognizer new]]);
    XCTAssertFalse([self.press canBePreventedByGestureRecognizer:[UIGestureRecognizer new]]);
    XCTAssertTrue([self.op gestureRecognizer:self.press shouldRecognizeSimultaneouslyWithGestureRecognizer:[UIGestureRecognizer new]]);
}
- (void)testOriginalMenuAndButtonsRemainIdentical {
    UIBarButtonItem *host=[[UIBarButtonItem alloc] initWithTitle:@"host" style:UIBarButtonItemStylePlain target:nil action:nil]; self.owner.navigationItem.rightBarButtonItems=@[host];
    UIAction *original=[UIAction actionWithTitle:@"host-action" image:nil identifier:@"host-action" handler:^(UIAction *a){}];
    ArticleMenu *menu=[ArticleMenu new]; menu.root=[UIMenu menuWithTitle:@"host" children:@[original]]; [self.web addInteraction:menu];
    [self select]; XCTAssertTrue(self.op.menuAdded); XCTAssertEqual(menu.root.children.firstObject,original); XCTAssertEqual(menu.root.children.count,2u);
    [self.op reset]; XCTAssertEqual(menu.root.children.count,1u); XCTAssertEqual(menu.root.children.firstObject,original); XCTAssertEqualObjects(self.owner.navigationItem.rightBarButtonItems,@[host]);
}
- (void)testIndependentButtonExpiresWithoutReplacingHost {
    UIBarButtonItem *host=[[UIBarButtonItem alloc] initWithTitle:@"host" style:UIBarButtonItemStylePlain target:nil action:nil]; self.owner.navigationItem.rightBarButtonItems=@[host];
    [self select]; Pump(.3); XCTAssertEqual(self.owner.navigationItem.rightBarButtonItems.firstObject,host); XCTAssertEqual(self.owner.navigationItem.rightBarButtonItems.count,2u);
    self.op.deadline=Now()-1; [self.op.timer fire]; XCTAssertNil(self.op.token); XCTAssertEqualObjects(self.owner.navigationItem.rightBarButtonItems,@[host]);
}
- (void)testLateDOMReplyCannotReplaceNewSelection {
    [self.op pressed:self.press]; NSString *old=self.op.token; [self.op reset]; self.op.token=@"new-native-token";
    [self.web replyFirst]; XCTAssertEqualObjects(self.op.token,@"new-native-token"); XCTAssertFalse(self.op.selected); XCTAssertFalse([self.op.token isEqual:old]);
}
- (void)testNavigationScrollAccountAndGenerationInvalidation {
    [self select]; epoch++; XCTAssertFalse([self.op current:NO]); [self.op.timer fire]; XCTAssertNil(self.op.token);
    [self select]; testAccount=@"other-account"; [self.op.timer fire]; XCTAssertNil(self.op.token); testAccount=@"synthetic-account";
    [self select]; [self.web willChangeValueForKey:@"URL"]; self.web.syntheticURL=[NSURL URLWithString:@"https://mp.weixin.qq.com/s/other"]; [self.web didChangeValueForKey:@"URL"]; XCTAssertNil(self.op.token);
    self.web.syntheticURL=[NSURL URLWithString:@"https://mp.weixin.qq.com/s/synthetic"];
    [self select]; self.web.scrollView.contentSize=CGSizeMake(320,900); self.web.scrollView.contentOffset=CGPointMake(0,1); self.web.scrollView.contentOffset=CGPointZero; XCTAssertNil(self.op.token);
    [self select]; [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil]; XCTAssertNil(self.op.token); XCTAssertTrue(self.op.stopped);
}
- (void)testOwnEditorDoesNotRequireChatAndDoesNotPopOtherPage {
    [self select];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(2,2)];
    NSData *png=[renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *context){ [UIColor.redColor setFill]; UIRectFill(CGRectMake(0,0,2,2)); }];
    __weak WUArticleImage *weak=self.op;
    self.op.opening=YES;
    XCTAssertTrue(WUOpenConfirmedImageDataEditor(self.owner,png,^BOOL(BOOL editing){ return [weak current:editing]; }));
    self.op.opening=NO; self.op.editing=YES;
    XCTAssertTrue([self.nav.topViewController isKindOfClass:EmoticonPickViewController.class]); XCTAssertEqual(chatReads,0u);
    UIViewController *editor=self.nav.topViewController; UIViewController *unrelated=[UIViewController new];
    [self.nav pushViewController:unrelated animated:NO]; [self.op reset];
    XCTAssertEqual(self.nav.topViewController,unrelated); XCTAssertFalse([self.nav.viewControllers containsObject:editor]); XCTAssertTrue([self.nav.viewControllers containsObject:self.owner]);
}
- (void)testUnrelatedPresentationIsNotDismissed {
    [self select]; UIViewController *other=[UIViewController new]; [self.owner presentViewController:other animated:NO completion:nil];
    self.op.prompt=[UIViewController new]; [self.op reset]; XCTAssertEqual(self.owner.presentedViewController,other);
    [other dismissViewControllerAnimated:NO completion:nil];
}
- (void)testLayoutOnlyAttachesForArticleAndNeverEvaluatesDOM {
    originalLayout=(IMP)OriginalLayout;
    self.web.syntheticURL=[NSURL URLWithString:@"https://example.invalid/s/not-an-article"];
    ArticleLayout(self.web,@selector(layoutSubviews)); XCTAssertNil(objc_getAssociatedObject(self.web,&ArticleKey)); XCTAssertEqual(self.web.pending.count,0u);
    self.web.syntheticURL=[NSURL URLWithString:@"https://mp.weixin.qq.com/s/synthetic"];
    feature=NO; ArticleLayout(self.web,@selector(layoutSubviews)); XCTAssertNil(objc_getAssociatedObject(self.web,&ArticleKey));
    feature=YES; ArticleLayout(self.web,@selector(layoutSubviews)); WUArticleImage *attached=objc_getAssociatedObject(self.web,&ArticleKey); XCTAssertNotNil(attached); XCTAssertEqual(self.web.pending.count,0u);
    XCTAssertFalse(attached.press.cancelsTouchesInView); XCTAssertFalse(attached.press.delaysTouchesBegan); XCTAssertFalse(attached.press.delaysTouchesEnded);
    [attached dispose]; XCTAssertNil(objc_getAssociatedObject(self.web,&ArticleKey));
    UIViewController *child=[UIViewController new]; [self.owner addChildViewController:child]; child.view.frame=self.owner.view.bounds; [self.owner.view addSubview:child.view]; [child didMoveToParentViewController:self.owner]; [child.view addSubview:self.web];
    XCTAssertEqual(Owner(self.web),self.owner); // Public containment, not a chat-session or label guess.
}
@end
