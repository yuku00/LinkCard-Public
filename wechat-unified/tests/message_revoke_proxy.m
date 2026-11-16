#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <assert.h>
#import "WUVerifiedServiceProxy.h"
#include "core_match.inc"
static NSString *account=@"me";
static NSUInteger generation=1;
static id service, oldMessage;
static unsigned originalCalls, lookups;
static BOOL switchAccount;
static unsigned notices;
static void WURevokeNoticeInsert(id mgr, NSString *a, NSString *s, uint64_t mid, NSUInteger gen, NSString *from, NSString *to, uint32_t time, BOOL (^valid)(void)) {
    assert([a isEqual:@"me"] && [s isEqual:@"peer"] && mid==42 && gen==1);
    assert([from isEqual:@"peer"] && [to isEqual:@"me"] && time==456 && valid()); notices++;
}
static BOOL WUEnabled(NSString *key) { return YES; }
static NSString *Account(void) { return account; }
static NSString *Str(id o, NSString *key) { return @"notice"; }
static uint64_t Num(id o, NSString *key) { return 456; }
static NSDictionary *WURevokeFields(NSString *s) { return @{@"session":@"peer",@"id":@42}; }
static id Service(NSString *name) { return service; }
static NSDictionary *Info(id o) { return o?:@{}; }
static BOOL InSession(NSDictionary *m, NSString *a, NSString *s) { return [m[@"from"] isEqual:s] && [m[@"to"] isEqual:a]; }
static BOOL WUOwnMessage(NSString *a, NSString *s, NSString *f, NSString *r) { return [a isEqual:f]; }
static BOOL Has(id o, NSString *s, const char *r, NSArray *a) { return o && WUMatches(class_getInstanceMethod(object_getClass(o),NSSelectorFromString(s)),r,a); }
#include "revoke.inc"
@interface CMessageMgr : NSObject
- (id)GetMsg:(id)session n64SvrID:(long long)mid;
@end
@implementation CMessageMgr
- (id)GetMsg:(id)session n64SvrID:(long long)mid { lookups++; assert([session isEqual:@"peer"] && mid==42); if(switchAccount) account=@"other"; return oldMessage; }
@end
@interface MessageProxy : NSProxy { id _target; BOOL _bad; }
+ (id)target:(id)target bad:(BOOL)bad;
@end
@implementation MessageProxy
+ (id)target:(id)target bad:(BOOL)bad { MessageProxy *p=[self alloc]; p->_target=target; p->_bad=bad; return p; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return _bad?[NSMethodSignature signatureWithObjCTypes:"@@:@i"]:[_target methodSignatureForSelector:s]; }
- (void)forwardInvocation:(NSInvocation *)v { [v invokeWithTarget:_target]; }
@end
static void Original(id obj, SEL cmd, id notice) { originalCalls++; }
int main(void) { @autoreleasepool {
    revokeOriginal=(IMP)Original;
    oldMessage=@{@"id":@42,@"from":@"peer",@"to":@"me",@"real":@""};
    CMessageMgr *mgr=[CMessageMgr new]; service=[MessageProxy target:mgr bad:NO];
    assert(LookupReady(service)); Revoke(nil,NULL,nil); assert(lookups==1 && originalCalls==0 && notices==1);
    service=[MessageProxy target:mgr bad:YES]; assert(!LookupReady(service)); Revoke(nil,NULL,nil); assert(lookups==1 && originalCalls==1);
    service=[MessageProxy target:mgr bad:NO]; switchAccount=YES; Revoke(nil,NULL,nil); assert(lookups==2 && originalCalls==2);
    switchAccount=NO; account=@"me"; oldMessage=nil; Revoke(nil,NULL,nil); assert(lookups==3 && originalCalls==3);
    puts("message revoke proxy mock: OK");
} return 0; }
