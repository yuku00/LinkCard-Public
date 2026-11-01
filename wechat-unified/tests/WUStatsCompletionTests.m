#import <XCTest/XCTest.h>
#import "WUStats.h"
#import <objc/runtime.h>
// Uses the synthetic host supplied by WUStatsTests.m; no real process/data.
@interface CMessageMgr : NSObject
@property(nonatomic,strong) NSArray *pages;
@property(nonatomic) NSUInteger calls;
@end
static NSDictionary *Message(NSString *sid, NSString *sender, int64_t time, NSString *type) {
    return @{@"sid":sid,@"lid":sid,@"source":@"normal",@"sender":sender,@"time":@(time),@"type":type,@"text":@"synthetic"};
}
static WUStatsBinding *Binding(NSString *session, NSArray *records) {
    CMessageMgr *manager=[CMessageMgr new]; manager.pages=@[records,@[]];
    WUStatsBinding *b=[WUStatsBinding new]; b.account=@"me"; b.session=session; b.group=[session hasSuffix:@"@chatroom"]; b.messageManager=manager;
    Method m=class_getInstanceMethod(CMessageMgr.class,NSSelectorFromString(@"GetMsgByCreateTime:FromID:FromCreateTime:Limit:LeftCount:"));
    b.verifiedEncoding=[NSString stringWithUTF8String:method_getTypeEncoding(m)]; b.initialCursor=@{@"id":@0,@"time":@0}; b.stillCurrent=^BOOL{ return YES; };
    b.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];
    b.decodePage=^NSDictionary *(NSArray *page,uint32_t left,NSDictionary *cursor) { return @{@"records":page,@"next":@{@"id":@1,@"time":@10},@"done":@(page.count==0 && left==0)}; };
    return b;
}
@interface WUStatsCompletionTests : XCTestCase
@end
@implementation WUStatsCompletionTests
- (void)testSidesDenominatorUnknownAndChronology {
    NSArray *rows=@[Message(@"1",@"me",100,@"text"),Message(@"2",@"peer",200,@"voice"),Message(@"3",@"stranger",0,@"image"),Message(@"4",@"",50,@"other")];
    NSDictionary *r=WUStatsDetails(rows,@"me",@"peer",NO,[NSTimeZone timeZoneForSecondsFromGMT:0]);
    XCTAssertEqualObjects(r[@"denominator"],@4); XCTAssertEqualObjects(r[@"dated"],@3);
    XCTAssertEqualObjects(r[@"summary"][@"self"][@"count"],@1); XCTAssertEqualObjects(r[@"summary"][@"peer"][@"count"],@1);
    XCTAssertEqualObjects(r[@"summary"][@"unknown"][@"count"],@2); XCTAssertEqualObjects(r[@"summary"][@"self"][@"shareOfTotal"],@0.25);
    XCTAssertEqualObjects(r[@"first"],@50); XCTAssertEqualObjects(r[@"last"],@200);
    XCTAssertEqualObjects(r,WUStatsDetails(rows.reverseObjectEnumerator.allObjects,@"me",@"peer",NO,[NSTimeZone timeZoneForSecondsFromGMT:0]));
    NSDictionary *empty=WUStatsDetails(@[],@"me",@"peer",NO,[NSTimeZone timeZoneForSecondsFromGMT:0]);
    XCTAssertEqualObjects(empty[@"first"],NSNull.null); XCTAssertEqualObjects(empty[@"summary"][@"self"][@"shareOfTotal"],NSNull.null);
}
- (void)testGroupAuthoredAndUnknownRoomID {
    NSDictionary *r=WUStatsDetails(@[Message(@"1",@"me",1,@"system"),Message(@"2",@"me",2,@"pat"),Message(@"3",@"me",3,@"text"),Message(@"4",@"g@chatroom",4,@"text")],@"me",@"g@chatroom",YES,[NSTimeZone timeZoneForSecondsFromGMT:0]);
    XCTAssertEqualObjects(r[@"summary"][@"self"][@"count"],@3); XCTAssertEqualObjects(r[@"summary"][@"self"][@"authoredCount"],@1);
    XCTAssertEqualObjects(r[@"summary"][@"unknown"][@"count"],@1);
}
- (void)testSectionValidationAndGroupRanking {
    XCTAssertEqualObjects(WUStatsSectionOrder(@[]),@[]); XCTAssertEqualObjects(WUStatsSectionOrder(@[@"journey",@"selfPeer"]),(@[@"journey",@"selfPeer"]));
    XCTAssertEqualObjects(WUStatsSectionOrder(@[@"journey",@"journey"]),WUStatsOptionalSections());
    XCTAssertEqualObjects(WUStatsSectionOrder(@[@1]),WUStatsOptionalSections()); XCTAssertEqualObjects(WUStatsSectionOrder(@[@"unknown"]),WUStatsOptionalSections());
    NSArray *r=WUStatsMyGroupRanking(@[@{@"id":@"b",@"kind":@"chatroom",@"selfCount":@2,@"count":@3},@{@"id":@"a",@"kind":@"chatroom",@"selfCount":@2,@"count":@99},@{@"id":@"z",@"kind":@"private",@"selfCount":@100}]);
    XCTAssertEqual(r.count,2u); XCTAssertEqualObjects(r[0][@"id"],@"a"); XCTAssertEqualObjects(r[0][@"count"],@2);
}
- (void)testProductionScanDetailsAfterDedupAndDateFilter {
    NSArray *records=@[Message(@"3",@"me",11,@"voice"),Message(@"3",@"me",11,@"voice"),Message(@"2",@"peer",12,@"text"),Message(@"4",@"stranger",13,@"text"),Message(@"5",@"",0,@"text"),Message(@"6",@"me",21,@"text")];
    WUStatsBinding *b=Binding(@"peer",records); b.dateRange=@{@"start":@10,@"end":@20};
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:b]; XCTestExpectation *done=[self expectationWithDescription:@"job"];
    [job start:^(NSDictionary *r,NSString *status){ if(!r) return;
        XCTAssertEqualObjects(r[@"total"],@3); XCTAssertEqualObjects(r[@"details"][@"denominator"],r[@"total"]);
        XCTAssertEqualObjects(r[@"details"][@"summary"][@"self"][@"count"],@1); XCTAssertEqualObjects(r[@"details"][@"summary"][@"peer"][@"count"],@1);
        XCTAssertEqualObjects(r[@"details"][@"first"],@11); XCTAssertEqualObjects(r[@"details"][@"last"],@13);
        XCTAssertTrue([r[@"complete"] boolValue]); [done fulfill];
    }]; [self waitForExpectationsWithTimeout:5 handler:nil];
}
- (void)testNewDetailsDroppedOnAccountChange {
    __block BOOL current=YES; WUStatsBinding *b=Binding(@"peer",@[Message(@"1",@"me",11,@"text")]); b.stillCurrent=^BOOL{ return current; };
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:b]; XCTestExpectation *done=[self expectationWithDescription:@"cancelled"];
    [job start:^(NSDictionary *r,NSString *status){ if(job.cancelled) { XCTAssertNil(r); [done fulfill]; } }];
    current=NO; [self waitForExpectationsWithTimeout:5 handler:nil];
}
- (void)testProductionOverviewRanksSelfInsteadOfTotal {
    WUStatsBinding *base=Binding(@"peer",@[]); base.sessions=@[@{@"username":@"a@chatroom",@"kind":@"chatroom"},@{@"username":@"b@chatroom",@"kind":@"chatroom"}];
    base.bindingForSession=^WUStatsBinding *(NSString *s){ return Binding(s,[s hasPrefix:@"a"]?@[Message(@"1",@"me",11,@"text"),Message(@"2",@"x",12,@"text"),Message(@"3",@"x",13,@"text")]:@[Message(@"1",@"me",11,@"text"),Message(@"2",@"me",12,@"voice")]); };
    WUStatsOverviewJob *job=[[WUStatsOverviewJob alloc] initWithBinding:base]; XCTestExpectation *done=[self expectationWithDescription:@"overview"];
    [job start:^(NSDictionary *r,NSString *status){ if(!r) return; XCTAssertEqualObjects(r[@"rank"][0][@"id"],@"a@chatroom"); XCTAssertEqualObjects(r[@"myGroups"][0][@"id"],@"b@chatroom"); XCTAssertEqualObjects(r[@"myGroups"][0][@"count"],@2); [done fulfill]; }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}
@end
