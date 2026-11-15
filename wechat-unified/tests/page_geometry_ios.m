// Real production helper, real UIKit, synthetic classes only; not WeChat acceptance.
#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>
@interface MMTableView : UITableView @end
@implementation MMTableView @end
@interface MMInputToolView : UIView @end
@implementation MMInputToolView @end
@interface InputToolContainerView : UIView @end
@implementation InputToolContainerView @end
@interface InputToolViewBar : UIView
@property(nonatomic) BOOL throwOnFrame;
@end
@implementation InputToolViewBar
- (CGRect)frame { if(self.throwOnFrame) @throw [NSException exceptionWithName:@"synthetic" reason:nil userInfo:nil]; return [super frame]; }
@end
@interface EmoticonMessageCellView : UIView @end
@implementation EmoticonMessageCellView
- (CGRect)frame { return CGRectMake(INFINITY,0,1,1); }
@end
@interface AppEmoticonMessageCellView : NSObject @end
@implementation AppEmoticonMessageCellView @end
@interface UnknownToolSubclass : MMInputToolView @end
@implementation UnknownToolSubclass @end
@interface NotWhitelistedView : UIView @end
@implementation NotWhitelistedView
- (CGRect)frame { @throw [NSException exceptionWithName:@"must not call" reason:nil userInfo:nil]; }
@end
#import "../Sources/WUPageGeometry.inc"
@interface WUPageGeometryTests : XCTestCase @end
@implementation WUPageGeometryTests
- (void)testProductionHelper {
    NSMutableString *out=[NSMutableString string];
    MMInputToolView *tool=[[MMInputToolView alloc] initWithFrame:CGRectMake(1,2,30,40)];
    WUPageAppendGeometry(out,tool);
    XCTAssertTrue([out containsString:@"frame=(1.00,2.00,30.00,40.00)"]);
    XCTAssertTrue([out containsString:@"bounds=("]);
    [out setString:@""]; WUPageAppendGeometry(out,[InputToolContainerView new]); XCTAssertTrue([out containsString:@"bounds=("]);
    InputToolViewBar *throwing=[InputToolViewBar new]; throwing.throwOnFrame=YES;
    [out setString:@""]; WUPageAppendGeometry(out,throwing); XCTAssertTrue([out containsString:@"getter 异常"]);
    [out setString:@""]; WUPageAppendGeometry(out,[EmoticonMessageCellView new]); XCTAssertTrue([out containsString:@"非有限数值"]);
    [out setString:@""]; WUPageAppendGeometry(out,[AppEmoticonMessageCellView new]); XCTAssertTrue([out containsString:@"不是 UIView"]);
    [out setString:@""]; WUPageAppendGeometry(out,[NotWhitelistedView new]); XCTAssertEqual(out.length,0u);
    [out setString:@""]; WUPageAppendGeometry(out,[UnknownToolSubclass new]); XCTAssertEqual(out.length,0u);
    MMTableView *table=[[MMTableView alloc] initWithFrame:CGRectMake(1,2,30,40)];
    table.contentSize=CGSizeMake(500,500); table.contentOffset=CGPointMake(77,88); table.contentInset=UIEdgeInsetsMake(1,2,3,4);
    [out setString:@""]; WUPageAppendGeometry(out,table);
    XCTAssertTrue([out containsString:@"bounds.size="]); XCTAssertTrue([out containsString:@"contentInset="]);
    XCTAssertFalse([out containsString:@"bounds=("]); XCTAssertFalse([out containsString:@"77.00"]); XCTAssertFalse([out containsString:@"88.00"]);
    [out setString:@""]; WUPageAppendGeometry(out,[[UIView alloc] initWithFrame:CGRectMake(10000001,0,1,1)]); XCTAssertTrue([out containsString:@"截断"]);
}
@end
