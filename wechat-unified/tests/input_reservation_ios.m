// XCTest mock: no WeChat or external plugin code.
#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
@interface MMInputToolView : UIView
@property(nonatomic,strong) UIView *panel;
- (double)getGroupUndoneBarHeight;
- (UIView *)toolPanelView;
@end
@implementation MMInputToolView
- (double)getGroupUndoneBarHeight { return 0; }
- (UIView *)toolPanelView { return self.panel; }
@end
@interface MMTableView : UIScrollView @end
@implementation MMTableView @end
@interface InputToolContainerView : UIView @end
@implementation InputToolContainerView @end
@interface InputToolViewBar : UIView @end
@implementation InputToolViewBar @end
static UIViewController *Chat(UIView *v) { for(UIResponder *r=v;r;r=r.nextResponder) if([r isKindOfClass:UIViewController.class]) return (id)r; return nil; }
static BOOL WUHook(NSString *cls, NSString *sel, BOOL meta, const char *ret, NSArray *args, IMP replacement, IMP *original) {
    Method m=class_getInstanceMethod(NSClassFromString(cls),NSSelectorFromString(sel));
    if(!m || meta || strcmp(ret,"d") || args.count) return NO;
    *original=method_setImplementation(m,replacement); return *original!=NULL;
}
#import "../Sources/ChatInputToolbar.inc"
#import "../Sources/WUInputReservation.inc"
@interface WUMockInputOwner : UIViewController
@property(nonatomic,strong) MMInputToolView *tool;
@property(nonatomic,strong) InputToolContainerView *container;
@property(nonatomic,strong) MMTableView *table;
@property(nonatomic) BOOL reserves, reservesInset;
@end
@implementation WUMockInputOwner
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat extra=self.reserves?[self.tool getGroupUndoneBarHeight]:0;
    self.tool.frame=CGRectMake(0,0,390,844);
    self.table.frame=self.tool.frame;
    self.table.contentInset=UIEdgeInsetsMake(91,0,90+(self.reservesInset?extra:0),0);
    self.container.frame=CGRectMake(0,754-extra,390,90+extra);
    self.container.subviews.firstObject.frame=CGRectMake(0,extra,390,56);
}
@end
@interface WUInputReservationTests : XCTestCase @end
@implementation WUInputReservationTests
- (WUMockInputOwner *)fixture:(BOOL)reserves window:(UIWindow **)outWindow {
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,390,844)];
    WUMockInputOwner *owner=[WUMockInputOwner new]; owner.reserves=reserves; owner.reservesInset=YES; window.rootViewController=owner; [window makeKeyAndVisible];
    owner.tool=[MMInputToolView new]; owner.container=[InputToolContainerView new];
    UIImageView *background=[[UIImageView alloc] initWithFrame:owner.view.bounds];
    [owner.view addSubview:background];
    owner.table=[MMTableView new]; owner.table.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever; [owner.view addSubview:owner.table];
    owner.tool.panel=owner.container; [owner.view addSubview:owner.tool]; [owner.tool addSubview:owner.container];
    InputToolViewBar *bar=[[InputToolViewBar alloc] initWithFrame:CGRectMake(0,0,320,50)]; [owner.container addSubview:bar];
    [owner.view setNeedsLayout]; [owner.view layoutIfNeeded]; *outWindow=window; return owner;
}
- (void)afterMain:(dispatch_block_t)block {
    XCTestExpectation *done=[self expectationWithDescription:@"layout adapter"];
    dispatch_async(dispatch_get_main_queue(),^{ block(); [done fulfill]; });
    [self waitForExpectations:@[done] timeout:2];
}
- (void)testReservationAndRemoval {
    UIWindow *window; WUMockInputOwner *owner=[self fixture:YES window:&window];
    WUInputSync(owner,@[@{@"title":@"搜索",@"run":^{}}]);
    [self afterMain:^{
        WUInputReservation *s=objc_getAssociatedObject(owner,&WUInputStateKey);
        XCTAssertTrue(s.ready); XCTAssertEqualWithAccuracy(owner.tool.frame.origin.y,0,0.1);
        XCTAssertEqualWithAccuracy(owner.container.frame.origin.y,710,0.1);
        XCTAssertEqualWithAccuracy(s.bar.frame.origin.y,44,0.1);
        XCTAssertEqualWithAccuracy(s.toolbar.frame.origin.y,0,0.1);
        XCTAssertEqualWithAccuracy([owner.tool getGroupUndoneBarHeight],44,0.1);
        WUInputRemove(owner); XCTAssertNil(s.toolbar.superview); XCTAssertEqualWithAccuracy([owner.tool getGroupUndoneBarHeight],0,0.1);
        [owner.view layoutIfNeeded]; XCTAssertEqualWithAccuracy(owner.container.frame.origin.y,754,0.1);
    }]; window.hidden=YES;
}
- (void)testUnsupportedLayoutRollsBackAndDoesNotRetry {
    UIWindow *window; WUMockInputOwner *owner=[self fixture:NO window:&window];
    WUInputSync(owner,@[@{@"title":@"搜索",@"run":^{}}]);
    [self afterMain:^{
        XCTAssertNil(objc_getAssociatedObject(owner,&WUInputStateKey));
        XCTAssertEqualWithAccuracy([owner.tool getGroupUndoneBarHeight],0,0.1);
        WUInputSync(owner,@[@{@"title":@"搜索",@"run":^{}}]);
        XCTAssertNil(objc_getAssociatedObject(owner,&WUInputStateKey));
        WUInputRemove(owner);
    }]; window.hidden=YES;
}
- (void)testUnreservedTableRollsBack {
    UIWindow *window; WUMockInputOwner *owner=[self fixture:YES window:&window];
    owner.reservesInset=NO;
    WUInputSync(owner,@[@{@"title":@"搜索",@"run":^{}}]);
    [self afterMain:^{
        XCTAssertNil(objc_getAssociatedObject(owner,&WUInputStateKey));
        XCTAssertEqualWithAccuracy([owner.tool getGroupUndoneBarHeight],0,0.1);
        [owner.view layoutIfNeeded];
        XCTAssertEqualWithAccuracy(owner.container.frame.origin.y,754,0.1);
    }]; window.hidden=YES;
}
- (void)testReservedStripCoveredByHostRollsBack {
    UIWindow *window; WUMockInputOwner *owner=[self fixture:YES window:&window];
    UIView *obstacle=[[UIView alloc] initWithFrame:CGRectMake(0,715,390,20)]; [owner.view addSubview:obstacle];
    WUInputSync(owner,@[@{@"title":@"搜索",@"run":^{}}]);
    [self afterMain:^{
        XCTAssertNil(objc_getAssociatedObject(owner,&WUInputStateKey));
        XCTAssertEqualWithAccuracy([owner.tool getGroupUndoneBarHeight],0,0.1);
        XCTAssertEqual([owner.view hitTest:CGPointMake(10,720) withEvent:nil],obstacle);
    }]; window.hidden=YES;
}
- (void)testInvalidatedContextBeforeDeferredValidation {
    UIWindow *window; WUMockInputOwner *owner=[self fixture:YES window:&window];
    __block BOOL current=YES;
    WUInputSyncChecked(owner,@[@{@"title":@"搜索",@"run":^{}}],^BOOL{ return current; });
    current=NO;
    [self afterMain:^{
        XCTAssertNil(objc_getAssociatedObject(owner,&WUInputStateKey));
        XCTAssertEqualWithAccuracy([owner.tool getGroupUndoneBarHeight],0,0.1);
        XCTAssertNil([owner.tool.subviews filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *bindings){ return [obj isKindOfClass:WUInputToolbar.class]; }]].firstObject);
    }]; window.hidden=YES;
}
- (void)testRemovalBeforeDeferredValidation {
    UIWindow *window; WUMockInputOwner *owner=[self fixture:YES window:&window];
    WUInputSync(owner,@[@{@"title":@"搜索",@"run":^{}}]); WUInputRemove(owner);
    [self afterMain:^{ XCTAssertNil(objc_getAssociatedObject(owner,&WUInputStateKey)); XCTAssertEqualWithAccuracy([owner.tool getGroupUndoneBarHeight],0,0.1); }];
    window.hidden=YES;
}
@end
