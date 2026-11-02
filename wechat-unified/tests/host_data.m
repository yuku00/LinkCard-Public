#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "MomentsCacheComments.h"
#import "MomentsCacheLogic.h"
#import "WUStatsHostProfile.h"
#import "WUHostRead.h"
#import "WUStats.h"
#include <assert.h>
static NSUInteger checks, forbidden;
#define CHECK(x) do { checks++; assert((x)); } while(0)
@interface WCUserComment : NSObject
@property(nonatomic,copy) id commentID;
@property(nonatomic,copy) id comment64ID;
@property(nonatomic,copy) NSString *username;
@property(nonatomic,copy) NSString *content;
@property(nonatomic,copy) NSString *refUserName;
@property(nonatomic) BOOL isLocalAdded;
@property(nonatomic) uint32_t type;
@end
@implementation WCUserComment
- (id)valueForKey:(NSString *)key { forbidden++; [NSException raise:@"KVC forbidden" format:@"not part of adapter contract"]; return nil; }
@end
@interface WCDataItem : NSObject
@property(nonatomic,copy) NSArray *commentUsers;
@end
@implementation WCDataItem @end
@interface CContact : NSObject
@property(nonatomic,copy) NSString *m_nsUsrName;
@property(nonatomic,copy) id m_nsCountry;
@property(nonatomic,copy) id m_nsProvince;
@property(nonatomic,copy) id m_nsChatRoomMemList;
@property(nonatomic) uint32_t m_uiSex;
@property(nonatomic) uint32_t m_uiAge;
@property(nonatomic) uint32_t m_uiLocalAddContactTime;
@property(nonatomic) uint32_t m_uiAddCreateTime;
@property(nonatomic) uint32_t m_uiChatRoomJoinTime;
@property(nonatomic) BOOL isMyContact;
@end
@implementation CContact
- (id)valueForKey:(NSString *)key { forbidden++; [NSException raise:@"KVC forbidden" format:@"not used"]; return nil; }
@end
@interface CContactMgr : NSObject
@property(nonatomic,copy) NSDictionary *contacts;
@property(nonatomic,strong) id roster;
@property(nonatomic) NSUInteger calls;
@end
@implementation CContactMgr
- (id)getContactByName:(NSString *)name { CHECK(NSThread.isMainThread); self.calls++; return self.contacts[name]; }
- (id)getAllContactUserName { CHECK(NSThread.isMainThread); return self.roster; }
- (void)requestContact:(id)value { forbidden++; }
- (void)modifyContact:(id)value { forbidden++; }
@end
@interface CMessageMgr : NSObject
@property(nonatomic) NSUInteger calls;
@end
@implementation CMessageMgr
- (NSArray *)GetMsgByCreateTime:(NSString *)session FromID:(uint32_t)mid FromCreateTime:(uint32_t)time Limit:(uint32_t)limit LeftCount:(uint32_t *)left { self.calls++; *left=0; return @[]; }
@end
static WCUserComment *WUTestHostComment(NSString *cid, NSString *text) {
    WCUserComment *c=[WCUserComment new]; c.type=2; c.commentID=cid; c.username=@"author-id"; c.content=text; c.refUserName=@"reply-id"; return c;
}
static CContact *Person(NSString *name) { CContact *c=[CContact new]; c.m_nsUsrName=name; return c; }
static int32_t BadObjectReturn(id o, SEL s) { forbidden++; return 123; }
static void SpinFor(BOOL (^finished)(void),NSTimeInterval timeout) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:timeout];
    while(!finished() && end.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    CHECK(finished());
}
static void Spin(BOOL (^finished)(void)) { SpinFor(finished,3); }
static void Comments(void) {
    WCDataItem *item=[WCDataItem new]; WCUserComment *c=WUTestHostComment(@"7",@"seen"); item.commentUsers=@[c];
    NSArray *decoded=WUMomentsDecodeDisplayedComments(item,@[c,c]); CHECK(decoded.count==1);
    CHECK([decoded[0][@"id"] isEqual:@"c32:7"] && [decoded[0][@"time"] isEqual:@0] && [decoded[0][@"replyTo"] isEqual:@"reply-id"]);
    CHECK(WUMomentsDecodeDisplayedComments(item,@[WUTestHostComment(@"7",@"same nickname")]).count==0);
    c.type=1; CHECK(WUMomentsDecodeDisplayedComments(item,@[c]).count==0); c.type=2;
    c.isLocalAdded=YES; CHECK(WUMomentsDecodeDisplayedComments(item,@[c]).count==0); c.isLocalAdded=NO;
    c.content=nil; CHECK(WUMomentsDecodeDisplayedComments(item,@[c]).count==0); c.content=@"seen";
    c.commentID=@"0"; c.comment64ID=@"18446744073709551615"; CHECK([WUMomentsDecodeDisplayedComments(item,@[c])[0][@"id"] isEqual:@"c64:18446744073709551615"]);
    c.comment64ID=@"18446744073709551616"; CHECK(WUMomentsDecodeDisplayedComments(item,@[c]).count==0);
    c.commentID=@1.5; c.comment64ID=nil; CHECK(WUMomentsDecodeDisplayedComments(item,@[c]).count==0);
    c.commentID=@"7"; WCUserComment *other=WUTestHostComment(@"7",@"conflict"); item.commentUsers=@[c,other]; CHECK(!WUMomentsDecodeDisplayedComments(item,@[c,other]));
    Class bad=objc_allocateClassPair(WCUserComment.class,"WUCommentWrongABI",0); class_addMethod(bad,@selector(commentID),(IMP)BadObjectReturn,"i@:"); objc_registerClassPair(bad);
    WCUserComment *wrong=[bad new]; wrong.type=2; wrong.username=@"id"; wrong.content=@"body"; item.commentUsers=@[wrong]; CHECK(WUMomentsDecodeDisplayedComments(item,@[wrong]).count==0);
    CHECK(!WUMomentsDecodeDisplayedComments([NSObject new],@[c]));
    NSURL *dir=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSError *error=nil; BOOL (^yes)(void)=^BOOL{ return YES; };
    CHECK(!WUMCacheSaveComments(dir,@"a",@"owner",@"9",decoded,1700000000,yes,&error));
    NSDictionary *parent=WUMCacheNormalize(@"9",@"owner",@"parent already seen");
    CHECK(WUMCacheObserve(dir,@"a",parent,1700000000,&error));
    CHECK(WUMCacheSaveComments(dir,@"a",@"owner",@"9",decoded,1700000001,yes,&error));
    CHECK(WUMCacheSaveComments(dir,@"a",@"owner",@"9",@[],1700000002,yes,&error));
    CHECK([WUMCacheLoad(dir,@"a",&error)[0][@"comments"] count]==1);
    CHECK(!WUMCacheSaveComments(dir,@"a",@"owner",@"9",decoded,1700000003,^BOOL{ return NO; },&error));
    CHECK(!WUMCacheSaveComments(dir,@"b",@"owner",@"9",decoded,1700000003,yes,&error));
    CHECK([WUMCacheLoad(dir,@"a",&error)[0][@"status"] isEqual:@"seen"]);
    [NSFileManager.defaultManager removeItemAtURL:dir error:NULL];
}
static void Profiles(void) {
    CContactMgr *mgr=[CContactMgr new]; CContact *peer=Person(@"peer"), *self=Person(@"self"), *room=Person(@"r@chatroom"), *other=Person(@"q@chatroom"), *bad=Person(@"bad@chatroom");
    peer.m_uiSex=2; peer.m_uiAge=23; peer.m_nsCountry=@"CN"; peer.m_nsProvince=@"unmapped-region"; peer.isMyContact=YES;
    peer.m_uiLocalAddContactTime=1600000000; peer.m_uiAddCreateTime=1500000000;
    room.m_nsChatRoomMemList=@"self;peer;peer;missing"; room.m_uiChatRoomJoinTime=1600000000;
    other.m_nsChatRoomMemList=@"peer;stranger"; bad.m_nsChatRoomMemList=@42;
    mgr.contacts=@{@"peer":peer,@"self":self,@"r@chatroom":room,@"q@chatroom":other,@"bad@chatroom":bad};
    NSDictionary *p=WUStatsContactProfile(mgr,@"peer",1700000000);
    CHECK([p[@"sex"] isEqual:@"female"] && [p[@"age"] isEqual:@23] && [p[@"added"] isEqual:@1600000000]);
    peer.m_uiAge=0; peer.m_uiSex=99; peer.m_nsCountry=@23;
    p=WUStatsContactProfile(mgr,@"peer",1700000000);
    CHECK(p[@"age"]==NSNull.null && [p[@"sex"] isEqual:@"unknown"] && [p[@"country"] isEqual:@""]);
    peer.m_uiLocalAddContactTime=UINT32_MAX;
    CHECK([WUStatsContactProfile(mgr,@"peer",1700000000)[@"addedSource"] isEqual:@"m_uiAddCreateTime"]);
    peer.m_uiAddCreateTime=0; CHECK(WUStatsContactProfile(mgr,@"peer",1700000000)[@"added"]==NSNull.null);
    mgr.contacts=@{@"peer":self}; CHECK(![WUStatsContactProfile(mgr,@"peer",1700000000)[@"available"] boolValue]);
    mgr.contacts=@{@"peer":peer,@"self":self,@"r@chatroom":room,@"q@chatroom":other,@"bad@chatroom":bad};
    CHECK(![WUStatsParseMembers(nil)[@"complete"] boolValue]); CHECK(![WUStatsParseMembers(@[])[@"complete"] boolValue]);
    CHECK([WUStatsParseMembers(@" a ;a;b")[ @"ids"] count]==2);
    NSMutableString *many=[NSMutableString string]; for(NSUInteger i=0;i<801;i++) [many appendFormat:@"u%lu;",(unsigned long)i];
    CHECK([WUStatsParseMembers(many)[@"ids"] count]==800 && ![WUStatsParseMembers(many)[@"complete"] boolValue]);
    NSArray *sessions=@[@{@"username":@"r@chatroom",@"kind":@"chatroom"},@{@"username":@"q@chatroom",@"kind":@"chatroom"},@{@"username":@"bad@chatroom",@"kind":@"chatroom"}];
    __block NSDictionary *value=nil;
    WUStatsReadHostProfile(mgr,@"self",@"peer",sessions,^BOOL{ return YES; },^(NSDictionary *v){ value=v; });
    Spin(^BOOL{ return value!=nil; });
    CHECK([value[@"commonGroups"] isEqual:@[@"r@chatroom"]] && [value[@"unknownRooms"] isEqual:@1]);
    CHECK([[WUStatsProfileLines(WUStatsProfileSummary(value),NSTimeZone.localTimeZone) componentsJoinedByString:@"\n"] length]>0);
    value=nil;
    WUStatsReadHostProfile(mgr,@"self",@"r@chatroom",sessions,^BOOL{ return YES; },^(NSDictionary *v){ value=v; });
    Spin(^BOOL{ return value!=nil; }); NSDictionary *summary=WUStatsProfileSummary(value);
    CHECK([summary[@"memberCount"] isEqual:@3] && [summary[@"unknownContact"] isEqual:@1]);
    CHECK([summary[@"unknownAge"] isEqual:@3] && [summary[@"sex"][@"unknown"] isEqual:@3]);
    // Real adapter, synthetic loaded sessions: dedupe, distinguish false/unknown,
    // never include self or rooms, aggregate only confirmed true flags.
    peer.m_uiSex=2; peer.m_uiAge=23; peer.m_nsCountry=@"CN"; peer.m_nsProvince=@"P";
    self.isMyContact=NO;
    NSArray *privateSessions=@[@{@"username":@"peer",@"kind":@"private"},@{@"username":@"peer",@"kind":@"private"},
        @{@"username":@"self",@"kind":@"private"},@{@"username":@"missing",@"kind":@"private"},
        @{@"username":@"other",@"kind":@"private"},@{@"username":@"r@chatroom",@"kind":@"private"}];
    CContact *notFriend=Person(@"other"); mgr.contacts=@{@"peer":peer,@"self":self,@"other":notFriend}; value=nil;
    WUStatsReadHostProfile(mgr,@"self",@"peer",privateSessions,^BOOL{ return YES; },^(NSDictionary *v){ value=v; });
    Spin(^BOOL{ return value!=nil; }); NSDictionary *f=value[@"loadedFriends"];
    CHECK([f[@"scanned"] isEqual:@3] && [f[@"memberCount"] isEqual:@1]);
    CHECK([f[@"nonFriend"] isEqual:@1] && [f[@"unknownFriend"] isEqual:@1]);
    CHECK([f[@"sex"][@"female"] isEqual:@1] && [f[@"ages"][@"23"] isEqual:@1]);
    CHECK(!f[@"members"] && ![[f description] containsString:@"peer"]);
    CHECK([[WUStatsProfileLines(WUStatsProfileSummary(value),NSTimeZone.localTimeZone) componentsJoinedByString:@"\n"] containsString:@"不是全好友名册"]);
    NSMutableArray *large=[NSMutableArray array]; for(NSUInteger i=0;i<501;i++) [large addObject:@{@"username":[NSString stringWithFormat:@"u%03lu",(unsigned long)i],@"kind":@"private"}];
    value=nil; WUStatsReadHostProfile(mgr,@"self",@"peer",large,^BOOL{ return YES; },^(NSDictionary *v){ value=v; });
    Spin(^BOOL{ return value!=nil; }); f=value[@"loadedFriends"];
    CHECK([f[@"scanned"] isEqual:@500] && [f[@"unknownFriend"] isEqual:@500] && [f[@"truncated"] boolValue]);
    CContact *offline=Person(@"offline"); offline.isMyContact=YES;
    mgr.contacts=@{@"peer":peer,@"offline":offline,@"self":self,@"other":notFriend};
    mgr.roster=@[@"offline",@"offline",@"peer",@"self",@"r@chatroom",@42]; value=nil;
    WUStatsReadHostProfile(mgr,@"self",@"peer",privateSessions,^BOOL{ return YES; },^(NSDictionary *v){ value=v; });
    Spin(^BOOL{ return value!=nil; }); f=value[@"loadedFriends"];
    CHECK([f[@"rosterAvailable"] boolValue] && [f[@"rosterMalformed"] boolValue] && [f[@"truncated"] boolValue]);
    CHECK([f[@"scanned"] isEqual:@4] && [f[@"memberCount"] isEqual:@2] && [f[@"unknownFriend"] isEqual:@1]);
    CHECK([[WUStatsProfileLines(WUStatsProfileSummary(value),NSTimeZone.localTimeZone) componentsJoinedByString:@"\n"] containsString:@"范围未经证实"]);
    mgr.roster=@{@"unexpected":@YES}; value=nil;
    WUStatsReadHostProfile(mgr,@"self",@"peer",privateSessions,^BOOL{ return YES; },^(NSDictionary *v){ value=v; });
    Spin(^BOOL{ return value!=nil; }); CHECK(![value[@"loadedFriends"][@"rosterAvailable"] boolValue]);
    mgr.roster=nil;
    __block BOOL current=YES,delivered=NO;
    WUStatsReadHostProfile(mgr,@"self",@"r@chatroom",sessions,^BOOL{ return current; },^(NSDictionary *v){ delivered=YES; });
    current=NO; NSUInteger calls=mgr.calls; __block BOOL tick=NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ tick=YES; });
    Spin(^BOOL{ return tick; }); CHECK(!delivered && mgr.calls==calls);
}
static WUStatsBinding *Binding(void) {
    WUStatsBinding *b=[WUStatsBinding new]; b.account=@"self"; b.session=@"peer"; b.messageManager=[CMessageMgr new]; b.stillCurrent=^BOOL{ return YES; };
    b.verifiedEncoding=[NSString stringWithUTF8String:method_getTypeEncoding(class_getInstanceMethod(CMessageMgr.class,@selector(GetMsgByCreateTime:FromID:FromCreateTime:Limit:LeftCount:)))];
    b.initialCursor=@{@"id":@0,@"time":@0};
    b.decodePage=^NSDictionary *(NSArray *page,uint32_t left,NSDictionary *cursor){ return @{@"records":@[],@"next":cursor,@"done":@YES}; }; return b;
}
static void Worker(void) {
    WUStatsBinding *b=Binding(); CContactMgr *mgr=[CContactMgr new]; mgr.contacts=@{@"peer":Person(@"peer")};
    b.readProfile=^(BOOL (^current)(void),void (^done)(NSDictionary *)){ WUStatsReadHostProfile(mgr,@"self",@"peer",@[],current,done); };
    WUStatsJob *job=[[WUStatsJob alloc] initWithBinding:b]; __block NSDictionary *result=nil;
    [job start:^(NSDictionary *r,NSString *status){ result=r; }]; Spin(^BOOL{ return result!=nil; });
    CHECK(result[@"profile"]!=nil && [result[@"total"] isEqual:@0]);
    __block void (^later)(NSDictionary *); __block BOOL (^current)(void); __block BOOL delivered=NO;
    b.readProfile=^(BOOL (^valid)(void),void (^done)(NSDictionary *)){ current=[valid copy]; later=[done copy]; };
    job=[[WUStatsJob alloc] initWithBinding:b]; [job start:^(NSDictionary *r,NSString *s){ delivered=YES; }];
    [job cancel]; CHECK(!current()); later(@{}); CHECK(!delivered);
    // Optional profile failures must not freeze or duplicate the existing message scan.
    for(NSUInteger mode=0;mode<4;mode++) {
        WUStatsBinding *probe=Binding(); CMessageMgr *pages=probe.messageManager;
        __block void (^late)(NSDictionary *); __block NSUInteger callbacks=0; __block NSDictionary *output=nil;
        probe.readProfile=^(BOOL (^valid)(void),void (^done)(NSDictionary *)) {
            if(mode==0) @throw [NSException exceptionWithName:@"profile-unavailable" reason:nil userInfo:nil];
            if(mode==1) { done(nil); done(nil); }
            else if(mode==2) late=[done copy]; // The production five-second watchdog handles a missing callback.
            else dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{ done(nil); });
        };
        WUStatsJob *probeJob=[[WUStatsJob alloc] initWithBinding:probe];
        [probeJob start:^(NSDictionary *value,NSString *status){ if(value) { output=value; callbacks++; } }];
        SpinFor(^BOOL{ return output!=nil; },mode==2?7:3);
        CHECK(pages.calls==1 && callbacks==1 && !output[@"profile"] && [output[@"total"] isEqual:@0]);
        CHECK([output[@"profileIssue"] isKindOfClass:NSString.class]);
        if(late) { late(@{}); CHECK(pages.calls==1 && callbacks==1); }
    }
}
int main(void) { @autoreleasepool { CHECK(NSThread.isMainThread); Comments(); Profiles(); Worker(); CHECK(forbidden==0); printf("host-data production mock assertions: %lu\n",(unsigned long)checks); } return 0; }
