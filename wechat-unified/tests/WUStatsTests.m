#import <XCTest/XCTest.h>
#import "WUStats.h"
#import <objc/runtime.h>

// Standalone XCTest target only: never link this mock into WeChat or the dylib.
@interface CMessageMgr : NSObject
@property(nonatomic,strong) NSArray *pages;
@property(nonatomic) NSUInteger calls;
@end
@implementation CMessageMgr
- (NSArray *)GetMsgByCreateTime:(NSString *)session FromID:(uint32_t)mid FromCreateTime:(uint32_t)time Limit:(uint32_t)limit LeftCount:(uint32_t *)left {
    NSAssert(limit==200,@"page size"); NSArray *p=self.pages[MIN(self.calls,self.pages.count-1)]; self.calls++; *left=self.calls<self.pages.count ? 1 : 0; return p;
}
@end
static NSDictionary *R(NSString *sid,NSString *sender,int64_t time,NSString *type) {
    return @{@"sid":sid,@"sender":sender,@"time":@(time),@"type":type,@"text":@"hello world hello",@"source":@"normal"};
}
@interface WUStatsTests : XCTestCase
@end
@implementation WUStatsTests
- (WUStatsAccumulator *)acc:(BOOL)group {return [[WUStatsAccumulator alloc] initWithTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0] group:group];}
- (void)testUnknownIDsAreNeverDeduplicated {
    WUStatsAccumulator *a=[self acc:NO]; [a addRecords:@[R(@"0",@"a",1,@"text"),R(@"",@"a",1,@"text")]];
    XCTAssertEqualObjects([a result][@"total"],@2); XCTAssertEqualObjects([a result][@"unknownID"],@2);
}
- (void)testCrossPagePaymentUpgrade {
    WUStatsAccumulator *a=[self acc:NO]; [a addRecords:@[R(@"42",@"a",1,@"other")]]; [a addRecords:@[R(@"42",@"a",1,@"redpacket")]];
    NSDictionary *r=a.result; XCTAssertEqualObjects(r[@"total"],@1); XCTAssertEqualObjects(r[@"types"],(@{@"redpacket":@1})); XCTAssertEqualObjects(r[@"duplicates"],@1);
}
- (void)testLocalIDsRequireSource {
    WUStatsAccumulator *a=[self acc:NO]; NSMutableDictionary *r=[R(@"",@"a",1,@"text") mutableCopy]; r[@"lid"]=@"8";
    NSMutableDictionary *other=[r mutableCopy]; other[@"source"]=@"app";
    [a addRecords:@[r,other,r]]; XCTAssertEqualObjects(a.result[@"total"],@2);
}
- (void)testOpposingServerIDsDoNotMergeViaLocalID {
    WUStatsAccumulator *a=[self acc:NO]; NSMutableDictionary *r=[R(@"1",@"a",1,@"text") mutableCopy]; r[@"lid"]=@"8";
    NSMutableDictionary *other=[r mutableCopy]; other[@"sid"]=@"2";
    [a addRecords:@[r,other]]; XCTAssertEqualObjects(a.result[@"total"],@2);
}
- (void)testGroupSignedDifferenceAndReverseInput {
    NSArray *rows=@[R(@"1",@"a",100,@"text"),R(@"2",@"b",200,@"text"),R(@"3",@"a",21800,@"text"),R(@"4",@"b",108200,@"text")];
    for(NSNumber *group in @[@YES,@NO]) {
        WUStatsAccumulator *a=[self acc:group.boolValue],*b=[self acc:group.boolValue]; [a addRecords:rows]; [b addRecords:rows.reverseObjectEnumerator.allObjects];
        XCTAssertEqualObjects(a.result,b.result); XCTAssertEqualObjects(a.result[@"replyCount"],@1); XCTAssertEqualObjects(a.result[@"replyMeanSeconds"],@100);
        XCTAssertEqual([a.result[@"openers"] count],2u); XCTAssertEqualObjects(a.result[@"icebreakers"],(@[@{@"id":@"b",@"count":@1}]));
    }
}
- (void)testEqualTimeClusterBreaksBothEdges {
    WUStatsAccumulator *a=[self acc:YES]; [a addRecords:@[R(@"1",@"a",10,@"text"),R(@"2",@"b",20,@"text"),R(@"3",@"c",20,@"text"),R(@"4",@"d",30,@"text")]];
    XCTAssertEqualObjects(a.result[@"replyCount"],@0);
}
- (void)testZeroTimeBreaksChain {
    WUStatsAccumulator *a=[self acc:YES]; [a addRecords:@[R(@"1",@"a",10,@"text"),R(@"2",@"b",0,@"text"),R(@"3",@"c",30,@"text")]];
    XCTAssertEqualObjects(a.result[@"replyCount"],@0); XCTAssertEqualObjects(a.result[@"unknownTime"],@1);
}
- (void)testInvalidPageIsAtomic {
    WUStatsAccumulator *a=[self acc:NO]; XCTAssertFalse(([a addRecords:@[R(@"1",@"a",10,@"text"),@{@"time":@(-1)}]])); XCTAssertEqualObjects(a.result[@"total"],@0);
}
- (void)testDSTCalendarDays {
    WUStatsAccumulator *a=[[WUStatsAccumulator alloc] initWithTimeZone:[NSTimeZone timeZoneWithName:@"America/New_York"] group:NO];
    [a addRecords:@[R(@"1",@"a",1710050400,@"text"),R(@"2",@"a",1710133200,@"text")]];
    XCTAssertEqualObjects(a.result[@"longestStreak"],@2); XCTAssertEqual([a.result[@"days"] count],2u);
}
- (void)testDeterministicRankAndWords {
    WUStatsAccumulator *a=[self acc:NO]; [a addRecords:@[R(@"1",@"b",1,@"text"),R(@"2",@"a",2,@"text")]];
    XCTAssertEqualObjects(a.result[@"speakers"][0][@"id"],@"a"); XCTAssertEqualObjects(a.result[@"words"][0],(@{@"id":@"hello",@"count":@4}));
}
- (WUStatsBinding *)binding:(CMessageMgr *)mgr {
    WUStatsBinding *b=[WUStatsBinding new]; b.account=@"synthetic-account"; b.session=@"synthetic-session"; b.messageManager=mgr; b.initialCursor=@{@"id":@1000,@"time":@1000}; b.stillCurrent=^{return YES;};
    b.verifiedEncoding=[NSString stringWithUTF8String:method_getTypeEncoding(class_getInstanceMethod(CMessageMgr.class,@selector(GetMsgByCreateTime:FromID:FromCreateTime:Limit:LeftCount:)))];
    b.decodePage=^NSDictionary *(NSArray *page,uint32_t left,NSDictionary *cursor) {return @{@"records":page,@"done":@(left==0),@"next":@{@"id":@([cursor[@"id"] unsignedIntValue]-1),@"time":@([cursor[@"time"] unsignedIntValue]-1)}};}; return b;
}
- (void)testPaginationAcrossDuplicatePages {
    CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[R(@"1",@"a",1,@"text")],@[R(@"1",@"a",1,@"text"),R(@"2",@"b",2,@"text")]];
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:[self binding:mgr]]; XCTestExpectation *done=[self expectationWithDescription:@"finish"];
    [job start:^(NSDictionary *r,NSString *s) {if(r){ XCTAssertEqualObjects(r[@"total"],@2); XCTAssertEqualObjects(r[@"complete"],@YES); [done fulfill]; }}];
    [self waitForExpectations:@[done] timeout:2];
}
- (void)testCancellationStopsNextPage {
    CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[R(@"1",@"a",1,@"text")],@[R(@"2",@"b",2,@"text")]];
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:[self binding:mgr]]; __block NSUInteger callbacks=0;
    [job start:^(NSDictionary *r,NSString *s) {callbacks++; [job cancel];}];
    XCTestExpectation *done=[self expectationWithDescription:@"queue drained"]; dispatch_async(dispatch_get_main_queue(),^{XCTAssertEqual(mgr.calls,1u); XCTAssertEqual(callbacks,1u); [done fulfill];}); [self waitForExpectations:@[done] timeout:2];
}
- (void)testAccountSwitchDropsResult {
    CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[R(@"1",@"a",1,@"text")]]; WUStatsBinding *b=[self binding:mgr]; __block BOOL current=YES; b.stillCurrent=^{return current;};
    b.decodePage=^NSDictionary *(NSArray *p,uint32_t left,NSDictionary *c){current=NO; return @{@"records":p,@"done":@YES};};
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:b]; __block BOOL called=NO;
    [job start:^(NSDictionary *r,NSString *s){called=YES; XCTAssertNil(r); XCTAssertTrue([s containsString:@"变化"]);}]; XCTAssertTrue(called);
}
- (void)testSignatureMismatchDoesNotInvokeHost {
    CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[]]; WUStatsBinding *b=[self binding:mgr]; b.verifiedEncoding=@"invalid";
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:b]; XCTestExpectation *done=[self expectationWithDescription:@"mismatch"];
    [job start:^(NSDictionary *r,NSString *s){XCTAssertTrue([s containsString:@"不匹配"]); XCTAssertEqualObjects(r[@"complete"],@NO); [done fulfill];}]; XCTAssertEqual(mgr.calls,0u);
    [self waitForExpectations:@[done] timeout:5];
}
- (void)testSameTimeCursorAdvancesByID {
    CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[R(@"1",@"a",100,@"text")],@[R(@"2",@"b",100,@"text")]];
    WUStatsBinding *b=[self binding:mgr]; b.decodePage=^NSDictionary *(NSArray *p,uint32_t left,NSDictionary *c){return @{@"records":p,@"done":@(left==0),@"next":@{@"time":c[@"time"],@"id":@([c[@"id"] unsignedIntValue]-1)}};};
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:b]; XCTestExpectation *done=[self expectationWithDescription:@"same-time pages"];
    [job start:^(NSDictionary *r,NSString *s){if(r){XCTAssertEqualObjects(r[@"complete"],@YES); XCTAssertEqualObjects(r[@"total"],@2); XCTAssertEqualObjects(r[@"replyCount"],@0); [done fulfill];}}];
    [self waitForExpectations:@[done] timeout:2];
}
- (void)testStalledCursorTruncates {
    CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[R(@"1",@"a",1,@"text")],@[]]; WUStatsBinding *b=[self binding:mgr];
    b.decodePage=^NSDictionary *(NSArray *p,uint32_t left,NSDictionary *c){return @{@"records":p,@"done":@NO,@"next":c};};
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:b]; XCTestExpectation *done=[self expectationWithDescription:@"stalled"];
    [job start:^(NSDictionary *r,NSString *s){XCTAssertEqualObjects(r[@"complete"],@NO); XCTAssertTrue([s containsString:@"游标"]); [done fulfill];}]; XCTAssertEqual(mgr.calls,1u);
    [self waitForExpectations:@[done] timeout:5];
}
@end
