#import "WU.h"
#include <assert.h>
#include <string.h>
#include <stdlib.h>
static BOOL enabled=YES, moments=YES, splash=YES;
static NSUInteger originalCalls, eventCalls;
BOOL WUEnabled(NSString *key) { return enabled && ([key isEqual:@"momentsAds"]?moments:([key isEqual:@"miniSplashAds"]?splash:NO)); }
// Fixture hook installer exercises the exact production registrations against real ObjC methods.
BOOL WUHook(NSString *name,NSString *selector,BOOL meta,const char *result,NSArray *args,IMP replacement,IMP *original) {
    Class c=NSClassFromString(name); if(meta && c) c=object_getClass(c);
    Method m=c?class_getInstanceMethod(c,NSSelectorFromString(selector)):NULL;
    if(!m || method_getNumberOfArguments(m)!=args.count+2) return NO;
    char *r=method_copyReturnType(m); BOOL match=strcmp(r,result)==0; free(r);
    for(unsigned i=0;match && i<args.count;i++) { char *a=method_copyArgumentType(m,i+2); match=strcmp(a,[args[i] UTF8String])==0; free(a); }
    if(!match) return NO;
    if(method_getImplementation(m)==replacement) return YES;
    *original=method_setImplementation(m,replacement); return YES;
}
@interface WCDataItem : NSObject @end
@implementation WCDataItem @end
@interface WCAdvertiseDataHelper : NSObject
- (BOOL)IsAdvertiseDataValid:(id)ad dataItem:(id)item;
@end
@implementation WCAdvertiseDataHelper
- (BOOL)IsAdvertiseDataValid:(id)ad dataItem:(id)item { originalCalls++; return YES; }
@end
@interface WAAppTaskSplashADConfig : NSObject
- (BOOL)canShowSplashADWindow;
@end
@implementation WAAppTaskSplashADConfig
- (BOOL)canShowSplashADWindow { originalCalls++; return YES; }
@end
@interface RewardFixture : NSObject
- (BOOL)showRewardAd;
- (void)handleJSEvent:(id)event;
@end
@implementation RewardFixture
- (BOOL)showRewardAd { eventCalls++; return YES; }
- (void)handleJSEvent:(id)event { eventCalls++; }
@end
static BOOL Hot(id self,SEL cmd) { originalCalls++; return YES; }
static void Wrong(id self,SEL cmd) {}
int main(void) { @autoreleasepool {
    WCAdvertiseDataHelper *helper=[WCAdvertiseDataHelper new];
    WAAppTaskSplashADConfig *config=[WAAppTaskSplashADConfig new];
    id item=[WCDataItem new], ad=[NSObject new];
    WUInstallAds();
    assert(WUAdsAvailable(@"momentsAds"));
    assert(!WUAdsAvailable(@"miniSplashAds")); // Missing hot-start gate disables both overrides.
    assert([config canShowSplashADWindow]);
    assert(![helper IsAdvertiseDataValid:ad dataItem:item]);
    assert([helper IsAdvertiseDataValid:ad dataItem:nil]);
    assert([helper IsAdvertiseDataValid:ad dataItem:ad]);
    assert([helper IsAdvertiseDataValid:nil dataItem:item]);
    moments=NO; assert([helper IsAdvertiseDataValid:ad dataItem:item]); moments=YES;
    enabled=NO; assert([helper IsAdvertiseDataValid:ad dataItem:item]); enabled=YES;
    // Wrong return type is rejected without replacing it.
    SEL wrong=NSSelectorFromString(@"wrongGate"); IMP saved=NULL;
    assert(class_addMethod(WAAppTaskSplashADConfig.class,wrong,(IMP)Wrong,"v@:"));
    assert(!WUHook(@"WAAppTaskSplashADConfig",@"wrongGate",NO,@encode(BOOL),@[],(IMP)Hot,&saved));
    assert(saved==NULL);
    SEL hot=NSSelectorFromString(@"canHotStartShowSplashAD");
    assert(class_addMethod(WAAppTaskSplashADConfig.class,hot,(IMP)Hot,[[NSString stringWithFormat:@"%s@:",@encode(BOOL)] UTF8String]));
    WUInstallAds(); assert(WUAdsAvailable(@"miniSplashAds"));
    assert(![config canShowSplashADWindow]);
    assert(!((BOOL(*)(id,SEL))objc_msgSend)(config,hot));
    splash=NO; assert([config canShowSplashADWindow]);
    assert(((BOOL(*)(id,SEL))objc_msgSend)(config,hot)); splash=YES;
    RewardFixture *reward=[RewardFixture new];
    assert([reward showRewardAd]); [reward handleJSEvent:@"user-request"];
    assert(eventCalls==2 && originalCalls==11);
    assert(!WUAdsAvailable(@"unknown"));
    puts("Ads hooks: runtime signature/missing-gate/normal-item/reward/original-path fixtures passed");
} return 0; }
