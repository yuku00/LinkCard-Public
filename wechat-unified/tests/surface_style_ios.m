// iOS XCTest target only. This is UIKit simulation, not target WeChat / real-device validation.
#import <XCTest/XCTest.h>
#import "WU.h"
static NSDictionary *config;
NSString *const WUChanged=@"test.ui.changed";
id WUValue(NSString *key) { return config[key]; }
BOOL WUEnabled(NSString *key) { return [config[@"enabled"] boolValue]&&[config[key] boolValue]; }
UIColor *WUThemeColor(NSString *token,UITraitCollection *traits) { return WUEnabled(@"themes")&&[token isEqual:@"bg-1"]?UIColor.cyanColor:nil; }
@interface WUSurfaceStyleTests : XCTestCase
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIView *surface;
@property(nonatomic,strong) UILabel *label;
@end
@implementation WUSurfaceStyleTests
- (void)setUp { [super setUp]; self.window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,390,844)]; self.surface=[[UIView alloc] initWithFrame:CGRectMake(0,0,240,60)]; self.label=[[UILabel alloc] initWithFrame:CGRectMake(8,8,160,30)]; self.label.text=@"Synthetic preview"; self.label.font=[UIFont systemFontOfSize:15]; self.label.textColor=UIColor.blackColor; self.surface.backgroundColor=UIColor.yellowColor; self.surface.layer.cornerRadius=2; [self.surface addSubview:self.label]; [self.window addSubview:self.surface]; }
- (void)tearDown { WURestoreConfiguredSurface(self.surface); self.window=nil; self.surface=nil; self.label=nil; config=nil; [super tearDown]; }
- (void)testRealPropertyApplicationAndDisable {
    config=@{@"enabled":@YES,@"searchSurface":@YES,@"surfaceStyles":@{@"searchSurface":@{@"radius":@14,@"borderWidth":@3,@"fontSize":@22,@"background":@"#123456",@"text":@"#ffffff"}}};
    WUApplyConfiguredSurface(self.surface,@"searchSurface",10,YES);
    XCTAssertEqual(self.surface.layer.cornerRadius,14); XCTAssertEqual(self.surface.layer.borderWidth,3); XCTAssertEqual(self.label.font.pointSize,22);
    XCTAssertEqualObjects(self.label.textColor,[UIColor colorWithRed:1 green:1 blue:1 alpha:1]);
    config=@{@"enabled":@NO}; WUApplyConfiguredSurface(self.surface,@"searchSurface",10,YES);
    XCTAssertEqual(self.surface.layer.cornerRadius,2); XCTAssertEqual(self.surface.layer.borderWidth,0); XCTAssertEqual(self.label.font.pointSize,15); XCTAssertEqualObjects(self.surface.backgroundColor,UIColor.yellowColor); XCTAssertEqualObjects(self.label.textColor,UIColor.blackColor);
}
- (void)testHostMutationIsNotOverwritten {
    config=@{@"enabled":@YES,@"searchSurface":@YES,@"surfaceStyles":@{@"searchSurface":@{@"radius":@14}}}; WUApplyConfiguredSurface(self.surface,@"searchSurface",10,YES);
    self.surface.layer.cornerRadius=27; self.label.font=[UIFont systemFontOfSize:29]; WURestoreConfiguredSurface(self.surface);
    XCTAssertEqual(self.surface.layer.cornerRadius,27); XCTAssertEqual(self.label.font.pointSize,29);
}
- (void)testThemeColorsReallyApplyAndExplicitOverrideWins {
    config=@{@"enabled":@YES,@"themes":@YES,@"searchSurface":@YES}; WUApplyConfiguredSurface(self.surface,@"searchSurface",10,YES); XCTAssertEqualObjects(self.surface.backgroundColor,UIColor.cyanColor);
    config=@{@"enabled":@YES,@"themes":@YES,@"searchSurface":@YES,@"surfaceStyles":@{@"searchSurface":@{@"background":@"#ff0000"}}}; WUApplyConfiguredSurface(self.surface,@"searchSurface",10,YES); XCTAssertEqualObjects(self.surface.backgroundColor,UIColor.redColor);
}
- (void)testRepeatedLayoutsDoNotOverwriteOriginalBaseline {
    config=@{@"enabled":@YES,@"searchSurface":@YES,@"surfaceStyles":@{@"searchSurface":@{@"fontSize":@20}}};
    for(NSUInteger n=0;n<50;n++) WUApplyConfiguredSurface(self.surface,@"searchSurface",10,YES);
    WURestoreConfiguredSurface(self.surface); XCTAssertEqual(self.label.font.pointSize,15); XCTAssertEqual(self.surface.layer.cornerRadius,2);
}
@end
