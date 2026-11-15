#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
#import <stdatomic.h>
#import "WUHostService.h"
#import "WUVerifiedServiceProxy.h"
#import "WUDiagnosticRing.h"
#include <assert.h>
#include <string.h>
void WURecordAccountDiagnosticEvent(WUDiagnosticEvent event) { (void)event; }
#include "core_match.inc"
#include "account.inc"
static id active, current, legacy;
@interface MMContext : NSObject
#if BAD_CONTEXT
+ (int)activeUserContext;
#else
+ (id)activeUserContext;
#endif
+ (id)currentContext;
@end
@implementation MMContext
#if BAD_CONTEXT
+ (int)activeUserContext { abort(); }
#else
+ (id)activeUserContext { return active; }
#endif
+ (id)currentContext { return current; }
@end
@interface MMServiceCenter : NSObject
+ (id)defaultCenter;
@end
@implementation MMServiceCenter
+ (id)defaultCenter { return legacy; }
@end
@interface CContactMgr : NSObject
@property(nonatomic,strong) id contact;
- (id)getSelfContact;
@end
@implementation CContactMgr
- (id)getSelfContact { return self.contact; }
@end
@interface ChildManager : CContactMgr @end
@implementation ChildManager @end
@interface Contact : NSObject
@property(nonatomic,copy) NSString *m_nsUsrName;
@end
@implementation Contact @end
@interface MainSessionMgr : NSObject @end
@implementation MainSessionMgr @end
@interface MMNewSessionMgr : NSObject
- (id)GetUserNamesOnSessionList;
- (id)GetSessionByUserName:(id)name;
@end
@implementation MMNewSessionMgr
- (id)GetUserNamesOnSessionList { return @[@"alice"]; }
- (id)GetSessionByUserName:(id)name { return name; }
@end
@interface SessionProxy : NSProxy
@property(nonatomic,strong) MMNewSessionMgr *target;
@property(nonatomic) BOOL badLookup;
@end
@implementation SessionProxy
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    if(self.badLookup && selector==@selector(GetSessionByUserName:)) return [NSMethodSignature signatureWithObjCTypes:"i@:@"];
    return [self.target methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.target]; }
@end
@interface Provider : NSObject
@property(nonatomic,strong) id manager;
@property(nonatomic,strong) id homeManager;
@property(nonatomic,strong) id sessionManager;
- (id)getService:(Class)cls;
@end
@implementation Provider
- (id)getService:(Class)cls {
    if(cls==CContactMgr.class) return self.manager;
    if(cls==MainSessionMgr.class) return self.homeManager;
    if(cls==MMNewSessionMgr.class) return self.sessionManager;
    return nil;
}
@end
@interface BadProvider : NSObject
- (int)getService:(int)value;
@end
@implementation BadProvider
- (int)getService:(int)value { abort(); }
@end
@interface BadManager : NSObject
- (int)getSelfContact;
@end
@implementation BadManager
- (int)getSelfContact { abort(); }
@end
@interface BadContact : NSObject
- (int)m_nsUsrName;
@end
@implementation BadContact
- (int)m_nsUsrName { abort(); }
@end
@interface MockProxy : NSProxy {
    id _target;
    int _mode;
}
+ (id)proxy:(id)target mode:(int)mode;
@end
@implementation MockProxy
+ (id)proxy:(id)target mode:(int)mode {
    MockProxy *p=[MockProxy alloc]; p->_target=target; p->_mode=mode; return p;
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    if(selector!=sel_registerName("getSelfContact")) return nil;
    if(_mode==1) return [NSMethodSignature signatureWithObjCTypes:"i@:"];
    if(_mode==2) return [NSMethodSignature signatureWithObjCTypes:"@@:@"];
    if(_mode==3) @throw [NSException exceptionWithName:@"mock" reason:nil userInfo:nil];
    if(_mode==4) return nil;
    return [_target methodSignatureForSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    if(_mode==5 && selector==sel_registerName("getSelfContact")) return _target;
    return nil;
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    if(_mode!=0 && _mode!=5) abort();
    [invocation invokeWithTarget:_target];
}
@end
static Provider *Make(NSString *name) {
    Contact *contact=[Contact new]; contact.m_nsUsrName=name;
    CContactMgr *manager=[CContactMgr new]; manager.contact=contact;
    Provider *provider=[Provider new]; provider.manager=manager; return provider;
}
int main(int argc, const char **argv) { @autoreleasepool {
    if(argc>1) {
        id object=strcmp(argv[1],"subclass")==0?[ChildManager new]:[NSObject new];
        WURecordAccountServiceMismatch(object,WUProviderCurrent);
        NSString *snapshot=WUAccountServiceDiagnosticSnapshot();
        assert([snapshot containsString:@"provider：currentContext"]);
        if(strcmp(argv[1],"subclass")==0) {
            assert([snapshot containsString:@"ChildManager"] && [snapshot containsString:@"CContactMgr或子类：是"]);
            assert([snapshot containsString:@"getSelfContact：存在"] && [snapshot containsString:@"类型编码：@"]);
        } else {
            assert([snapshot containsString:@"NSObject"] && [snapshot containsString:@"getSelfContact：不存在"]);
            assert([snapshot containsString:@"类型编码：无"]);
        }
        return 0;
    }
    SessionProxy *sessionProxy=[SessionProxy alloc]; sessionProxy.target=[MMNewSessionMgr new];
    assert(WUVerifiedProxyMethod(sessionProxy,WUVerifiedSessionNames));
    assert(WUVerifiedProxyMethod(sessionProxy,WUVerifiedSessionLookup));
    assert([((id(*)(id,SEL))objc_msgSend)(sessionProxy,@selector(GetUserNamesOnSessionList)) isEqual:@[@"alice"]]);
    assert([((id(*)(id,SEL,id))objc_msgSend)(sessionProxy,@selector(GetSessionByUserName:),@"alice") isEqual:@"alice"]);
    sessionProxy.badLookup=YES;
    assert(!WUVerifiedProxyMethod(sessionProxy,WUVerifiedSessionLookup));
    assert(!WUVerifiedProxyMethod([NSObject new],WUVerifiedSessionNames));
    legacy=Make(@"legacy"); current=Make(@"current"); active=Make(@"active");
    ((Provider *)current).homeManager=[MainSessionMgr new];
    ((Provider *)current).sessionManager=[MMNewSessionMgr new];
    ((Provider *)legacy).homeManager=[MainSessionMgr new];
    ((Provider *)legacy).sessionManager=[MMNewSessionMgr new];
    ((Provider *)active).homeManager=[MainSessionMgr new];
    ((Provider *)active).sessionManager=[MMNewSessionMgr new];
#if BAD_CONTEXT
    assert(WUHostService(@"MainSessionMgr")==((Provider *)current).homeManager);
    assert(WUHostService(@"MMNewSessionMgr")==((Provider *)current).sessionManager);
#else
    assert(WUHostService(@"MainSessionMgr")==((Provider *)active).homeManager);
    assert(WUHostService(@"MMNewSessionMgr")==((Provider *)active).sessionManager);
    ((Provider *)active).homeManager=nil;
    assert(WUHostService(@"MainSessionMgr")==nil); // no cross-account fallback
#endif
#if BAD_CONTEXT
    WUProviderPath path=WUProviderUnknown;
    assert(WUHostServiceWithPath(@"CContactMgr",&path)==((Provider *)current).manager && path==WUProviderCurrent);
    assert([Account() isEqual:@"current"]); // malformed class method must never be invoked
#else
    WUProviderPath path=WUProviderUnknown;
    assert(WUHostServiceWithPath(@"CContactMgr",&path)==((Provider *)active).manager && path==WUProviderActive);
    assert(WUAccountServiceDiagnosticSnapshot()==nil);
    assert([Account() isEqual:@"active"]); NSUInteger g=generation;
    id original=((Provider *)active).manager;
    for(int mode=1; mode<=4; mode++) {
        ((Provider *)active).manager=[MockProxy proxy:original mode:mode];
        assert(!WUAccountServiceHasSelfContact(((Provider *)active).manager));
    }
    ((Provider *)active).manager=[MockProxy proxy:original mode:0];
    assert([Account() isEqual:@"active"] && generation==g);
    ((Provider *)active).manager=[MockProxy proxy:original mode:5];
    assert([Account() isEqual:@"active"] && generation==g);
    active=Make(@"proxy-other");
    ((Provider *)active).manager=[MockProxy proxy:((Provider *)active).manager mode:0];
    assert([Account() isEqual:@"proxy-other"] && generation==g+1); g=generation;
    active=Make(@"active");
    ((Provider *)active).manager=[MockProxy proxy:((Provider *)active).manager mode:0];
    assert([Account() isEqual:@"active"] && generation==g+1); g=generation;
    assert([Account() isEqual:@"active"] && generation==g);
    active=Make(@"other"); assert([Account() isEqual:@"other"] && generation==g+1); g=generation;
    active=[BadProvider new]; assert(Account()==nil && generation==g+1); g=generation;
    active=Make(@"other"); assert([Account() isEqual:@"other"] && generation==g+1);
    ((Provider *)active).manager=[BadManager new]; assert(Account()==nil);
    NSString *snapshot=WUAccountServiceDiagnosticSnapshot();
    assert([snapshot containsString:@"BadManager"] && [snapshot containsString:@"CContactMgr或子类：否"]);
    assert([snapshot containsString:@"getSelfContact：存在"] && [snapshot containsString:@"类型编码：i"]);
    assert([snapshot containsString:@"provider：activeUserContext"] && ![snapshot containsString:@"other"]);
    ((Provider *)active).manager=[NSObject new]; assert(Account()==nil);
    assert([snapshot isEqual:WUAccountServiceDiagnosticSnapshot()]); // rate limited
    ((Provider *)active).manager=nil; assert(Account()==nil);
    active=Make(@"other");
    ((CContactMgr *)((Provider *)active).manager).contact=[BadContact new]; assert(Account()==nil);
    active=Make(nil); assert(Account()==nil);
    active=nil; assert([Account() isEqual:@"current"]);
#endif
    active=nil; current=nil;
    assert(WUHostServiceWithPath(@"CContactMgr",&path)==((Provider *)legacy).manager && path==WUProviderLegacy);
    assert([Account() isEqual:@"legacy"]);
    legacy=nil; assert(Account()==nil);
    assert(WUHostService(@"AbsentServiceClass")==nil);
    puts("host-service native mock: OK");
} return 0; }
