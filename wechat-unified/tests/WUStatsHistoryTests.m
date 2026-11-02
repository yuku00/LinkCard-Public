#import <XCTest/XCTest.h>
#import "WUStats.h"
#import <objc/runtime.h>
// Standalone synthetic hosts; never linked into the production dylib.
@interface CMessageMgr : NSObject
@property(nonatomic,strong) NSArray *pages;
@property(nonatomic) NSUInteger calls;
@end
@interface WUHistorySource : CMessageMgr
@property(nonatomic,strong) NSArray *appPages;
@property(nonatomic,strong) NSMutableArray *requests;
@property(nonatomic) NSUInteger appCalls;
- (NSArray *)app:(uint64_t)mid time:(uint64_t)time limit:(uint64_t)limit;
@end
@implementation WUHistorySource
- (NSArray *)app:(uint64_t)mid time:(uint64_t)time limit:(uint64_t)limit {
    NSAssert(limit==200,@"exact page limit");
    if(!self.requests) self.requests=[NSMutableArray array];
    [self.requests addObject:@[@(mid),@(time),@(limit)]];
    NSArray *page=self.appPages[MIN(self.appCalls,self.appPages.count-1)]; self.appCalls++; return page;
}
@end
@interface WUHistory32 : WUHistorySource @end
@implementation WUHistory32
- (NSArray *)GetAppMsgList:(NSString *)session FromID:(uint32_t)mid CreateTime:(uint32_t)time Limit:(uint32_t)limit { return [self app:mid time:time limit:limit]; }
@end
@interface WUHistory64 : WUHistorySource @end
@implementation WUHistory64
- (NSArray *)GetAppMsgList:(NSString *)session FromID:(uint64_t)mid CreateTime:(int64_t)time Limit:(uint64_t)limit { return [self app:mid time:time limit:limit]; }
@end
@interface WUHistorySigned : WUHistorySource @end
@implementation WUHistorySigned
- (NSArray *)GetAppMsgList:(NSString *)session FromID:(int32_t)mid CreateTime:(int32_t)time Limit:(int32_t)limit { return [self app:mid time:time limit:limit]; }
@end
@interface WUHistoryBad : WUHistorySource @end
@implementation WUHistoryBad
- (NSArray *)GetAppMsgList:(NSString *)session FromID:(id)mid CreateTime:(double)time Limit:(uint32_t)limit { self.appCalls++; return @[]; }
@end
@interface WUHistoryPay : NSObject
@property(nonatomic,copy) NSString *m_c2cNativeUrl;
@property(nonatomic) uint32_t m_sceneId;
@end
@implementation WUHistoryPay @end
@interface CMessageWrap : NSObject
@property(nonatomic,copy) NSString *m_nsFromUsr, *m_nsToUsr, *m_nsRealChatUsr, *m_nsContent;
@property(nonatomic) uint64_t m_n64MesSvrID;
@property(nonatomic) uint32_t m_uiMesLocalID, m_uiCreateTime, m_uiMessageType, m_uiAppMsgInnerType;
@property(nonatomic,strong) WUHistoryPay *m_oWCPayInfoItem;
@end
@implementation CMessageWrap @end
static CMessageWrap *Wrap(uint64_t sid,uint32_t lid,uint32_t time,BOOL mine) {
    CMessageWrap *w=[CMessageWrap new]; w.m_n64MesSvrID=sid; w.m_uiMesLocalID=lid; w.m_uiCreateTime=time; w.m_uiMessageType=1;
    w.m_nsFromUsr=mine?@"me":@"peer"; w.m_nsToUsr=mine?@"peer":@"me"; w.m_nsContent=@"same synthetic body"; return w;
}
static WUStatsBinding *Binding(WUHistorySource *mgr) {
    WUStatsBinding *b=[WUStatsBinding new]; b.account=@"me"; b.session=@"peer"; b.messageManager=mgr; b.stillCurrent=^BOOL{ return YES; };
    b.verifiedEncoding=[NSString stringWithUTF8String:method_getTypeEncoding(class_getInstanceMethod(mgr.class,NSSelectorFromString(@"GetMsgByCreateTime:FromID:FromCreateTime:Limit:LeftCount:")))];
    b.initialCursor=@{@"id":@0,@"time":@0}; b.scanAppMessages=YES; b.appEncoding=WUStatsAppMethodEncoding(mgr);
    b.decodePage=^NSDictionary *(NSArray *p,uint32_t left,NSDictionary *c){ return WUStatsDecodeHostPage(p,left,@"me",@"peer",NO); };
    b.decodeAppPage=^NSDictionary *(NSArray *p,NSDictionary *c){ return WUStatsDecodeHostPage(p,0,@"me",@"peer",YES); };
    return b;
}
@interface WUStatsHistoryTests : XCTestCase @end
@implementation WUStatsHistoryTests
- (NSDictionary *)run:(WUStatsBinding *)binding {
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:binding]; XCTestExpectation *done=[self expectationWithDescription:@"production job"];
    __block NSDictionary *result=nil;
    [job start:^(NSDictionary *r,NSString *s){ if(r) { result=r; [done fulfill]; } }];
    [self waitForExpectations:@[done] timeout:10]; return result;
}
- (void)testProductionShortPagesEmptyTerminalAndWidth32And64 {
    for(Class cls in @[WUHistory32.class,WUHistory64.class]) {
        WUHistorySource *mgr=[cls new]; mgr.pages=@[@[Wrap(1,12,100,YES)],@[]];
        mgr.appPages=@[@[Wrap(2,UINT32_MAX,200,NO)],@[Wrap(3,UINT32_MAX-1,200,NO)],@[]];
        NSDictionary *r=[self run:Binding(mgr)];
        XCTAssertEqualObjects(r[@"complete"],@YES); XCTAssertEqualObjects(r[@"pages"],@5); XCTAssertEqualObjects(r[@"scanned"],@3);
        XCTAssertEqualObjects(mgr.requests,(@[@[@0,@0,@200],@[@(UINT32_MAX),@200,@200],@[@(UINT32_MAX-1),@200,@200]]));
        XCTAssertEqualObjects(r[@"total"],@3);
    }
}
- (void)testPhaseResetAndVerifiedServerOverlapOnly {
    WUHistory32 *mgr=[WUHistory32 new];
    mgr.pages=@[@[Wrap(99,30,100,YES),Wrap(0,29,101,YES)],@[]];
    CMessageWrap *payment=Wrap(99,500,100,YES); payment.m_uiMessageType=49; payment.m_oWCPayInfoItem=[WUHistoryPay new]; payment.m_oWCPayInfoItem.m_c2cNativeUrl=@"wxpay://c2ctransfer/transfer?x=1";
    mgr.appPages=@[@[payment,Wrap(0,29,102,NO)],@[]];
    NSDictionary *r=[self run:Binding(mgr)];
    XCTAssertEqualObjects(r[@"total"],@3); XCTAssertEqualObjects(r[@"duplicates"],@1); XCTAssertEqualObjects(r[@"types"][@"transfer"],@1);
    XCTAssertEqualObjects(r[@"replyCount"],@0); // No normal -> App reply edge.
    XCTAssertEqualObjects(r[@"scanned"],@4); // Budget counts duplicates too.
}
- (void)testAppCursorMinimumPositiveTimeAndNoBodyIdentity {
    NSArray *page=@[Wrap(0,20,99,YES),Wrap(0,8,0,YES),Wrap(0,8,10,YES),Wrap(0,8,9,YES)];
    NSDictionary *d=WUStatsDecodeHostPage(page,0,@"me",@"peer",YES);
    XCTAssertEqualObjects(d[@"next"],(@{@"id":@8,@"time":@9})); XCTAssertEqualObjects(d[@"done"],@NO);
    XCTAssertEqualObjects(d[@"records"][0][@"source"],@"app"); XCTAssertEqualObjects(d[@"records"][0][@"sid"],@"0");
    CMessageWrap *full=Wrap(UINT64_MAX,7,10,YES);
    XCTAssertEqualObjects(WUStatsDecodeHostPage(@[full],0,@"me",@"peer",NO)[@"records"][0][@"sid"],@"18446744073709551615");
    full.m_nsToUsr=@"another"; XCTAssertNil(WUStatsDecodeHostPage(@[full],0,@"me",@"peer",YES));
    XCTAssertNil(WUStatsDecodeHostPage(@[[NSObject new]],0,@"me",@"peer",YES));
}
- (void)testAppAdvanceUsesProvedEitherAxisNotGuessedDirection {
    WUHistory32 *mgr=[WUHistory32 new]; mgr.pages=@[@[]];
    mgr.appPages=@[@[Wrap(1,20,100,YES)],@[Wrap(2,21,99,NO)],@[]];
    NSDictionary *r=[self run:Binding(mgr)]; XCTAssertEqualObjects(r[@"complete"],@YES); XCTAssertEqual(mgr.appCalls,3u);
}
- (void)testStalledAppCursorAndShortPageNotEnd {
    WUHistory32 *mgr=[WUHistory32 new]; mgr.pages=@[@[]]; mgr.appPages=@[@[Wrap(1,20,100,YES)]];
    NSDictionary *r=[self run:Binding(mgr)]; XCTAssertEqualObjects(r[@"complete"],@NO); XCTAssertEqual(mgr.appCalls,2u);
    XCTAssertEqualObjects(r[@"total"],@1); XCTAssertEqualObjects(r[@"duplicates"],@1);
}
- (void)testInvalidSignatureAndSignedRangeDoNotInvokeWrongABI {
    WUHistoryBad *bad=[WUHistoryBad new]; bad.pages=@[@[]]; bad.appPages=@[@[]];
    XCTAssertNil(WUStatsAppMethodEncoding(bad)); XCTAssertEqualObjects([self run:Binding(bad)][@"complete"],@NO); XCTAssertEqual(bad.appCalls,0u);
    WUHistorySigned *mgr=[WUHistorySigned new]; mgr.pages=@[@[]]; mgr.appPages=@[@[Wrap(1,UINT32_MAX,100,YES)],@[]];
    XCTAssertEqualObjects([self run:Binding(mgr)][@"complete"],@NO); XCTAssertEqual(mgr.appCalls,1u);
    WUHistory32 *changed=[WUHistory32 new]; changed.pages=@[@[]]; changed.appPages=@[@[]]; WUStatsBinding *b=Binding(changed); b.appEncoding=@"mismatched";
    XCTAssertEqualObjects([self run:b][@"complete"],@NO); XCTAssertEqual(changed.appCalls,0u);
}
- (void)testSharedPageBudgetAcrossTransition {
    WUHistory32 *mgr=[WUHistory32 new]; mgr.pages=@[@[Wrap(1,50,100,YES)],@[]]; mgr.appPages=@[@[Wrap(2,20,200,NO)],@[]];
    WUStatsBinding *b=Binding(mgr); b.pageLimit=3;
    NSDictionary *r=[self run:b]; XCTAssertEqualObjects(r[@"complete"],@NO); XCTAssertEqualObjects(r[@"pages"],@3);
    XCTAssertEqual(mgr.calls,2u); XCTAssertEqual(mgr.appCalls,1u); XCTAssertEqualObjects(r[@"total"],@2);
}
- (void)testTwentyThousandRawRowsBudgetCannotBeEvadedByDuplicates {
    WUHistory32 *mgr=[WUHistory32 new]; NSMutableArray *pages=[NSMutableArray array];
    for(uint32_t p=0;p<100;p++) { NSMutableArray *rows=[NSMutableArray array]; for(NSUInteger i=0;i<200;i++) [rows addObject:Wrap(1,1000-p,100,YES)]; [pages addObject:rows]; }
    [pages addObject:@[]]; mgr.pages=pages; mgr.appPages=@[@[]];
    NSDictionary *r=[self run:Binding(mgr)];
    XCTAssertEqualObjects(r[@"pages"],@100); XCTAssertEqualObjects(r[@"scanned"],@20000); XCTAssertEqualObjects(r[@"complete"],@NO);
    XCTAssertEqualObjects(r[@"total"],@1); XCTAssertEqual(mgr.calls,100u); XCTAssertEqual(mgr.appCalls,0u);
}
- (void)testCancelAtTransitionAndDuringAppPage {
    for(NSNumber *duringApp in @[@NO,@YES]) {
        WUHistory32 *mgr=[WUHistory32 new]; mgr.pages=@[@[]]; mgr.appPages=@[@[Wrap(1,100,100,YES)],@[Wrap(2,90,99,NO)],@[]];
        WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:Binding(mgr)]; __block BOOL result=NO;
        [job start:^(NSDictionary *r,NSString *s){ if(r) result=YES; if(!duringApp.boolValue || mgr.appCalls) [job cancel]; }];
        XCTestExpectation *drain=[self expectationWithDescription:@"cancel queue"];
        dispatch_async(dispatch_get_main_queue(),^{ dispatch_async(dispatch_get_main_queue(),^{ XCTAssertFalse(result); XCTAssertEqual(mgr.appCalls,duringApp.boolValue?1u:0u); [drain fulfill]; }); });
        [self waitForExpectations:@[drain] timeout:3];
    }
}
- (void)testDateBoundaryStillScansAppAndSameSecond {
    WUHistory32 *mgr=[WUHistory32 new]; mgr.pages=@[@[Wrap(1,50,50,YES)],@[]]; mgr.appPages=@[@[Wrap(2,50,100,NO)],@[Wrap(3,49,100,NO)],@[]];
    WUStatsBinding *b=Binding(mgr); b.descendingTimeVerified=YES; b.dateRange=@{@"start":@100,@"end":@101};
    NSDictionary *r=[self run:b]; XCTAssertEqualObjects(r[@"total"],@2); XCTAssertEqualObjects(r[@"complete"],@YES); XCTAssertEqual(mgr.calls,1u); XCTAssertEqual(mgr.appCalls,3u);
}
- (void)testProductionRejectsBadReturnAndContextChangeBetweenPhases {
    WUHistory32 *bad=[WUHistory32 new]; bad.pages=@[@[]]; bad.appPages=@[NSNull.null];
    XCTAssertEqualObjects([self run:Binding(bad)][@"complete"],@NO); XCTAssertEqual(bad.appCalls,1u);
    WUHistory32 *mgr=[WUHistory32 new]; mgr.pages=@[@[]]; mgr.appPages=@[@[]];
    WUStatsBinding *b=Binding(mgr); __block BOOL current=YES; b.stillCurrent=^BOOL{ return current; };
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:b]; XCTestExpectation *done=[self expectationWithDescription:@"context changed"];
    [job start:^(NSDictionary *r,NSString *s){ XCTAssertNil(r); if(job.cancelled) [done fulfill]; else current=NO; }];
    [self waitForExpectations:@[done] timeout:3]; XCTAssertEqual(mgr.appCalls,0u);
}
- (void)testProductionGroupSenderNeverUsesRoomIdentity {
    CMessageWrap *w=Wrap(1,9,100,NO); w.m_nsFromUsr=@"r@chatroom"; w.m_nsToUsr=nil; w.m_nsRealChatUsr=@"r@chatroom";
    NSDictionary *d=WUStatsDecodeHostPage(@[w],0,@"me",@"r@chatroom",YES);
    XCTAssertEqualObjects(d[@"records"][0][@"sender"],@"");
    w.m_nsRealChatUsr=@"member"; XCTAssertEqualObjects(WUStatsDecodeHostPage(@[w],0,@"me",@"r@chatroom",YES)[@"records"][0][@"sender"],@"member");
}
- (void)testPaymentFieldsOnlyMutuallyExclusiveAndNoLocalTransactionID {
    CMessageWrap *w=Wrap(1,1,100,YES); w.m_uiMessageType=49; w.m_nsContent=@"<type>2001</type> wxpay://c2ctransfer transfer 红包";
    NSString *(^kind)(void)=^NSString *{ return WUStatsDecodeHostPage(@[w],0,@"me",@"peer",YES)[@"records"][0][@"type"]; };
    XCTAssertEqualObjects(kind(),@"appUnknown");
    w.m_uiAppMsgInnerType=2001; XCTAssertEqualObjects(kind(),@"appUnknown"); // Missing scene is not zero.
    w.m_oWCPayInfoItem=[WUHistoryPay new]; w.m_oWCPayInfoItem.m_sceneId=1003; XCTAssertEqualObjects(kind(),@"transfer");
    w.m_oWCPayInfoItem.m_c2cNativeUrl=@"wxpay://c2cbizmessagehandler/hongbao/receivehongbao?sendid=synthetic";
    XCTAssertEqualObjects(kind(),@"appUnknown"); // Conflicting trusted fields, not a double count.
    w.m_uiAppMsgInnerType=0; XCTAssertEqualObjects(kind(),@"redpacket");
    w.m_oWCPayInfoItem.m_c2cNativeUrl=@"https://example.invalid/?q=wxpay://c2ctransfer"; XCTAssertEqualObjects(kind(),@"appUnknown");
    w.m_oWCPayInfoItem.m_c2cNativeUrl=@"wxpay://c2ctransfer.evil/"; XCTAssertEqualObjects(kind(),@"appUnknown");
    w.m_oWCPayInfoItem.m_c2cNativeUrl=@"wxpay://c2ctransfer/";
    NSDictionary *a=WUStatsDecodeHostPage(@[w],0,@"me",@"peer",NO)[@"records"][0]; w.m_n64MesSvrID=2;
    NSDictionary *b=WUStatsDecodeHostPage(@[w],0,@"me",@"peer",YES)[@"records"][0];
    WUStatsAccumulator *acc=[[WUStatsAccumulator alloc] initWithTimeZone:NSTimeZone.localTimeZone group:NO]; [acc addRecords:@[a,b]];
    XCTAssertEqualObjects(acc.result[@"total"],@2); XCTAssertNil(a[@"transactionID"]);
}
@end
