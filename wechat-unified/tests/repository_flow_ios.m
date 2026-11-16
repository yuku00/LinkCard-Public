// Real Repository.m + RepositoryLogic.m; synthetic UIAlertAction activation and sender.
#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "Repository.h"

static NSMapTable *handlers;
static NSHashTable *completedPresentations;
@interface UIViewController (WURepositoryPresentationTest)
- (void)wu_repoPresent:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion;
@end
@implementation UIViewController (WURepositoryPresentationTest)
- (void)wu_repoPresent:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    [self wu_repoPresent:controller animated:animated completion:^{ if(completion) completion(); [completedPresentations addObject:controller]; }];
}
@end
static void SwapPresentation(void) {
    method_exchangeImplementations(class_getInstanceMethod(UIViewController.class,@selector(presentViewController:animated:completion:)),class_getInstanceMethod(UIViewController.class,@selector(wu_repoPresent:animated:completion:)));
}
@interface UIAlertAction (WURepositoryTest)
+ (instancetype)wu_repoAction:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler;
@end
@implementation UIAlertAction (WURepositoryTest)
+ (instancetype)wu_repoAction:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler {
    UIAlertAction *a=[self wu_repoAction:title style:style handler:handler];
    if(handler) [handlers setObject:[handler copy] forKey:a]; return a;
}
@end
static void Pump(NSTimeInterval seconds) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
static void Swap(void) {
    method_exchangeImplementations(class_getClassMethod(UIAlertAction.class,@selector(actionWithTitle:style:handler:)),class_getClassMethod(UIAlertAction.class,@selector(wu_repoAction:style:handler:)));
}
@interface WURepositoryFlowTests : XCTestCase
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIViewController *owner;
@property(nonatomic,strong) WURepositoryBinding *binding;
@property(nonatomic,copy) NSString *account;
@property(nonatomic) NSUInteger sends;
@end
@implementation WURepositoryFlowTests
+ (void)setUp { [super setUp]; handlers=[NSMapTable weakToStrongObjectsMapTable]; completedPresentations=[NSHashTable weakObjectsHashTable]; Swap(); SwapPresentation(); }
+ (void)tearDown { SwapPresentation(); Swap(); completedPresentations=nil; handlers=nil; [super tearDown]; }
- (void)setUp {
    [super setUp]; self.account=[@"WU-Test-" stringByAppendingString:NSUUID.UUID.UUIDString];
    self.owner=[UIViewController new]; self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=self.owner; [self.window makeKeyAndVisible]; Pump(.1);
    self.binding=[WURepositoryBinding new]; self.binding.account=self.account; self.binding.target=@"synthetic-target";
    self.binding.current=^BOOL{ return YES; };
    __weak WURepositoryFlowTests *weak=self;
    self.binding.send=^NSString *(NSDictionary *part){ weak.sends++; return @"已请求（非送达）"; };
    self.binding.capture=^NSArray *{ return @[@{@"kind":@"reference", @"identity":@{@"from":@"synthetic-account", @"to":@"filehelper", @"real":@"", @"local":@1, @"type":@1, @"time":@1, @"id":@1}}]; };
}
- (NSURL *)directory { return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"WeChatUnified/Repository" isDirectory:YES]; }
- (void)tearDown {
    [self.owner dismissViewControllerAnimated:NO completion:nil]; Pump(.1);
    NSMutableString *hex=[NSMutableString string]; NSData *bytes=[self.account dataUsingEncoding:NSUTF8StringEncoding];
    const unsigned char *p=bytes.bytes; for(NSUInteger i=0;i<bytes.length;i++) [hex appendFormat:@"%02x",p[i]];
    NSURL *file=[[self directory] URLByAppendingPathComponent:[hex stringByAppendingString:@".plist"]];
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    self.window.hidden=YES; self.window.rootViewController=nil; self.window=nil; self.owner=nil; self.binding=nil; [super tearDown];
}
- (UITableViewController *)openRepository {
    WUShowRepository(self.owner,self.binding); Pump(.8);
    UINavigationController *nav=(id)self.owner.presentedViewController;
    XCTAssertTrue([nav isKindOfClass:UINavigationController.class]);
    XCTAssertTrue(WUIsRepositoryController(nav)); return (id)nav.topViewController;
}
- (UIAlertController *)alert:(UIViewController *)controller {
    Pump(.7); UIAlertController *a=(id)controller.presentedViewController;
    XCTAssertTrue([a isKindOfClass:UIAlertController.class]);
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
    while(a && ![completedPresentations containsObject:a] && deadline.timeIntervalSinceNow>0) Pump(.01);
    XCTAssertTrue([completedPresentations containsObject:a], @"Alert presentation did not complete"); return a;
}
- (void)activate:(NSString *)title alert:(UIAlertController *)alert {
    UIAlertAction *chosen=nil; for(UIAlertAction *a in alert.actions) if([a.title isEqualToString:title]) chosen=a;
    XCTAssertNotNil(chosen); void (^handler)(UIAlertAction *)=[handlers objectForKey:chosen]; XCTAssertNotNil(handler);
    if(handler) handler(chosen); Pump(.8);
}
- (void)testTextSaveCloseAndReopen {
    UITableViewController *repo=[self openRepository];
    [UIApplication.sharedApplication sendAction:NSSelectorFromString(@"newText") to:repo from:nil forEvent:nil];
    UIAlertController *alert=[self alert:repo]; XCTAssertEqual(alert.textFields.count,2u);
    alert.textFields[0].text=@"synthetic-name"; alert.textFields[1].text=@"synthetic-body";
    [self activate:@"保存" alert:alert];
    NSError *error=nil; NSArray *disk=WURepositoryLoad([self directory],self.account,&error);
    XCTAssertNil(error); XCTAssertEqual(disk.count,1u); XCTAssertEqualObjects(disk.firstObject[@"name"],@"synthetic-name");
    XCTAssertEqualObjects(disk.firstObject[@"parts"][0][@"text"],@"synthetic-body");
    [UIApplication.sharedApplication sendAction:NSSelectorFromString(@"close") to:repo from:nil forEvent:nil]; Pump(.8);
    XCTAssertNil(self.owner.presentedViewController); repo=[self openRepository];
    XCTAssertEqual([repo tableView:repo.tableView numberOfRowsInSection:0],1);
    UITableViewCell *cell=[repo tableView:repo.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    XCTAssertEqualObjects(cell.textLabel.text,@"synthetic-name");
}
- (void)testCaptureAndConfirmedSend {
    UITableViewController *repo=[self openRepository];
    [UIApplication.sharedApplication sendAction:NSSelectorFromString(@"capture") to:repo from:nil forEvent:nil];
    UIAlertController *capture=[self alert:repo]; capture.textFields.firstObject.text=@"captured";
    [self activate:@"保存引用" alert:capture];
    XCTAssertEqual(WURepositoryLoad([self directory],self.account,NULL).count,1u);
    [repo tableView:repo.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    [UIApplication.sharedApplication sendAction:NSSelectorFromString(@"confirmSend") to:repo from:nil forEvent:nil];
    UIAlertController *confirmation=[self alert:repo]; XCTAssertTrue([confirmation.message containsString:@"synthetic-target"]); XCTAssertEqual(self.sends,0u);
    [self activate:@"确认请求" alert:confirmation]; XCTAssertEqual(self.sends,1u);
}
@end
