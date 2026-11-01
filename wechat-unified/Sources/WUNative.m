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
static BOOL startupBoundaryOpen=YES, boundaryRunning;
#if defined(WU_NATIVE_BOUNDARY_TEST)
// Only the self-authored runtime fixture supplies these contracts, never an injected build.
extern BOOL WUNativeTestBoundary(id receiver,SEL selector,IMP loader);
extern BOOL WUNativeTestHost(Class cls,SEL selector,IMP previous,IMP candidate);
#endif
static BOOL VerifiedBoundary(id receiver,SEL selector,IMP loader) {
#if defined(WU_NATIVE_BOUNDARY_TEST)
    return WUNativeTestBoundary(receiver,selector,loader);
#else
    (void)receiver; (void)selector; (void)loader;
    return NO; // No audited host adapter proves synchronous, exclusive writes and no captured/JIT loopback.
#endif
}
static BOOL VerifiedHost(Class cls,SEL selector,IMP previous,IMP candidate) {
#if defined(WU_NATIVE_BOUNDARY_TEST)
    return WUNativeTestHost(cls,selector,previous,candidate);
#else
    (void)cls; (void)selector; (void)previous; (void)candidate; return NO;
#endif
}
@interface WUNativeSuspendedHook : NSObject
@property(nonatomic,strong) WUNativeHookRecord *record;
@property(nonatomic,assign) IMP previous;
@end
@implementation WUNativeSuspendedHook @end
static BOOL PluginReplacement(IMP candidate) {
    for(WUNativeHookRecord *r in records) if(r.replacement==candidate) return YES;
    return NO;
}
static NSArray *SuspendForStartup(id receiver,SEL selector,IMP loader) {
    if(!NSThread.isMainThread || !startupBoundaryOpen || boundaryRunning ||
       !WUNativeEnabled(@"hotCompat") || !VerifiedBoundary(receiver,selector,loader)) return nil;
    NSMutableArray *suspended=[NSMutableArray array];
    @synchronized(WUNativeHookRecord.class) {
        for(WUNativeHookRecord *r in records) {
            Method m=class_getInstanceMethod(r.cls,r.selector); IMP old=r.originalSlot?*r.originalSlot:NULL;
            if(!m || !old || method_getImplementation(m)!=r.replacement ||
               strcmp(method_getTypeEncoding(m),r.encoding.UTF8String) || PluginReplacement(old) ||
               !VerifiedHost(r.cls,r.selector,old,old)) continue;
            WUNativeSuspendedHook *entry=[WUNativeSuspendedHook new]; entry.record=r; entry.previous=old;
            [suspended addObject:entry];
        }
        // Allocate/validate the entire list before the first write; no partial suspension on allocation failure.
        boundaryRunning=YES;
        for(WUNativeSuspendedHook *entry in suspended) {
            WUNativeHookRecord *r=entry.record; Method m=class_getInstanceMethod(r.cls,r.selector);
            // The verified adapter must exclude concurrent writers; ObjC has no compare-and-swap IMP API.
            method_setImplementation(m,entry.previous);
        }
    }
    return suspended;
}
static void ResumeAfterStartup(NSArray *suspended) {
    if(!suspended) return;
    @try { @synchronized(WUNativeHookRecord.class) {
        for(WUNativeSuspendedHook *entry in suspended) {
            WUNativeHookRecord *r=entry.record; Method m=class_getInstanceMethod(r.cls,r.selector);
            if(!m || !r.originalSlot || *r.originalSlot!=entry.previous ||
               strcmp(method_getTypeEncoding(m),r.encoding.UTF8String)) continue;
            IMP actual=method_getImplementation(m);
            if(!actual || PluginReplacement(actual) || !VerifiedHost(r.cls,r.selector,entry.previous,actual)) continue;
            // Rebase BEFORE republishing us. Finish even if config changed mid-loader.
            *r.originalSlot=actual; method_setImplementation(m,r.replacement);
        }
    }} @finally { boundaryRunning=NO; }
}
static void HotNew(id x,SEL s) {
    if(WUNativeEnabled(@"hotDisable") && !(NSThread.isMainThread && boundaryRunning)) return;
    NSArray *suspended=SuspendForStartup(x,s,hotOriginal);
    @try { ((void(*)(id,SEL))hotOriginal)(x,s); }
    @finally { ResumeAfterStartup(suspended); }
}
static BOOL HotOld(id x,SEL s) {
    if(WUNativeEnabled(@"hotDisable") && !(NSThread.isMainThread && boundaryRunning)) return NO;
    NSArray *suspended=SuspendForStartup(x,s,oldHotOriginal);
    @try { return ((BOOL(*)(id,SEL))oldHotOriginal)(x,s); }
    @finally { ResumeAfterStartup(suspended); }
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
    static dispatch_once_t boundaryOnce; dispatch_once(&boundaryOnce, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ startupBoundaryOpen=NO; }];
    });
    UIApplication *application=NSThread.isMainThread?UIApplication.sharedApplication:nil;
    if(application && application.applicationState==UIApplicationStateActive) startupBoundaryOpen=NO;
    WUInstallNativeEntries();
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
    if([key isEqual:@"hotCompat"]) {
#if defined(WU_NATIVE_BOUNDARY_TEST)
        return hotReady;
#else
        return NO; // Evaluated boundary is not an attested adapter for either real host loader.
#endif
    }
    if([key isEqual:@"rewardFast"] || [key isEqual:@"homeFinder"]) return WUNativeEntryAvailable(key);
    if([key isEqual:@"safeMode"]) return safeOriginal && WUNativeGuardReady();
    if([key isEqual:@"gameChoice"]) return WUNativeGameAvailable();
    if([key isEqual:@"jailbreak"]) return jailReady;
    if([key isEqual:@"clientReport"]) return clientReady;
    if([key isEqual:@"liveEnvironment"]) return liveReady;
    return WUNativeInteractionAvailable(key);
}
