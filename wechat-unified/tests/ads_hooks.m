#import "WU.h"
#include <assert.h>
#include <string.h>
#include <stdlib.h>
static BOOL enabled=YES, moments=YES, splash=YES, flow=NO, card=NO;
static NSUInteger recoOriginalCalls;
static NSUInteger originalCalls, eventCalls;
BOOL WUEnabled(NSString *key) { return enabled && ([key isEqual:@"momentsAds"]?moments:([key isEqual:@"miniSplashAds"]?splash:([key isEqual:@"officialRecoFlow"]?flow:([key isEqual:@"officialRecCard"]?card:NO)))); }
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
@interface BrandTLExptConfig : NSObject @end
@implementation BrandTLExptConfig @end
static BOOL OriginalReco(id self,SEL cmd) { recoOriginalCalls++; return NO; }
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
int main(int argc, const char **argv) { @autoreleasepool {
    if(argc>1 && strcmp(argv[1],"wrong-reco")==0) {
        SEL rf=NSSelectorFromString(@"isExptNotShowRecoFlow"), rc=NSSelectorFromString(@"isExptNotShowRecCard");
        NSString *type=[NSString stringWithFormat:@"%s@:",@encode(BOOL)];
        assert(class_addMethod(BrandTLExptConfig.class,rf,(IMP)OriginalReco,type.UTF8String));
        assert(class_addMethod(BrandTLExptConfig.class,rc,(IMP)Wrong,"v@:"));
        WUInstallAds();
        assert(WUAdsAvailable(@"officialRecoFlow") && !WUAdsAvailable(@"officialRecCard"));
        assert(method_getImplementation(class_getInstanceMethod(BrandTLExptConfig.class,rc))==(IMP)Wrong);
        flow=YES; assert(((BOOL(*)(id,SEL))objc_msgSend)([BrandTLExptConfig new],rf));
        puts("Ads hooks: wrong recommendation ABI rejected independently"); return 0;
    }
    WCAdvertiseDataHelper *helper=[WCAdvertiseDataHelper new];
    WAAppTaskSplashADConfig *config=[WAAppTaskSplashADConfig new];
    id item=[WCDataItem new], ad=[NSObject new];
    WUInstallAds();
    assert(!WUAdsAvailable(@"officialRecoFlow") && !WUAdsAvailable(@"officialRecCard"));
    SEL rf=NSSelectorFromString(@"isExptNotShowRecoFlow"), rc=NSSelectorFromString(@"isExptNotShowRecCard");
    NSString *boolType=[NSString stringWithFormat:@"%s@:",@encode(BOOL)];
    assert(class_addMethod(BrandTLExptConfig.class,rf,(IMP)OriginalReco,boolType.UTF8String));
    assert(class_addMethod(BrandTLExptConfig.class,rc,(IMP)OriginalReco,boolType.UTF8String));
    WUInstallAds();
    assert(WUAdsAvailable(@"officialRecoFlow") && WUAdsAvailable(@"officialRecCard"));
    id brand=[BrandTLExptConfig new];
    BOOL (*call)(id,SEL)=(BOOL(*)(id,SEL))objc_msgSend;
    assert(!call(brand,rf) && !call(brand,rc) && recoOriginalCalls==2);
    flow=YES; assert(call(brand,rf) && !call(brand,rc));
    flow=NO; card=YES; assert(!call(brand,rf) && call(brand,rc));
    flow=YES; assert(call(brand,rf) && call(brand,rc));
    enabled=NO; assert(!call(brand,rf) && !call(brand,rc)); enabled=YES;
    flow=NO; card=NO; assert(!call(brand,rf) && !call(brand,rc));
    assert(recoOriginalCalls==8);
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

void WUCaptureObserve(id object, unsigned point) { (void)object; (void)point; }
