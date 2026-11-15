#import <Foundation/Foundation.h>
#import "WURevokeNotice.h"
#import <assert.h>

@interface CMessageWrap : NSObject
@property(nonatomic,copy) NSString *m_nsFromUsr, *m_nsToUsr, *m_nsContent;
@property(nonatomic) unsigned int m_uiStatus, m_uiCreateTime;
- (instancetype)initWithMsgType:(unsigned int)type;
@end
@implementation CMessageWrap
- (instancetype)initWithMsgType:(unsigned int)type { assert(type==10000); return [super init]; }
@end
@interface CMessageMgr : NSObject
@property(nonatomic) int calls;
@property(nonatomic,strong) CMessageWrap *last;
@property(nonatomic) BOOL raises;
- (void)AddLocalMsg:(NSString *)session MsgWrap:(CMessageWrap *)wrap fixTime:(BOOL)fix NewMsgArriveNotify:(BOOL)notify;
@end
@implementation CMessageMgr
- (void)AddLocalMsg:(NSString *)session MsgWrap:(CMessageWrap *)wrap fixTime:(BOOL)fix NewMsgArriveNotify:(BOOL)notify {
    assert([session isEqual:@"peer"] && fix && !notify); self.calls++; self.last=wrap;
    if (self.raises) @throw [NSException exceptionWithName:@"partial" reason:nil userInfo:nil];
}
@end
@interface WrongManager : NSObject @end
@implementation WrongManager @end
int main(void) { @autoreleasepool {
    CMessageMgr *mgr=[CMessageMgr new]; __block BOOL valid=YES;
    void (^insert)(id,uint64_t,NSUInteger)=^(id target,uint64_t ident,NSUInteger gen) {
        WURevokeNoticeInsert(target,@"me",@"peer",ident,gen,@"peer",@"me",123, ^BOOL{ return valid; });
    };
    insert(mgr,1,1); assert(mgr.calls==1);
    assert([mgr.last.m_nsContent isEqual:@"对方撤回了一条消息"] && mgr.last.m_uiStatus==4 && mgr.last.m_uiCreateTime==124);
    assert([mgr.last.m_nsFromUsr isEqual:@"peer"] && [mgr.last.m_nsToUsr isEqual:@"me"]);
    insert(mgr,1,1); assert(mgr.calls==1);
    valid=NO; insert(mgr,2,1); assert(mgr.calls==1); valid=YES;
    insert([WrongManager new],2,1); assert(mgr.calls==1);
    mgr.raises=YES; insert(mgr,2,1); assert(mgr.calls==2);
    mgr.raises=NO; insert(mgr,2,1); assert(mgr.calls==2);
    insert(mgr,1,2); assert(mgr.calls==3);
    NSLog(@"WURevokeNotice mock tests passed");
} return 0; }
