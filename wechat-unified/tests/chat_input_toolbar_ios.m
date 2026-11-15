// XCTest with real UIKit and synthetic host classes; does not load WeChat.
#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
@interface MMInputToolView : UIView @end
@implementation MMInputToolView @end
@interface InputToolContainerView : UIView @end
@implementation InputToolContainerView @end
@interface InputToolViewBar : UIView @end
@implementation InputToolViewBar @end
static UIViewController *Chat(UIView *view) {
    for(UIResponder *r=view;r;r=r.nextResponder) if([r isKindOfClass:UIViewController.class]) return (UIViewController *)r;
    return nil;
}
#import "../Sources/ChatInputToolbar.inc"
@interface WUInputToolbarTests : XCTestCase @end
@implementation WUInputToolbarTests
- (void)testObservedChainAndOwnerContainment {
    UIViewController *owner=[UIViewController new], *other=[UIViewController new];
    MMInputToolView *tool=[MMInputToolView new]; InputToolContainerView *container=[InputToolContainerView new]; InputToolViewBar *bar=[InputToolViewBar new];
    [owner.view addSubview:tool]; [tool addSubview:container]; [container addSubview:bar];
    XCTAssertEqual(WUInputBarForOwner(owner),bar); XCTAssertNil(WUInputBarForOwner(other));
    [container addSubview:[InputToolViewBar new]]; XCTAssertNil(WUInputBarForOwner(owner));
}
- (void)testNativeButtonsAndAnchoredLayout {
    __block NSUInteger taps=0; WUInputToolbar *toolbar=[[WUInputToolbar alloc] initWithEntries:@[@{@"title":@"搜索",@"run":^{ taps++; }}]];
    UIView *root=[[UIView alloc] initWithFrame:CGRectMake(0,0,320,640)], *bar=[UIView new]; bar.translatesAutoresizingMaskIntoConstraints=NO; toolbar.translatesAutoresizingMaskIntoConstraints=NO;
    [root addSubview:bar]; [root addSubview:toolbar]; NSLayoutConstraint *top=[bar.topAnchor constraintEqualToAnchor:root.topAnchor constant:500];
    [NSLayoutConstraint activateConstraints:@[top,[bar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[bar.widthAnchor constraintEqualToConstant:320],[bar.heightAnchor constraintEqualToConstant:50],[toolbar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[toolbar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[toolbar.bottomAnchor constraintEqualToAnchor:bar.topAnchor],[toolbar.heightAnchor constraintEqualToConstant:44]]];
    [root layoutIfNeeded]; XCTAssertEqualWithAccuracy(CGRectGetMaxY(toolbar.frame),500,0.1);
    top.constant=300; root.frame=CGRectMake(0,0,640,320); [root layoutIfNeeded]; XCTAssertEqualWithAccuracy(CGRectGetMaxY(toolbar.frame),300,0.1); XCTAssertEqualWithAccuracy(toolbar.bounds.size.width,640,0.1);
    UIScrollView *scroll=(id)toolbar.subviews.firstObject; UIStackView *stack=(id)scroll.subviews.firstObject; UIButton *button=(id)stack.arrangedSubviews.firstObject;
    [button sendActionsForControlEvents:UIControlEventTouchUpInside]; XCTAssertEqual(taps,1u);
    [toolbar removeFromSuperview]; XCTAssertNil(toolbar.superview); XCTAssertEqual(bar.superview,root);
}
@end
