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
- (void)testDuplicateFillsOnlyMissingFields {
    WUStatsAccumulator *a=[self acc:NO];
    NSDictionary *empty=@{@"sid":@"42",@"source":@"normal",@"sender":@"",@"time":@0,@"type":@"text",@"text":@""};
    NSDictionary *full=@{@"sid":@"42",@"source":@"app",@"sender":@"alice",@"time":@100,@"type":@"text",@"text":@"hello world"};
    NSDictionary *conflict=@{@"sid":@"42",@"source":@"app",@"sender":@"bob",@"time":@200,@"type":@"text",@"text":@"other words"};
    XCTAssertTrue(([a addRecords:@[empty,full,conflict]]));
    NSDictionary *r=a.result;
    XCTAssertEqualObjects(r[@"total"],@1); XCTAssertEqualObjects(r[@"duplicates"],@2);
    XCTAssertEqualObjects(r[@"unknownTime"],@0); XCTAssertEqualObjects(r[@"unknownSender"],@0);
    XCTAssertEqualObjects(r[@"speakers"][0][@"id"],@"alice");
    XCTAssertEqualObjects(r[@"words"][0][@"id"],@"hello");
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
- (void)testZeroCursorStartsAtFirstRealPage {
    CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[R(@"1",@"a",100,@"text")],@[]];
    WUStatsBinding *b=[self binding:mgr]; b.initialCursor=@{@"id":@0,@"time":@0};
    b.decodePage=^NSDictionary *(NSArray *p,uint32_t left,NSDictionary *c){return @{@"records":p,@"done":@(p.count==0 && left==0),@"next":@{@"id":@20,@"time":@100}};};
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:b]; XCTestExpectation *done=[self expectationWithDescription:@"zero sentinel"];
    [job start:^(NSDictionary *r,NSString *s){if(r){XCTAssertEqualObjects(r[@"total"],@1); XCTAssertEqualObjects(r[@"complete"],@YES); XCTAssertEqual(mgr.calls,2u); [done fulfill];}}];
    [self waitForExpectations:@[done] timeout:5];
}
- (void)testCancellationDuringBackgroundSummary {
    CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[R(@"1",@"a",100,@"text")]];
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:[self binding:mgr]]; __block NSUInteger callbacks=0;
    [job start:^(NSDictionary *r,NSString *s){callbacks++;}]; [job cancel];
    XCTestExpectation *done=[self expectationWithDescription:@"cancel summary"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{XCTAssertEqual(callbacks,0u); [done fulfill];});
    [self waitForExpectations:@[done] timeout:5];
}
- (void)testCivilDateRangeDSTAndInvalidDates {
    NSTimeZone *zone=[NSTimeZone timeZoneWithName:@"America/New_York"];
    NSDictionary *spring=WUStatsDateRange(@"2024-03-10",@"2024-03-10",zone);
    NSDictionary *fall=WUStatsDateRange(@"2024-11-03",@"2024-11-03",zone);
    XCTAssertEqual([spring[@"end"] doubleValue]-[spring[@"start"] doubleValue],23*3600);
    XCTAssertEqual([fall[@"end"] doubleValue]-[fall[@"start"] doubleValue],25*3600);
    XCTAssertTrue(WUStatsTimeInRange(spring[@"start"],spring)); XCTAssertFalse(WUStatsTimeInRange(spring[@"end"],spring));
    XCTAssertFalse(WUStatsTimeInRange(@0,spring));
    XCTAssertNil(WUStatsDateRange(@"2024-02-30",@"2024-03-01",zone));
    XCTAssertNil(WUStatsDateRange(@"2024-03-11",@"2024-03-10",zone));
}
- (void)testDateFilteredProductionPagesKeepSameSecondAndFreezeRange {
    CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[R(@"1",@"a",100,@"text"),R(@"2",@"b",200,@"text")],@[R(@"3",@"c",100,@"text"),R(@"4",@"a",99,@"text")]];
    WUStatsBinding *binding=[self binding:mgr]; binding.dateRange=@{@"start":@100,@"end":@200};
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:binding]; binding.dateRange=@{@"start":@300,@"end":@400};
    XCTestExpectation *done=[self expectationWithDescription:@"date pages"];
    [job start:^(NSDictionary *r,NSString *s){ if(r) { XCTAssertEqualObjects(r[@"total"],@2); XCTAssertEqualObjects(r[@"replyCount"],@0); XCTAssertEqual(mgr.calls,2u); [done fulfill]; }}];
    [self waitForExpectations:@[done] timeout:5];
}
- (void)testDateRangeDoesNotInferMonotonicTimeFromLocalID {
    CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[R(@"1",@"a",50,@"text")],@[R(@"2",@"b",100,@"text")]];
    WUStatsBinding *b=[self binding:mgr]; b.dateRange=@{@"start":@100,@"end":@101};
    b.decodePage=^NSDictionary *(NSArray *p,uint32_t left,NSDictionary *c){ return @{@"records":p,@"done":@(left==0),@"next":@{@"id":@([c[@"id"] unsignedIntValue]-1),@"time":@50}}; };
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:b]; XCTestExpectation *done=[self expectationWithDescription:@"nonmonotonic"];
    [job start:^(NSDictionary *r,NSString *s){if(r){XCTAssertEqualObjects(r[@"total"],@1); XCTAssertEqual(mgr.calls,2u); [done fulfill];}}];
    [self waitForExpectations:@[done] timeout:5];
}
- (void)testVisitsDebounceForegroundAccountIsolationAndWriteFailure {
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    WUStatsVisitStore *store=[[WUStatsVisitStore alloc] initWithDirectory:root account:@"synthetic-a"];
    BOOL (^yes)(void)=^BOOL{return YES;};
    XCTAssertFalse([store recordSession:@"room" kind:@"chatroom" time:100 active:NO enabled:YES current:yes]);
    XCTAssertFalse([store recordSession:@"room" kind:@"chatroom" time:100 active:YES enabled:NO current:yes]);
    XCTAssertFalse([store recordSession:@"room" kind:@"chatroom" time:100 active:YES enabled:YES current:^BOOL{return NO;}]);
    XCTAssertTrue([store recordSession:@"room" kind:@"chatroom" time:100 active:YES enabled:YES current:yes]);
    XCTAssertFalse([store recordSession:@"room" kind:@"chatroom" time:111.99 active:YES enabled:YES current:yes]);
    XCTAssertTrue([store recordSession:@"room" kind:@"chatroom" time:112 active:YES enabled:YES current:yes]);
    XCTAssertTrue([store recordSession:@"friend" kind:@"private" time:113 active:YES enabled:YES current:yes]);
    XCTAssertTrue([store recordSession:@"room" kind:@"chatroom" time:114 active:YES enabled:YES current:yes]);
    XCTAssertFalse([store recordSession:@"friend" kind:@"private" time:110 active:YES enabled:YES current:yes]);
    WUStatsVisitStore *other=[[WUStatsVisitStore alloc] initWithDirectory:root account:@"synthetic-b"];
    XCTAssertEqual([other.snapshot[@"events"] count],0u);
    store.writeData=^BOOL(NSData *data,NSURL *url){return NO;};
    XCTAssertFalse([store recordSession:@"friend" kind:@"private" time:130 active:YES enabled:YES current:yes]);
    XCTAssertEqual([store.snapshot[@"events"] count],4u); XCTAssertFalse([store clearIfCurrent:yes]);
    store.writeData=nil;
    XCTAssertFalse([store clearIfCurrent:^BOOL{return NO;}]); XCTAssertEqual([store.snapshot[@"events"] count],4u);
    XCTAssertTrue([store clearIfCurrent:yes]); XCTAssertEqual([store.snapshot[@"events"] count],0u);
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
}
- (void)testOverviewReusesProductionJobsAndRanksPerSession {
    WUStatsBinding *base=[WUStatsBinding new]; base.account=@"synthetic"; base.stillCurrent=^BOOL{return YES;}; base.dateRange=@{@"start":@100,@"end":@200};
    base.sessions=@[@{@"username":@"b",@"kind":@"chatroom"},@{@"username":@"a",@"kind":@"private"},@{@"username":@"a",@"kind":@"private"},@{@"username":@"unclassified",@"kind":@"unknown"}];
    base.bindingForSession=^WUStatsBinding *(NSString *session) {
        CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=[session isEqual:@"a"]?@[@[R(@"1",@"a",100,@"text"),R(@"2",@"a",101,@"text"),R(@"3",@"a",200,@"text")]]:@[@[R(@"1",@"b",100,@"text")]];
        WUStatsBinding *b=[self binding:mgr]; b.session=session; return b;
    };
    WUStatsOverviewJob *job=[[WUStatsOverviewJob alloc] initWithBinding:base]; XCTestExpectation *done=[self expectationWithDescription:@"overview"];
    [job start:^(NSDictionary *r,NSString *s){if(r){ XCTAssertEqualObjects(r[@"processed"],@2); XCTAssertEqualObjects(r[@"rank"][0][@"id"],@"a"); XCTAssertEqualObjects(r[@"rank"][0][@"count"],@2); XCTAssertEqualObjects(r[@"rank"][1][@"count"],@1); XCTAssertEqualObjects(r[@"complete"],@YES); [done fulfill]; }}];
    [self waitForExpectations:@[done] timeout:5];
}
- (void)testOverviewEnumeratesAdditionalCandidatesAndMarksCoverageUnknown {
    WUStatsBinding *base=[WUStatsBinding new]; base.stillCurrent=^BOOL{return YES;};
    base.sessions=@[@{@"username":@"a",@"kind":@"private"}];
    __weak WUStatsBinding *weakBase=base;
    base.readSessions=^(BOOL (^current)(void), void (^done)(NSArray *,BOOL)) {
        NSArray *extra=@[@{@"username":@"b",@"kind":@"chatroom"},@{@"username":@"a",@"kind":@"private"}];
        dispatch_async(dispatch_get_main_queue(),^{ if(current()) { weakBase.sessions=[weakBase.sessions arrayByAddingObjectsFromArray:extra]; done(extra,NO); } });
    };
    base.bindingForSession=^WUStatsBinding *(NSString *session){ CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[]]; WUStatsBinding *b=[self binding:mgr]; b.session=session; return b; };
    WUStatsOverviewJob *job=[[WUStatsOverviewJob alloc] initWithBinding:base]; XCTestExpectation *done=[self expectationWithDescription:@"extended candidates"];
    [job start:^(NSDictionary *r,NSString *s){ if(r) { XCTAssertEqualObjects(r[@"processed"],@2); XCTAssertEqualObjects(r[@"sessions"],@2); XCTAssertEqualObjects(r[@"complete"],@NO); [done fulfill]; } }];
    [self waitForExpectations:@[done] timeout:5];
}
- (void)testOverviewCancellationDuringEnumerationRejectsLateResult {
    WUStatsBinding *base=[WUStatsBinding new]; base.stillCurrent=^BOOL{return YES;};
    __block void (^finish)(NSArray *,BOOL); __block BOOL (^gate)(void); __block NSUInteger calls=0;
    base.readSessions=^(BOOL (^current)(void),void (^done)(NSArray *,BOOL)){gate=[current copy];finish=[done copy];};
    base.bindingForSession=^WUStatsBinding *(NSString *s){calls++;return nil;};
    WUStatsOverviewJob *job=[[WUStatsOverviewJob alloc] initWithBinding:base]; [job start:^(NSDictionary *r,NSString *s){ XCTFail(@"late callback"); }];
    [job cancel]; XCTAssertFalse(gate()); finish(@[@{@"username":@"a",@"kind":@"private"}],NO); XCTAssertEqual(calls,0u);
}
- (void)testOverviewSessionCapIsExplicitlyPartial {
    WUStatsBinding *base=[WUStatsBinding new]; base.stillCurrent=^BOOL{return YES;};
    NSMutableArray *sessions=[NSMutableArray array]; for(NSUInteger i=0;i<51;i++) [sessions addObject:@{@"username":[NSString stringWithFormat:@"synthetic-%03lu",(unsigned long)i],@"kind":@"private"}]; base.sessions=sessions;
    base.bindingForSession=^WUStatsBinding *(NSString *session){ CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[]]; return [self binding:mgr]; };
    WUStatsOverviewJob *job=[[WUStatsOverviewJob alloc] initWithBinding:base]; XCTestExpectation *done=[self expectationWithDescription:@"cap"];
    [job start:^(NSDictionary *r,NSString *s){if(r){XCTAssertEqualObjects(r[@"complete"],@NO); XCTAssertEqualObjects(r[@"processed"],@50); XCTAssertEqualObjects(r[@"pages"],@50); [done fulfill];}}];
    [self waitForExpectations:@[done] timeout:10];
}
- (void)testOverviewCancellationPreventsNextSession {
    WUStatsBinding *base=[WUStatsBinding new]; base.stillCurrent=^BOOL{return YES;}; base.sessions=@[@{@"username":@"a",@"kind":@"private"},@{@"username":@"b",@"kind":@"private"}];
    __block NSUInteger bindings=0;
    base.bindingForSession=^WUStatsBinding *(NSString *session){bindings++; CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[R(@"1",@"a",100,@"text")],@[]]; return [self binding:mgr];};
    WUStatsOverviewJob *job=[[WUStatsOverviewJob alloc] initWithBinding:base];
    [job start:^(NSDictionary *r,NSString *s){[job cancel];}];
    XCTestExpectation *done=[self expectationWithDescription:@"cancel overview"];
    dispatch_async(dispatch_get_main_queue(),^{XCTAssertTrue(job.cancelled); XCTAssertEqual(bindings,1u); [done fulfill];});
    [self waitForExpectations:@[done] timeout:5];
}
- (void)testVerifiedDateBoundaryDoesNotCutEqualSecondPages {
    CMessageMgr *mgr=[CMessageMgr new]; mgr.pages=@[@[R(@"1",@"a",100,@"text")],@[R(@"2",@"b",100,@"text")],@[R(@"3",@"a",99,@"text")],@[]];
    WUStatsBinding *b=[self binding:mgr]; b.dateRange=@{@"start":@100,@"end":@200}; b.descendingTimeVerified=YES;
    b.decodePage=^NSDictionary *(NSArray *p,uint32_t left,NSDictionary *cursor){return @{@"records":p,@"done":@(left==0),@"next":@{@"id":@([cursor[@"id"] unsignedIntValue]-1),@"time":p.count?p[0][@"time"]:@0}};};
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:b]; XCTestExpectation *done=[self expectationWithDescription:@"boundary"];
    [job start:^(NSDictionary *r,NSString *s){if(r){XCTAssertEqualObjects(r[@"total"],@2); XCTAssertEqual(mgr.calls,3u); XCTAssertEqualObjects(r[@"complete"],@YES); [done fulfill];}}];
    [self waitForExpectations:@[done] timeout:5];
}
- (void)testOverviewSharesHundredPageBudgetAcrossSessions {
    CMessageMgr *mgr=[CMessageMgr new]; NSMutableArray *pages=[NSMutableArray array]; for(NSUInteger i=0;i<101;i++) [pages addObject:@[R(@"1",@"a",100,@"text")]]; mgr.pages=pages;
    WUStatsBinding *base=[WUStatsBinding new]; base.stillCurrent=^BOOL{return YES;}; base.sessions=@[@{@"username":@"a",@"kind":@"private"},@{@"username":@"b",@"kind":@"private"}];
    __block NSUInteger bindings=0; base.bindingForSession=^WUStatsBinding *(NSString *session){bindings++; return [self binding:mgr];};
    WUStatsOverviewJob *job=[[WUStatsOverviewJob alloc] initWithBinding:base]; XCTestExpectation *done=[self expectationWithDescription:@"shared budget"];
    [job start:^(NSDictionary *r,NSString *s){if(r){XCTAssertEqualObjects(r[@"complete"],@NO); XCTAssertEqualObjects(r[@"pages"],@100); XCTAssertEqualObjects(r[@"processed"],@1); XCTAssertEqual(bindings,1u); XCTAssertEqual(mgr.calls,100u); [done fulfill];}}];
    [self waitForExpectations:@[done] timeout:10];
}
- (void)testVisitFullAndCorruptIndexRefuseMutation {
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *account=WUStatsVisitID(@"synthetic-a",@""); NSURL *file=[root URLByAppendingPathComponent:[account stringByAppendingString:@".plist"]];
    NSMutableArray *events=[NSMutableArray array]; for(NSUInteger i=0;i<4096;i++) [events addObject:@{@"session":WUStatsVisitID(account,@"a"),@"kind":@"unknown",@"time":@(i+1)}];
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:@{@"version":@1,@"account":account,@"events":events} format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil]; [data writeToURL:file atomically:YES];
    WUStatsVisitStore *store=[[WUStatsVisitStore alloc] initWithDirectory:root account:@"synthetic-a"];
    XCTAssertTrue([store.snapshot[@"full"] boolValue]);
    XCTAssertFalse([store recordSession:@"b" kind:@"unknown" time:5000 active:YES enabled:YES current:^BOOL{return YES;}]);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:file],data);
    NSData *bad=[@"synthetic-corrupt" dataUsingEncoding:NSUTF8StringEncoding]; [bad writeToURL:file atomically:YES];
    XCTAssertFalse([store.snapshot[@"valid"] boolValue]); XCTAssertFalse([store clearIfCurrent:^BOOL{return YES;}]);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:file],bad);
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
}
- (void)testVisitRankingRangeAndInputOrderConsistency {
    NSArray *events=@[@{@"session":@"b",@"kind":@"chatroom",@"time":@100},@{@"session":@"a",@"kind":@"private",@"time":@100},@{@"session":@"b",@"kind":@"chatroom",@"time":@200},@{@"session":@"a",@"kind":@"unknown",@"time":@101}];
    NSDictionary *range=@{@"start":@100,@"end":@200};
    NSArray *ranking=WUStatsVisitRanking(events,range);
    XCTAssertEqualObjects(ranking,WUStatsVisitRanking(events.reverseObjectEnumerator.allObjects,range));
    XCTAssertEqualObjects(ranking[0],(@{@"id":@"a",@"count":@2,@"kind":@"unknown"}));
    XCTAssertEqualObjects(ranking[1][@"count"],@1);
    XCTAssertEqualObjects(WUStatsVisitRanking(events,nil)[0][@"id"],@"a");
}
- (void)testVisitWriteThenCancelLeavesPreviousIndex {
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    WUStatsVisitStore *store=[[WUStatsVisitStore alloc] initWithDirectory:root account:@"synthetic-a"];
    XCTAssertTrue([store recordSession:@"a" kind:@"unknown" time:100 active:YES enabled:YES current:^BOOL{return YES;}]);
    __block BOOL current=YES;
    store.writeData=^BOOL(NSData *data,NSURL *url){ BOOL ok=[data writeToURL:url options:NSDataWritingWithoutOverwriting error:nil]; current=NO; return ok; };
    XCTAssertFalse([store recordSession:@"b" kind:@"unknown" time:101 active:YES enabled:YES current:^BOOL{return current;}]);
    XCTAssertEqual([store.snapshot[@"events"] count],1u);
    XCTAssertEqual([[NSFileManager.defaultManager contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:0 error:nil] count],1u);
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
}
- (void)testVisitCommitRechecksGenerationAndReloadDebounce {
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    WUStatsVisitStore *store=[[WUStatsVisitStore alloc] initWithDirectory:root account:@"synthetic-a"];
    __block NSUInteger checks=0;
    XCTAssertFalse([store recordSession:@"a" kind:@"unknown" time:100 active:YES enabled:YES current:^BOOL{return ++checks==1;}]);
    XCTAssertEqual([store.snapshot[@"events"] count],0u);
    XCTAssertTrue([store recordSession:@"a" kind:@"unknown" time:100 active:YES enabled:YES current:^BOOL{return YES;}]);
    WUStatsVisitStore *reloaded=[[WUStatsVisitStore alloc] initWithDirectory:root account:@"synthetic-a"];
    XCTAssertFalse([reloaded recordSession:@"a" kind:@"unknown" time:101 active:YES enabled:YES current:^BOOL{return YES;}]);
    NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:0 error:nil];
    NSData *data=[NSData dataWithContentsOfURL:files.firstObject];
    NSDictionary *plist=[NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil];
    XCTAssertFalse([plist.description containsString:@"synthetic-a"]); XCTAssertEqual([plist[@"events"][0][@"session"] length],64u);
    XCTAssertEqualObjects(reloaded.snapshot[@"events"],store.snapshot[@"events"]);
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
}
@end
