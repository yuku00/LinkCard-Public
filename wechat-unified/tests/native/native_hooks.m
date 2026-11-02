#import "TestHost.h"
static IMP fixtureOriginal;
static unsigned loads,hostCalls,pluginCalls,checks,reports;
static BOOL rawPatch,throwPatch,nested,patchResult=YES;
@interface Fixture : NSObject - (int)value; @end
@implementation Fixture - (int)value { hostCalls++; return 1; } @end
static int Ours(id x,SEL s) { pluginCalls++; return 10+((int(*)(id,SEL))fixtureOriginal)(x,s); }
static int Patch(id x,SEL s) { hostCalls++; return 9; }
static int Patch2(id x,SEL s) { hostCalls++; return 12; }
static int Foreign(id x,SEL s) { return 77; }
@interface MicroMessengerAppDelegate : NSObject - (void)loadUpdateAndExcute; @end
@interface WCUpdateMgr : NSObject - (BOOL)loadMainUpdateBundle; @end
static void PerformPatch(void) {
    loads++;
    if(rawPatch) method_setImplementation(class_getInstanceMethod(Fixture.class,@selector(value)),(IMP)Patch);
    else {
        IMP next=fixtureOriginal==(IMP)Patch?(IMP)Patch2:(IMP)Patch;
        WUNativeRebaseOwnedHook(Fixture.class,@selector(value),fixtureOriginal,next);
    }
    if(nested) { nested=NO; [[WCUpdateMgr new] loadMainUpdateBundle]; }
    if(throwPatch) @throw [NSException exceptionWithName:@"synthetic" reason:nil userInfo:nil];
}
@implementation MicroMessengerAppDelegate - (void)loadUpdateAndExcute { PerformPatch(); } @end
@implementation WCUpdateMgr - (BOOL)loadMainUpdateBundle { PerformPatch(); return patchResult; } @end
@interface JailBreakHelper : NSObject
+ (BOOL)JailBroken; + (id)getJailbreakRootDir; + (id)getJailbreakPath; - (BOOL)IsJailBreak;
@end
@implementation JailBreakHelper
+ (BOOL)JailBroken { return YES; } - (BOOL)IsJailBreak { return YES; }
+ (id)getJailbreakRootDir { return @"fixture-root"; } + (id)getJailbreakPath { return @"fixture-path"; }
@end
@interface MMClientCacheManager : NSObject - (void)checkConfig; - (void)doDReport; @end
@implementation MMClientCacheManager
- (void)checkConfig { checks++; } - (void)doDReport { reports++; }
@end
@interface SecDataReportUtil : NSObject + (BOOL)checkVpnConnect; + (BOOL)checkVoipCalling; @end
@implementation SecDataReportUtil
+ (BOOL)checkVpnConnect { return YES; } + (BOOL)checkVoipCalling { return YES; }
@end
static BOOL Screen(id x,SEL s) { return YES; }
int main(void) { @autoreleasepool {
    TestInit(); WUInstallNative();
    assert(!WUNativeValidOptions(@[]) && !WUNativeValidOptions(@{@"wrong":@YES}));
    assert(!WUNativeValidOptions(@{@"jailbreak":@2}));
    assert(!WUNativeValidOptions(@{@"hotDisable":@YES,@"hotCompat":@YES}));
    assert(!WUNativeSave(@"safeMode",YES) && !WUNativeSave(@"homeFinder",YES) && !WUNativeSave(@"rewardFast",YES));
    TestConfig(@{@"liveEnvironment":@YES}); assert(!WUNativeAvailable(@"liveEnvironment") && [SecDataReportUtil checkVpnConnect]);
    SEL screen=NSSelectorFromString(@"checkScreenRecording");
    assert(class_addMethod(object_getClass(SecDataReportUtil.class),screen,(IMP)Screen,[[NSString stringWithFormat:@"%s@:",@encode(BOOL)] UTF8String]));
    WUInstallNative(); assert(WUNativeAvailable(@"liveEnvironment") && ![SecDataReportUtil checkVpnConnect]);
    assert(WUNativeSave(@"jailbreak",YES)); assert(![JailBreakHelper JailBroken] && ![[JailBreakHelper new] IsJailBreak]);
    assert(WUNativeSave(@"clientReport",YES)); MMClientCacheManager *mgr=[MMClientCacheManager new]; [mgr checkConfig]; [mgr doDReport]; assert(!checks && !reports);
    testMaster=NO; [mgr checkConfig]; [mgr doDReport]; assert(checks==1 && reports==1 && [JailBreakHelper JailBroken]); testMaster=YES;
    assert(!WUNativeSave(@"hotCompat",YES) && !WUNativeSave(@"hotDisable",YES));
    TestConfig(@{@"hotDisable":@YES});
    MicroMessengerAppDelegate *app=[MicroMessengerAppDelegate new]; WCUpdateMgr *update=[WCUpdateMgr new];
    [app loadUpdateAndExcute]; assert(loads==1 && [update loadMainUpdateBundle] && loads==2);
    assert(!WUNativeAvailable(@"hotDisable") && !WUNativeAvailable(@"hotCompat"));
    TestConfig(@{});
    assert(WUHook(@"Fixture",@"value",NO,"i",@[],(IMP)Ours,&fixtureOriginal));
    assert([[Fixture new] value]==11 && hostCalls==1 && pluginCalls==1);
    // Explicit verified-host primitive: actual original slot updates and new host executes.
    [app loadUpdateAndExcute]; assert([[Fixture new] value]==19 && hostCalls==2 && pluginCalls==2);
    patchResult=NO; assert(![update loadMainUpdateBundle] && [[Fixture new] value]==22); patchResult=YES;
    nested=YES; [app loadUpdateAndExcute]; assert([[Fixture new] value]==22);
    throwPatch=YES; @try { [app loadUpdateAndExcute]; assert(0); } @catch(NSException *e) { assert([e.name isEqual:@"synthetic"]); }
    assert([[Fixture new] value]==19); throwPatch=NO;
    assert(!WUNativeRebaseOwnedHook(Fixture.class,@selector(value),fixtureOriginal,(IMP)Ours));
    assert(!WUNativeRebaseOwnedHook(Fixture.class,@selector(value),(IMP)Patch2,(IMP)Patch));
    Method method=class_getInstanceMethod(Fixture.class,@selector(value));
    method_setImplementation(method,(IMP)Foreign); IMP slot=fixtureOriginal;
    [app loadUpdateAndExcute]; assert([[Fixture new] value]==77 && fixtureOriginal==slot);
    // Real loader changed method IMP without a verified adapter: do NOT steal it back.
    rawPatch=YES; [app loadUpdateAndExcute]; assert([[Fixture new] value]==9 && fixtureOriginal==slot && !WUNativeAvailable(@"hotCompat"));
    assert(!WUNativeRebaseOwnedHook(Fixture.class,@selector(value),slot,(IMP)Patch2));
    puts("PASS real Core registry/original slots, verified-only rebase, nested/throw/BOOL semantics; unsafe generic strong-compat DISABLED");
} return 0; }
