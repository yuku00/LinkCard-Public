#import "WUNative.h"
/* These are independent local host switches, not reward completion or global UI filters. */
static IMP experimentOriginal, readOnlyOriginal;
static BOOL RewardKey(id key) {
    if(![key isKindOfClass:NSString.class]) return NO;
    NSString *s=key;
    return [s isEqual:@"clicfg_miniprogram_open_admb2_in_motivating"] ||
           [s isEqual:@"clicfg_miniprogram_open_admb2_in_motivating_test"];
}
static BOOL Experiment(id x,SEL s,id key,BOOL fallback,IMP original) {
    if(RewardKey(key) && WUNativeEnabled(@"rewardFast")) return YES;
    return ((BOOL(*)(id,SEL,id,BOOL))original)(x,s,key,fallback);
}
static BOOL ExperimentNormal(id x,SEL s,id key,BOOL fallback) { return Experiment(x,s,key,fallback,experimentOriginal); }
static BOOL ExperimentReadOnly(id x,SEL s,id key,BOOL fallback) { return Experiment(x,s,key,fallback,readOnlyOriginal); }
void WUInstallNativeEntries(void) {
    if(!WUNativeGuardAllowsHooks()) return;
    if(!experimentOriginal) WUHook(@"ExptService",@"getExpt:withBoolDef:",NO,@encode(BOOL),@[@"@",@(@encode(BOOL))],(IMP)ExperimentNormal,&experimentOriginal);
    if(!readOnlyOriginal) WUHook(@"ExptService",@"getExptReadOnly:withBoolDef:",NO,@encode(BOOL),@[@"@",@(@encode(BOOL))],(IMP)ExperimentReadOnly,&readOnlyOriginal);

}
BOOL WUNativeEntryAvailable(NSString *key) {
    if([key isEqual:@"rewardFast"]) return experimentOriginal || readOnlyOriginal;
    return NO;
}
