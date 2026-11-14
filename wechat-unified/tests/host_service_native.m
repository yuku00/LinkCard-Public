#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
#import <stdatomic.h>
#import "WUHostService.h"
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
@interface Contact : NSObject
@property(nonatomic,copy) NSString *m_nsUsrName;
@end
@implementation Contact @end
@interface MainSessionMgr : NSObject @end
@implementation MainSessionMgr @end
@interface MMNewSessionMgr : NSObject @end
@implementation MMNewSessionMgr @end
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
static Provider *Make(NSString *name) {
    Contact *contact=[Contact new]; contact.m_nsUsrName=name;
    CContactMgr *manager=[CContactMgr new]; manager.contact=contact;
    Provider *provider=[Provider new]; provider.manager=manager; return provider;
}
int main(void) { @autoreleasepool {
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
    assert([Account() isEqual:@"current"]); // malformed class method must never be invoked
#else
    assert([Account() isEqual:@"active"]); NSUInteger g=generation;
    assert([Account() isEqual:@"active"] && generation==g);
    active=Make(@"other"); assert([Account() isEqual:@"other"] && generation==g+1); g=generation;
    active=[BadProvider new]; assert(Account()==nil && generation==g+1); g=generation;
    active=Make(@"other"); assert([Account() isEqual:@"other"] && generation==g+1);
    ((Provider *)active).manager=[BadManager new]; assert(Account()==nil);
    ((Provider *)active).manager=nil; assert(Account()==nil);
    active=Make(@"other");
    ((CContactMgr *)((Provider *)active).manager).contact=[BadContact new]; assert(Account()==nil);
    active=Make(nil); assert(Account()==nil);
    active=nil; assert([Account() isEqual:@"current"]);
#endif
    active=nil; current=nil; assert([Account() isEqual:@"legacy"]);
    legacy=nil; assert(Account()==nil);
    assert(WUHostService(@"AbsentServiceClass")==nil);
    puts("host-service native mock: OK");
} return 0; }
