#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <assert.h>
#import "WUMessageServiceCompatibility.h"
#include "core_match.inc"
@class UIViewController;
#include "request_revoke.inc"
@interface CMessageMgr : NSObject
@property unsigned calls;
- (void)RevokeMsg:(id)s MsgWrap:(id)w Counter:(unsigned int)c;
- (NSArray *)GetMsgByCreateTime:(id)s FromID:(unsigned int)i FromCreateTime:(unsigned int)t Limit:(unsigned int)n LeftCount:(unsigned int *)left;
- (NSArray *)GetAppMsgList:(id)s FromID:(unsigned int)i CreateTime:(unsigned int)t Limit:(unsigned int)n;
@end
@implementation CMessageMgr
- (void)RevokeMsg:(id)s MsgWrap:(id)w Counter:(unsigned int)c { self.calls++; assert(c==1); }
- (NSArray *)GetMsgByCreateTime:(id)s FromID:(unsigned int)i FromCreateTime:(unsigned int)t Limit:(unsigned int)n LeftCount:(unsigned int *)left { self.calls++; *left=7; return @[]; }
- (NSArray *)GetAppMsgList:(id)s FromID:(unsigned int)i CreateTime:(unsigned int)t Limit:(unsigned int)n { self.calls++; return @[]; }
@end
@interface LegacyService : NSObject
- (void)RevokeMsg:(id)s MsgWrap:(id)w Counter:(unsigned int)c;
@end
@implementation LegacyService
- (void)RevokeMsg:(id)s MsgWrap:(id)w Counter:(unsigned int)c { assert(c==1); }
@end
@interface MockProxy : NSProxy { id _target; BOOL _bad; }
+ (id)target:(id)t bad:(BOOL)b;
@end
@implementation MockProxy
+ (id)target:(id)t bad:(BOOL)b { MockProxy *p=[self alloc]; p->_target=t; p->_bad=b; return p; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return _bad?[NSMethodSignature signatureWithObjCTypes:"v@:@@@"]:[_target methodSignatureForSelector:s]; }
- (void)forwardInvocation:(NSInvocation *)inv { [inv invokeWithTarget:_target]; }
@end
int main(void) { @autoreleasepool {
    CMessageMgr *mgr=[CMessageMgr new]; id proxy=[MockProxy target:mgr bad:NO], bad=[MockProxy target:mgr bad:YES];
    for (NSNumber *n in @[@(WUMessageServiceRevokeShort),@(WUMessageServiceStatsPage),@(WUMessageServiceStatsAppPage)]) {
        WUMessageServiceOperation op=n.unsignedIntegerValue;
        assert(WUMessageServiceEncoding(mgr,op)); assert(WUMessageServiceEncoding(proxy,op)); assert(!WUMessageServiceEncoding(bad,op)); assert(!WUMessageServiceEncoding([NSObject new],op));
    }
    assert(!WUMessageServiceEncoding(proxy,WUMessageServiceRevokeLong));
    LegacyService *legacy=[LegacyService new]; NSString *legacySelector=RevokeSelector(legacy);
    assert(legacySelector); RequestRevoke(legacy,legacySelector,@"peer",@"wrap",nil);
    NSString *revoke=RevokeSelector(proxy); assert([revoke isEqual:@"RevokeMsg:MsgWrap:Counter:"]);
    RequestRevoke(proxy,revoke,@"peer",@"wrap",nil); assert(mgr.calls==1);
    assert(!RevokeSelector(bad));
    @try { RequestRevoke(bad,revoke,@"peer",@"wrap",nil); assert(0); } @catch(NSException *exception) { assert(mgr.calls==1); }
    mgr.calls=0;
    NSString *e=WUMessageServiceEncoding(proxy,WUMessageServiceStatsPage);
    NSInvocation *v=[NSInvocation invocationWithMethodSignature:[NSMethodSignature signatureWithObjCTypes:e.UTF8String]];
    v.selector=NSSelectorFromString(@"GetMsgByCreateTime:FromID:FromCreateTime:Limit:LeftCount:"); v.target=proxy;
    __unsafe_unretained id session=@"peer"; unsigned int zero=0,limit=200,left=0,*p=&left;
    [v setArgument:&session atIndex:2]; [v setArgument:&zero atIndex:3]; [v setArgument:&zero atIndex:4]; [v setArgument:&limit atIndex:5]; [v setArgument:&p atIndex:6]; [v invoke];
    assert(mgr.calls==1 && left==7); puts("message service proxy ABI mock: OK");
} return 0; }
