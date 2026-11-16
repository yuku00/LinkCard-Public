// Synthetic UIKit hierarchy: tests production card helper, not host-app acceptance.
#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import "../Sources/WUNeoSettings.h"

@interface WUNeoTestController : UITableViewController @end
@implementation WUNeoTestController
- (void)viewDidLoad { [super viewDidLoad]; WUNeoPrepareTable(self); }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return 3; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=@"功能选项";
    cell.detailTextLabel.text=path.row==0 ? nil : (path.row==2 ? @"支持动态字体，较长的说明应当自动换行，保持文字和开关完整显示。支持动态字体，较长的说明应当自动换行。" : @"支持动态字体");
    if(path.row==1) cell.accessoryView=[UISwitch new];
    return WUNeoCell(cell,@"gearshape");
}
@end
@interface WUNeoPreviewController : UITableViewController @end
@implementation WUNeoPreviewController
- (void)viewDidLoad { [super viewDidLoad]; WUNeoPrepareTable(self); }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return 1; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=@"这是很长的主题名称，必须完整显示而不能被固定高度裁切。这是很长的主题名称，必须完整显示而不能被固定高度裁切。这是很长的主题名称，必须完整显示而不能被固定高度裁切。";
    cell.detailTextLabel.text=@"主题预览 · 本地资源";
    cell.imageView.image=[UIImage systemImageNamed:@"photo"];
    cell.imageView.contentMode=UIViewContentModeScaleAspectFit;
    NSLayoutConstraint *minimum=[cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:148];
    minimum.priority=999; minimum.active=YES;
    return WUNeoCell(cell,@"paintpalette");
}
@end

@interface WUNeoLongSubtitleController : UITableViewController @end
@implementation WUNeoLongSubtitleController
- (void)viewDidLoad { [super viewDidLoad]; WUNeoPrepareTable(self); }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return 3; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UILabel *title, *detail; UIImageView *icon;
    WUNeoSubtitleContent(cell,&title,&detail,&icon);
    title.tag=1001; detail.tag=1002; icon.tag=1003;
    icon.image=[UIImage systemImageNamed:@"waveform"];
    title.text=path.row==0 ? @"公众号单图 → 表情编辑（手动确认）" : (path.row==1 ? @"语音真实播放进度（本地）" : @"语音：显示PCM实测时长");
    detail.text=path.row==0 ? @"仅微信已打开的mp.weixin.qq.com文章：实际长按一张已加载图片，在原菜单或12秒导航按钮选择，再确认来源与预览。只支持可核验未缩放布局的静态PNG/JPEG；GIF/APNG、iframe、未知布局拒绝。联网只在你确认后请求一张，无Cookie/账号凭据，不代表已添加表情。" : @"仅在兼容接口和气泡留有安全空间时显示；单条不满足条件则保持微信原样。支持关闭总开关。";
    UISwitch *toggle=[UISwitch new]; toggle.accessibilityLabel=title.text; toggle.accessibilityHint=detail.text;
    cell.accessoryView=toggle; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    return WUNeoCell(cell,nil);
}
@end

static UIView *WUNeoFindView(UIView *root, NSString *identifier) {
    if([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for(UIView *subview in root.subviews) { UIView *found=WUNeoFindView(subview,identifier); if(found) return found; }
    return nil;
}

@interface WUNeoCardTests : XCTestCase @end
@implementation WUNeoCardTests
- (void)testProductionCards {
    for (NSNumber *style in @[@(UIUserInterfaceStyleLight),@(UIUserInterfaceStyleDark)]) {
        WUNeoTestController *vc=[[WUNeoTestController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        vc.overrideUserInterfaceStyle=style.integerValue;
        UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,390,844)];
        window.rootViewController=vc; [window makeKeyAndVisible];
        [vc.view layoutIfNeeded]; [vc.tableView reloadData]; [vc.tableView layoutIfNeeded];
        XCTAssertEqual(vc.tableView.style,UITableViewStylePlain);
        XCTAssertEqual(vc.tableView.delegate,vc); XCTAssertEqual(vc.tableView.dataSource,vc);
        for (NSInteger row=0;row<3;row++) {
            UITableViewCell *cell=[vc.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
            XCTAssertNotNil(cell); [cell layoutIfNeeded]; [cell.backgroundView layoutIfNeeded];
            UIView *card=cell.backgroundView.subviews.firstObject;
            XCTAssertNotNil(card); XCTAssertEqualWithAccuracy(card.layer.cornerRadius,16,0.01);
            XCTAssertGreaterThanOrEqual(CGRectGetHeight(cell.bounds),63.5);
            XCTAssertFalse(card.userInteractionEnabled);
            if(row==0) XCTAssertGreaterThan(CGRectGetHeight(card.bounds), 2*card.layer.cornerRadius);
            XCTAssertEqualWithAccuracy(CGRectGetMinX(card.frame),16,0.5);
            XCTAssertEqualWithAccuracy(CGRectGetMinY(card.frame),4,0.5);
            XCTAssertEqualWithAccuracy(CGRectGetMaxX(card.frame),CGRectGetWidth(cell.backgroundView.bounds)-16,0.5);
            XCTAssertEqualWithAccuracy(CGRectGetMaxY(card.frame),CGRectGetHeight(cell.backgroundView.bounds)-4,0.5);
            XCTAssertEqual(card.layer.maskedCorners,(CACornerMask)15);
            XCTAssertNotNil(cell.selectedBackgroundView.subviews.firstObject);
            XCTAssertTrue(cell.textLabel.adjustsFontForContentSizeCategory);
            if(row==1) {
                UISwitch *toggle=(UISwitch *)cell.accessoryView;
                XCTAssertEqualObjects(toggle.accessibilityLabel,@"功能选项");
                CGPoint center=[toggle convertPoint:CGPointMake(CGRectGetMidX(toggle.bounds),CGRectGetMidY(toggle.bounds)) toView:cell];
                UIView *hit=[cell hitTest:center withEvent:nil];
                XCTAssertTrue(hit==toggle || [hit isDescendantOfView:toggle]);
            }
            if(row==2) {
                XCTAssertGreaterThan(CGRectGetHeight(cell.bounds),64);
                UILabel *title=(UILabel *)WUNeoFindView(cell,@"WUNeoTitle");
                UILabel *detail=(UILabel *)WUNeoFindView(cell,@"WUNeoDetail");
                XCTAssertNotNil(title); XCTAssertNotNil(detail);
                XCTAssertEqualObjects(detail.text,cell.detailTextLabel.text);
                XCTAssertGreaterThan(CGRectGetWidth(detail.bounds),0);
                XCTAssertGreaterThanOrEqual(CGRectGetHeight(detail.bounds)+0.5,[detail sizeThatFits:CGSizeMake(CGRectGetWidth(detail.bounds),CGFLOAT_MAX)].height);
                CGRect cardRect=[card convertRect:card.bounds toView:cell];
                XCTAssertTrue(CGRectContainsRect(CGRectInset(cardRect,-0.5,-0.5),[title convertRect:title.bounds toView:cell]));
                XCTAssertTrue(CGRectContainsRect(CGRectInset(cardRect,-0.5,-0.5),[detail convertRect:detail.bounds toView:cell]));
            }
        }
        window.hidden=YES; window.rootViewController=nil;
    }
}
- (void)testThemePreviewMinimumGrowsForLongNames {
    WUNeoPreviewController *vc=[[WUNeoPreviewController alloc] initWithStyle:UITableViewStylePlain];
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,320,844)];
    window.rootViewController=vc; [window makeKeyAndVisible];
    [vc.view layoutIfNeeded]; [vc.tableView reloadData]; [vc.tableView layoutIfNeeded];
    UITableViewCell *cell=[vc.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    XCTAssertNotNil(cell); [cell layoutIfNeeded];
    UILabel *title=(UILabel *)WUNeoFindView(cell,@"WUNeoTitle");
    XCTAssertNotNil(title); XCTAssertGreaterThan(CGRectGetHeight(cell.bounds),148);
    XCTAssertGreaterThan(CGRectGetWidth(title.bounds),0);
    XCTAssertGreaterThanOrEqual(CGRectGetHeight(title.bounds)+0.5,[title sizeThatFits:CGSizeMake(CGRectGetWidth(title.bounds),CGFLOAT_MAX)].height);
    window.hidden=YES; window.rootViewController=nil;
}
- (void)testReusedCellReplacesVisibleText {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"stat"];
    cell.textLabel.text=@"旧统计"; WUNeoCell(cell,nil);
    XCTAssertEqualObjects(((UILabel *)WUNeoFindView(cell,@"WUNeoTitle")).text,@"旧统计");
    cell.textLabel.text=@"新统计"; WUNeoCell(cell,nil);
    XCTAssertEqualObjects(((UILabel *)WUNeoFindView(cell,@"WUNeoTitle")).text,@"新统计");
    NSUInteger count=0;
    for(UIView *view in cell.contentView.subviews) if([view.accessibilityIdentifier isEqualToString:@"WUNeoCustomContent"]) count++;
    XCTAssertEqual(count,1u);
}
- (void)testSystemSubtitleCardsFitAtAccessibleSizes {
    for(NSNumber *width in @[@320,@430]) for(NSString *category in @[UIContentSizeCategoryLarge,UIContentSizeCategoryAccessibilityExtraExtraExtraLarge]) {
        UIViewController *host=[UIViewController new];
        WUNeoTestController *vc=[[WUNeoTestController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [host addChildViewController:vc];
        [host setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:category] forChildViewController:vc];
        UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,width.doubleValue,2400)];
        window.rootViewController=host;
        vc.view.frame=host.view.bounds; vc.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [host.view addSubview:vc.view]; [vc didMoveToParentViewController:host]; [window makeKeyAndVisible];
        [host.view layoutIfNeeded]; [vc.tableView reloadData]; [vc.tableView layoutIfNeeded];
        UITableViewCell *cell=[vc.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
        XCTAssertNotNil(cell); [cell layoutIfNeeded]; [cell.backgroundView layoutIfNeeded];
        UILabel *title=(UILabel *)WUNeoFindView(cell,@"WUNeoTitle"), *detail=(UILabel *)WUNeoFindView(cell,@"WUNeoDetail");
        XCTAssertNotNil(title); XCTAssertNotNil(detail);
        if([category isEqualToString:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge]) XCTAssertGreaterThan(title.font.pointSize,20);
        UIView *card=cell.backgroundView.subviews.firstObject;
        CGRect cardRect=[card convertRect:card.bounds toView:cell];
        CGRect titleRect=[title convertRect:title.bounds toView:cell], detailRect=[detail convertRect:detail.bounds toView:cell];
        XCTAssertTrue(CGRectContainsRect(CGRectInset(cardRect,-0.5,-0.5),titleRect));
        XCTAssertTrue(CGRectContainsRect(CGRectInset(cardRect,-0.5,-0.5),detailRect));
        XCTAssertLessThanOrEqual(CGRectGetMaxY(titleRect),CGRectGetMinY(detailRect)+0.5);
        XCTAssertGreaterThan(CGRectGetWidth(detail.bounds),0);
        XCTAssertGreaterThanOrEqual(CGRectGetHeight(title.bounds)+0.5,[title sizeThatFits:CGSizeMake(CGRectGetWidth(title.bounds),CGFLOAT_MAX)].height);
        XCTAssertGreaterThanOrEqual(CGRectGetHeight(detail.bounds)+0.5,[detail sizeThatFits:CGSizeMake(CGRectGetWidth(detail.bounds),CGFLOAT_MAX)].height);
        window.hidden=YES; window.rootViewController=nil;
    }
}
- (void)testLongSubtitlesStayInsideAutomaticHeightCards {
    NSArray *categories=@[UIContentSizeCategoryLarge, UIContentSizeCategoryAccessibilityExtraExtraExtraLarge];
    for(NSNumber *width in @[@320,@390,@430]) for(NSString *category in categories) {
        UIViewController *host=[UIViewController new];
        WUNeoLongSubtitleController *vc=[[WUNeoLongSubtitleController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [host addChildViewController:vc];
        [host setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:category] forChildViewController:vc];
        UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,width.doubleValue,2400)];
        window.rootViewController=host;
        vc.view.frame=host.view.bounds; vc.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [host.view addSubview:vc.view]; [vc didMoveToParentViewController:host]; [window makeKeyAndVisible];
        [host.view layoutIfNeeded]; [vc.tableView reloadData]; [vc.tableView layoutIfNeeded];
        XCTAssertEqual(vc.tableView.rowHeight,UITableViewAutomaticDimension);
        CGRect previous=CGRectNull;
        for(NSInteger row=0;row<3;row++) {
            NSIndexPath *path=[NSIndexPath indexPathForRow:row inSection:0];
            [vc.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionTop animated:NO];
            [vc.tableView layoutIfNeeded];
            UITableViewCell *cell=[vc.tableView cellForRowAtIndexPath:path];
            XCTAssertNotNil(cell); [cell layoutIfNeeded]; [cell.backgroundView layoutIfNeeded];
            UILabel *title=[cell viewWithTag:1001], *detail=[cell viewWithTag:1002];
            UIImageView *icon=[cell viewWithTag:1003]; UIView *card=cell.backgroundView.subviews.firstObject;
            XCTAssertNotNil(title); XCTAssertNotNil(detail); XCTAssertNotNil(card);
            if([category isEqualToString:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge]) XCTAssertGreaterThan(title.font.pointSize,20);
            CGRect cardRect=[card convertRect:card.bounds toView:cell];
            CGRect titleRect=[title convertRect:title.bounds toView:cell];
            CGRect detailRect=[detail convertRect:detail.bounds toView:cell];
            CGRect iconRect=[icon convertRect:icon.bounds toView:cell];
            CGRect toggleRect=[cell.accessoryView convertRect:cell.accessoryView.bounds toView:cell];
            XCTAssertTrue(CGRectContainsRect(CGRectInset(cardRect,-0.5,-0.5),titleRect));
            XCTAssertTrue(CGRectContainsRect(CGRectInset(cardRect,-0.5,-0.5),detailRect));
            XCTAssertTrue(CGRectContainsRect(CGRectInset(cardRect,-0.5,-0.5),iconRect));
            XCTAssertTrue(CGRectContainsRect(CGRectInset(cardRect,-0.5,-0.5),toggleRect));
            XCTAssertLessThanOrEqual(CGRectGetMaxY(titleRect),CGRectGetMinY(detailRect)+0.5);
            XCTAssertLessThanOrEqual(CGRectGetMaxX(detailRect),CGRectGetMinX(toggleRect)+0.5);
            XCTAssertGreaterThanOrEqual(CGRectGetHeight(title.bounds)+0.5,[title sizeThatFits:CGSizeMake(CGRectGetWidth(title.bounds),CGFLOAT_MAX)].height);
            XCTAssertGreaterThanOrEqual(CGRectGetHeight(detail.bounds)+0.5,[detail sizeThatFits:CGSizeMake(CGRectGetWidth(detail.bounds),CGFLOAT_MAX)].height);
            CGRect rowRect=[vc.tableView rectForRowAtIndexPath:path];
            if(!CGRectIsNull(previous)) XCTAssertLessThanOrEqual(CGRectGetMaxY(previous),CGRectGetMinY(rowRect)+0.5);
            previous=rowRect;
            CGPoint center=[cell.accessoryView convertPoint:CGPointMake(CGRectGetMidX(cell.accessoryView.bounds),CGRectGetMidY(cell.accessoryView.bounds)) toView:cell];
            UIView *hit=[cell hitTest:center withEvent:nil];
            XCTAssertTrue(hit==cell.accessoryView || [hit isDescendantOfView:cell.accessoryView]);
        }
        window.hidden=YES; window.rootViewController=nil;
    }
}
@end
