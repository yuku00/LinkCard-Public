// UIKit/XCTest regression: real controllers and production parser/flow, synthetic alert activation and openURL.
#import <XCTest/XCTest.h>
#import <SafariServices/SafariServices.h>
#import <objc/runtime.h>
#import "MessageEntries.h"
#import "WUDiagnostics.h"

NSString *const WUChanged=@"test.changed";
id WUValue(NSString *key) { return @YES; }
BOOL WUSave(NSString *key,id value) { return YES; }
NSString *WUCurrentAccount(void) { return @"test"; }
NSUInteger WUContextGeneration(void) { return 1; }
NSData *WUEmoticonRead(NSString *path) { return nil; }
NSString *WUEmoticonType(NSData *data) { return nil; }
BOOL WUThemeValidImage(NSData *data) { return NO; }
void WURecordDiagnosticEvent(WUDiagnosticEvent event) {}

static NSMapTable *handlers;
static NSURL *opened;
static void (^openReply)(BOOL);
@interface UIAlertAction (WULinkTest)
+ (instancetype)wu_action:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler;
@end
@implementation UIAlertAction (WULinkTest)
+ (instancetype)wu_action:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler {
    UIAlertAction *a=[self wu_action:title style:style handler:handler];
    if(handler) [handlers setObject:[handler copy] forKey:a];
    return a;
}
@end
@interface UIApplication (WULinkTest)
- (void)wu_open:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion;
@end
@implementation UIApplication (WULinkTest)
- (void)wu_open:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion {
    opened=url; openReply=[completion copy];
}
@end
static void Pump(NSTimeInterval t) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:t]]; }
static void Swap(Class c, SEL a, SEL b, BOOL classMethod) {
    Method x=classMethod?class_getClassMethod(c,a):class_getInstanceMethod(c,a);
    Method y=classMethod?class_getClassMethod(c,b):class_getInstanceMethod(c,b);
    method_exchangeImplementations(x,y);
}
@interface WULinkFlowTests : XCTestCase
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIViewController *owner;
@property(nonatomic,strong) UINavigationController *nav;
@end
@implementation WULinkFlowTests
+ (void)setUp {
    [super setUp]; handlers=[NSMapTable weakToStrongObjectsMapTable];
    Swap(UIAlertAction.class,@selector(actionWithTitle:style:handler:),@selector(wu_action:style:handler:),YES);
    Swap(UIApplication.class,@selector(openURL:options:completionHandler:),@selector(wu_open:options:completionHandler:),NO);
}
+ (void)tearDown {
    Swap(UIApplication.class,@selector(openURL:options:completionHandler:),@selector(wu_open:options:completionHandler:),NO);
    Swap(UIAlertAction.class,@selector(actionWithTitle:style:handler:),@selector(wu_action:style:handler:),YES);
    handlers=nil; [super tearDown];
}
- (void)setUp {
    [super setUp]; opened=nil; openReply=nil;
    self.owner=[UIViewController new]; self.nav=[[UINavigationController alloc] initWithRootViewController:self.owner];
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window.rootViewController=self.nav;
    [self.window makeKeyAndVisible]; Pump(.1);
}
- (void)tearDown {
    WUCancelMessageEntries(); Pump(.1); openReply=nil; self.window.hidden=YES; self.window.rootViewController=nil;
    self.window=nil; self.owner=nil; self.nav=nil; [super tearDown];
}
- (void)start {
    WUOpenSelectedLinks(self.owner,@[@{@"type":@1,@"content":@"https://example.com/a https://example.org/b"}],^BOOL{ return YES; });
    Pump(.7);
}
- (UIAlertController *)alert {
    UIViewController *c=self.owner.presentedViewController;
    XCTAssertTrue([c isKindOfClass:UIAlertController.class]);
    return (UIAlertController *)c;
}
- (void)choose:(NSString *)title {
    UIAlertController *a=[self alert]; UIAlertAction *chosen=nil;
    for(UIAlertAction *item in a.actions) if([item.title containsString:title]) { chosen=item; break; }
    XCTAssertNotNil(chosen); void (^handler)(UIAlertAction *)=[handlers objectForKey:chosen];
    XCTAssertNotNil(handler); if(handler) handler(chosen); Pump(.7);
}
- (void)testMultipleAndCancel {
    [self start]; XCTAssertEqual([self alert].actions.count,3u);
    [self choose:@"example.org/b"]; XCTAssertTrue([[self alert].message containsString:@"example.org"]);
    [self choose:@"取消"]; XCTAssertNil(self.owner.presentedViewController); XCTAssertNil(opened);
}
- (void)testSystemAcceptedAndRejected {
    [self start]; [self choose:@"example.com/a"]; [self choose:@"系统默认浏览器"];
    XCTAssertEqualObjects(opened.absoluteString,@"https://example.com/a"); XCTAssertNotNil(openReply);
    if(openReply) openReply(NO); Pump(.7); XCTAssertTrue([[self alert].message containsString:@"未接受"]);
    [self choose:@"好"]; XCTAssertNil(self.owner.presentedViewController);
    opened=nil; openReply=nil; [self start]; [self choose:@"example.org/b"]; [self choose:@"系统默认浏览器"];
    if(openReply) openReply(YES); Pump(.7); XCTAssertNil(self.owner.presentedViewController);
}
- (void)testSafariDelegateAndNestedPresentation {
    [self start]; [self choose:@"example.com/a"]; [self choose:@"内置 Safari"];
    SFSafariViewController *safari=(id)self.owner.presentedViewController;
    XCTAssertTrue([safari isKindOfClass:SFSafariViewController.class]);
    XCTAssertNotNil(safari.delegate); XCTAssertTrue(WUMessageEntriesOwnsController(safari));
    UIViewController *nested=[UIViewController new]; [safari presentViewController:nested animated:NO completion:nil]; Pump(.2);
    [safari.delegate safariViewControllerDidFinish:safari]; Pump(.3);
    XCTAssertNil(self.owner.presentedViewController); XCTAssertFalse(WUMessageEntriesOwnsController(safari));
}
- (void)testResignAndLateSystemReply {
    [self start]; [self choose:@"example.com/a"]; [self choose:@"系统默认浏览器"];
    void (^reply)(BOOL)=[openReply copy]; XCTAssertNotNil(reply);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil]; Pump(.2);
    if(reply) reply(NO); Pump(.4); XCTAssertNil(self.owner.presentedViewController);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)testLeavingOwnerAndDismissDelegate {
    [self start]; UIAlertController *a=[self alert]; id<UIAdaptivePresentationControllerDelegate> delegate=a.presentationController.delegate;
    XCTAssertNotNil(delegate); [delegate presentationControllerDidDismiss:a.presentationController]; Pump(.3);
    XCTAssertNil(self.owner.presentedViewController);
    [self start]; [self.nav pushViewController:[UIViewController new] animated:NO]; Pump(.5);
    XCTAssertNil(self.owner.presentedViewController);
}
@end
