#import "WUNative.h"
#include <string.h>
#include <stdlib.h>
/* No original plugin classes, authentication, update servers or binary addresses. */
static NSArray *Keys(void) { return @[@"hotDisable",@"hotCompat",@"jailbreak",@"clientReport",@"liveEnvironment",@"safeMode",@"keepKeyboard",@"patConfirm",@"gameChoice",@"homeFinder",@"rewardFast"]; }
BOOL WUNativeValidOptions(id value) {
    if(![value isKindOfClass:NSDictionary.class] || [value count]>Keys().count) return NO;
    for(id key in value) {
        id n=value[key];
        if(![Keys() containsObject:key] || ![n isKindOfClass:NSNumber.class] ||
           !([n isEqual:@YES] || [n isEqual:@NO])) return NO;
    }
    return !([value[@"hotDisable"] boolValue] && [value[@"hotCompat"] boolValue]);
}
BOOL WUNativeEnabled(NSString *key) {
    id x=WUValue(@"native");
    return WUNativeGuardAllowsHooks() && WUEnabled(@"enabled") && WUNativeAvailable(key) && WUNativeValidOptions(x) && [x[key] boolValue];
}
BOOL WUNativeSave(NSString *key, BOOL on) {
    if(!NSThread.isMainThread || ![Keys() containsObject:key] || (on && !WUNativeAvailable(key))) return NO;
    id old=WUValue(@"native");
    NSMutableDictionary *next=WUNativeValidOptions(old)?[old mutableCopy]:[NSMutableDictionary dictionary];
    WUNativeHotPolicy p={[next[@"hotDisable"] boolValue],[next[@"hotCompat"] boolValue]};
    if([key isEqual:@"hotDisable"] || [key isEqual:@"hotCompat"]) {
        if(!WUNativeSetHot(&p,[key isEqual:@"hotCompat"],on)) return NO;
        next[@"hotDisable"]=@(p.disable); next[@"hotCompat"]=@(p.compat);
    } else next[key]=@(on);
    return WUSave(@"native",next); // one durable commit, never two interleaved writes
}
@interface WUNativeHookRecord : NSObject
@property(nonatomic,assign) Class cls;
@property(nonatomic,assign) SEL selector;
@property(nonatomic,assign) IMP replacement;
@property(nonatomic,assign) IMP *originalSlot;
@property(nonatomic,copy) NSString *encoding;
@end
@implementation WUNativeHookRecord
@end
static NSMutableArray<WUNativeHookRecord *> *records;
BOOL WUNativeHasRegisteredHooks(void) { @synchronized(WUNativeHookRecord.class) { return records.count>0; } }
void WUNativeRecordHook(Class cls, SEL selector, IMP replacement, IMP *originalSlot) {
    if(!cls || !selector || !replacement || !originalSlot || !*originalSlot || *originalSlot==replacement) return;
    Method m=class_getInstanceMethod(cls,selector);
    if(!m || method_getImplementation(m)!=replacement) return;
    @synchronized(WUNativeHookRecord.class) {
        if(!records) records=[NSMutableArray array];
        for(WUNativeHookRecord *r in records) if(r.cls==cls && r.selector==selector) return;
        WUNativeHookRecord *r=[WUNativeHookRecord new]; r.cls=cls; r.selector=selector;
        r.replacement=replacement; r.originalSlot=originalSlot; r.encoding=@(method_getTypeEncoding(m)); [records addObject:r];
    }
}
BOOL WUNativeRebaseOwnedHook(Class cls,SEL selector,IMP expectedOriginal,IMP verifiedHost) {
    // Primitive for a future verified loader adapter, NOT an automatic swizzle repair.
    // Caller must prove this is a new host body, not a third-party trampoline calling us.
    if(!NSThread.isMainThread || !verifiedHost || !expectedOriginal) return NO;
    @synchronized(WUNativeHookRecord.class) {
        for(WUNativeHookRecord *other in records) if(other.replacement==verifiedHost) return NO;
        for(WUNativeHookRecord *r in records) if(r.cls==cls && r.selector==selector) {
            Method m=class_getInstanceMethod(cls,selector);
            if(!m || method_getImplementation(m)!=r.replacement || !r.originalSlot ||
               *r.originalSlot!=expectedOriginal || strcmp(method_getTypeEncoding(m),r.encoding.UTF8String)) return NO;
            *r.originalSlot=verifiedHost; // keep plugin method, forward to the NEW host body
            return YES;
        }
    }
    return NO;
}
static IMP hotOriginal, oldHotOriginal, jailOriginal, jailInstanceOriginal, safeOriginal;
static BOOL SafeMode(id x,SEL s) {
    return WUNativeSafeModeArmed() && WUNativeEnabled(@"safeMode")?NO:((BOOL(*)(id,SEL))safeOriginal)(x,s);
}
static IMP rootOriginal, pathOriginal, checkOriginal, reportOriginal, vpnOriginal, callOriginal, screenOriginal;
static BOOL hotReady, jailReady, clientReady, liveReady;
static void Hot(id self, SEL cmd, IMP original) {
    if(WUNativeEnabled(@"hotDisable")) return;
    // No verified patch-write provenance: do not overwrite methods changed by the loader.
    ((void(*)(id,SEL))original)(self,cmd);
}
static void HotNew(id x, SEL s) { Hot(x,s,hotOriginal); }
static BOOL HotOld(id x, SEL s) {
    if(WUNativeEnabled(@"hotDisable")) return NO;
    return ((BOOL(*)(id,SEL))oldHotOriginal)(x,s);
}
#define BOOL_GATE(NAME,ORIG,KEY) static BOOL NAME(id x,SEL s) { return WUNativeEnabled(@KEY)?NO:((BOOL(*)(id,SEL))ORIG)(x,s); }
BOOL_GATE(Jail,jailOriginal,"jailbreak")
BOOL_GATE(JailInstance,jailInstanceOriginal,"jailbreak")
BOOL_GATE(VPN,vpnOriginal,"liveEnvironment")
BOOL_GATE(Call,callOriginal,"liveEnvironment")
BOOL_GATE(Screen,screenOriginal,"liveEnvironment")
static id Root(id x,SEL s) { return WUNativeEnabled(@"jailbreak")?nil:((id(*)(id,SEL))rootOriginal)(x,s); }
static id Path(id x,SEL s) { return WUNativeEnabled(@"jailbreak")?nil:((id(*)(id,SEL))pathOriginal)(x,s); }
static void Check(id x,SEL s) { if(!WUNativeEnabled(@"clientReport")) ((void(*)(id,SEL))checkOriginal)(x,s); }
static void Report(id x,SEL s) { if(!WUNativeEnabled(@"clientReport")) ((void(*)(id,SEL))reportOriginal)(x,s); }
static BOOL Hook(NSString *c,NSString *s,BOOL meta,const char *ret,IMP replacement,IMP *original) {
    if(*original) return YES;
    BOOL ok=WUHook(c,s,meta,ret,@[],replacement,original);
    return ok && *original; // WUHook's existing-registration fast path must not imply ownership
}
void WUInstallNative(void) {
    if(!WUNativeGuardAllowsHooks()) return;
    BOOL a=Hook(@"MicroMessengerAppDelegate",@"loadUpdateAndExcute",NO,"v",(IMP)HotNew,&hotOriginal);
    BOOL b=Hook(@"WCUpdateMgr",@"loadMainUpdateBundle",NO,@encode(BOOL),(IMP)HotOld,&oldHotOriginal);
    hotReady=a||b;
    a=Hook(@"JailBreakHelper",@"JailBroken",YES,@encode(BOOL),(IMP)Jail,&jailOriginal);
    b=Hook(@"JailBreakHelper",@"IsJailBreak",NO,@encode(BOOL),(IMP)JailInstance,&jailInstanceOriginal);
    jailReady=a||b;
    Hook(@"JailBreakHelper",@"getJailbreakRootDir",YES,"@",(IMP)Root,&rootOriginal);
    Hook(@"JailBreakHelper",@"getJailbreakPath",YES,"@",(IMP)Path,&pathOriginal);
    a=Hook(@"MMClientCacheManager",@"checkConfig",NO,"v",(IMP)Check,&checkOriginal);
    b=Hook(@"MMClientCacheManager",@"doDReport",NO,"v",(IMP)Report,&reportOriginal);
    clientReady=a&&b;
    a=Hook(@"SecDataReportUtil",@"checkVpnConnect",YES,@encode(BOOL),(IMP)VPN,&vpnOriginal);
    b=Hook(@"SecDataReportUtil",@"checkVoipCalling",YES,@encode(BOOL),(IMP)Call,&callOriginal);
    BOOL c=Hook(@"SecDataReportUtil",@"checkScreenRecording",YES,@encode(BOOL),(IMP)Screen,&screenOriginal);
    liveReady=a&&b&&c;
    if(WUNativeGuardReady()) Hook(@"MMSafeModeMgr",@"shouldEnterSafeMode",NO,@encode(BOOL),(IMP)SafeMode,&safeOriginal);
}
BOOL WUNativeAvailable(NSString *key) {
    if([key isEqual:@"hotDisable"]) return hotReady;
    if([key isEqual:@"hotCompat"]) return NO; // no verified host-patch writer adapter; generic Restore is unsafe
    if([key isEqual:@"safeMode"]) return safeOriginal && WUNativeGuardReady();
    if([key isEqual:@"gameChoice"]) return WUNativeGameAvailable();
    if([key isEqual:@"jailbreak"]) return jailReady;
    if([key isEqual:@"clientReport"]) return clientReady;
    if([key isEqual:@"liveEnvironment"]) return liveReady;
    return WUNativeInteractionAvailable(key);
}
