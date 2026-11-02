#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import "WUMiniAds.h"
#include <assert.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

static NSMutableDictionary *hooks;
static atomic_bool banner=true, interstitial=true, master=true;
static atomic_uint reads, originalCalls, setupReads, records;
static _Thread_local void *expectedContext;
static _Thread_local JSValueRef expectedArgument, expectedException;
static _Thread_local BOOL throwOriginal, changeException;
static id opaque, returnToken;
static NSException *nativeException;
static Class waClass, normalClass;
static SEL invokeSelector;
BOOL WUNativeGuardAllowsHooks(void) { return YES; }
void WUNativeRecordHook(Class c,SEL s,IMP imp,IMP *original) {
    assert(c==waClass && s==invokeSelector && imp && *original && imp!=*original); atomic_fetch_add(&records,1);
}
// Exact unmodified production WUMatches/WUHook functions, extracted by run.py.
#include "CoreHook.inc"
BOOL WUEnabled(NSString *key) {
    atomic_fetch_add(&reads,1);
    if(expectedContext) {
        assert((__bridge void *)[JSContext currentContext]==expectedContext);
        NSArray *arguments=[JSContext currentArguments];
        // Native off-check remains in the outer two-argument callback; installed
        // wrapper flag reads are nested zero-argument native BOOL functions.
        assert(arguments.count==0 || arguments.count==2);
        if(arguments.count==0) atomic_fetch_add(&setupReads,1);
        else assert(((JSValue *)arguments[0]).JSValueRef==expectedArgument);
    }
    return atomic_load(&master) && ([key isEqual:@"miniBannerAds"]?atomic_load(&banner):
        ([key isEqual:@"miniInterstitialAds"]?atomic_load(&interstitial):NO));
}
@interface WUPoisonArgument : NSObject @end
@implementation WUPoisonArgument
- (NSString *)description { assert(0 && "opaque argument inspected"); return nil; }
- (id)valueForKey:(NSString *)key { (void)key; assert(0 && "opaque argument KVC"); return nil; }
@end
static id Original(id object,SEL selector,id argument) {
    assert(object && selector==invokeSelector && argument==opaque);
    atomic_fetch_add(&originalCalls,1);
    JSContext *c=[JSContext currentContext];
    assert((__bridge void *)c==expectedContext);
    if(c) {
        assert([JSContext currentArguments].count==2);
        assert(((JSValue *)[JSContext currentArguments][0]).JSValueRef==expectedArgument);
        assert(c.exception.JSValueRef==expectedException);
        if(changeException) c.exception=[JSValue valueWithInt32:42 inContext:c];
    }
    if(throwOriginal) @throw nativeException;
    return returnToken;
}
static id Call(id object) { return ((id(*)(id,SEL,id))objc_msgSend)(object,invokeSelector,opaque); }
static void Bind(JSContext *c,Class type) {
    id object=[type new];
    c[@"waBridge"]=^BOOL {
        JSContext *current=[JSContext currentContext];
        NSArray *arguments=[JSContext currentArguments];
        JSValue *callee=[JSContext currentCallee], *receiver=[JSContext currentThis];
        assert(arguments.count==2);
        void *oldContext=expectedContext; JSValueRef oldArgument=expectedArgument, oldException=expectedException;
        expectedContext=(__bridge void *)current;
        expectedArgument=((JSValue *)arguments[0]).JSValueRef;
        // Prove setup restores pre-existing JSC exception/handler before original.
        JSValue *sentinel=[JSValue valueWithInt32:7 inContext:current];
        current.exception=sentinel; expectedException=sentinel.JSValueRef;
        void (^handler)(JSContext *,JSValue *)=current.exceptionHandler;
        unsigned callCount=atomic_load(&originalCalls);
        BOOL caught=NO; id result=nil;
        @try { result=Call(object); }
        @catch(NSException *exception) {
            assert(throwOriginal && exception==nativeException); caught=YES; result=returnToken;
        }
        assert(caught==throwOriginal);
        assert(atomic_load(&originalCalls)==callCount+1);
        assert(result==returnToken && current==[JSContext currentContext]);
        assert(((JSValue *)[JSContext currentArguments][0]).JSValueRef==expectedArgument);
        assert(((JSValue *)[JSContext currentArguments][1]).JSValueRef==((JSValue *)arguments[1]).JSValueRef);
        assert([JSContext currentCallee].JSValueRef==callee.JSValueRef && [JSContext currentThis].JSValueRef==receiver.JSValueRef);
        assert(current.exceptionHandler==handler);
        assert(changeException ? current.exception.toInt32==42 : current.exception==sentinel);
        current.exception=nil;
        expectedContext=oldContext; expectedArgument=oldArgument; expectedException=oldException;
        return YES;
    };
    c[@"setFlags"]=^(BOOL b,BOOL i) { atomic_store(&banner,b); atomic_store(&interstitial,i); };
    c[@"nativeDiagnostics"]=^unsigned { return WUMiniAdsDiagnostics(); };
}
static void Run(JSContext *c,NSString *source) {
    __block BOOL exception=NO;
    c.exceptionHandler=^(JSContext *context,JSValue *value) {
        (void)context; exception=YES;
        fprintf(stderr,"SYNTHETIC JS failure: %s\n",value.toString.UTF8String);
    };
    [c evaluateScript:source];
    assert(!exception);
}
static void SmallCases(void) {
    JSContext *normal=[JSContext new]; Bind(normal,normalClass);
    unsigned before=atomic_load(&reads);
    Run(normal,@"globalThis.wx={createBannerAd:function(){},createInterstitialAd:function(){}};var f=wx.createBannerAd;waBridge(1,{});if(f!==wx.createBannerAd||Object.hasOwn(globalThis,'__wuMiniAds_current_v1__'))throw Error('normal installed');");
    assert(atomic_load(&reads)==before);
    Class subclass=objc_allocateClassPair(waClass,"WUInheritedInvoker",0); objc_registerClassPair(subclass);
    JSContext *child=[JSContext new]; Bind(child,subclass);
    Run(child,@"globalThis.wx={createBannerAd:function(){},createInterstitialAd:function(){}};waBridge(1,{});if(Object.hasOwn(globalThis,'__wuMiniAds_current_v1__'))throw Error('subclass installed');");
    assert(atomic_load(&reads)==before);
    JSContext *readonly=[JSContext new]; Bind(readonly,waClass);
    Run(readonly,@"globalThis.wx=Object.freeze({createBannerAd:function(){},createInterstitialAd:function(){}});var f=wx.createBannerAd;waBridge(1,{});if(f!==wx.createBannerAd)throw Error('readonly factory');");
    JSContext *missing=[JSContext new]; Bind(missing,waClass);
    Run(missing,@"waBridge(2,{});if(Object.hasOwn(globalThis,'__wuMiniAds_current_v1__'))throw Error('wx missing');");
    // Setup exception uses local C-API exception out parameter, not the original handler.
    JSContext *bad=[JSContext new]; Bind(bad,waClass);
    Run(bad,@"globalThis.wx=new Proxy({}, {getOwnPropertyDescriptor(){throw Error('synthetic setup');}});waBridge(3,{});");
    assert(WUMiniAdsDiagnostics()&32);
    JSContext *originalException=[JSContext new]; Bind(originalException,waClass);
    changeException=YES; Run(originalException,@"waBridge(4,{});"); changeException=NO;
    throwOriginal=YES; Run(originalException,@"waBridge(4,{});"); throwOriginal=NO;
    // Master switch off does not even create the realm marker.
    atomic_store(&master,false);
    JSContext *off=[JSContext new]; Bind(off,waClass);
    Run(off,@"globalThis.wx={createBannerAd:function(){},createInterstitialAd:function(){}};waBridge(5,{});if(Object.hasOwn(globalThis,'__wuMiniAds_current_v1__'))throw Error('master off');");
    atomic_store(&master,true);
}
static void Full(NSString *fixture,BOOL worker) { @autoreleasepool {
    assert(NSThread.isMainThread != worker);
    JSContext *context=[[JSContext alloc] initWithVirtualMachine:[JSVirtualMachine new]];
    Bind(context,waClass);
    __block BOOL done=NO, success=NO;
    context[@"finish"]=^(BOOL ok) {
        assert(NSThread.isMainThread != worker);
        assert([JSContext currentContext]); done=YES; success=ok;
    };
    context[@"reportSyntheticFailure"]=^(NSString *message) { fprintf(stderr,"SYNTHETIC: %s\n",message.UTF8String); };
    Run(context,fixture);
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
    while(!done && deadline.timeIntervalSinceNow>0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(done && success && atomic_load(&setupReads)>0);
} }
int main(int argc,const char **argv) { @autoreleasepool {
    assert(argc==3);
    NSString *mode=@(argv[1]);
    hooks=[NSMutableDictionary dictionary]; opaque=[WUPoisonArgument new]; returnToken=[NSObject new];
    nativeException=[NSException exceptionWithName:@"SyntheticOriginal" reason:@"synthetic" userInfo:nil];
    invokeSelector=sel_registerName("invokeInJsContext:");
    normalClass=objc_allocateClassPair(NSObject.class,"WCJSInvoker",0);
    assert(class_addMethod(normalClass,invokeSelector,(IMP)Original,"@@:@")); objc_registerClassPair(normalClass);
    if([mode isEqual:@"missing"]) {
        WUInstallMiniAds(); assert(!WUMiniAdsAvailable(@"miniBannerAds")); puts("miniads missing PASS"); return 0;
    }
    BOOL inherited=[mode isEqual:@"inherited"];
    waClass=objc_allocateClassPair(inherited?normalClass:NSObject.class,"WAJSInvoker",0);
    const char *encoding=[mode isEqual:@"wrong-return"]?"v@:@":
        ([mode isEqual:@"wrong-argument"]?"@@:q":([mode isEqual:@"wrong-count"]?"@@:@@":"@@:@"));
    if([mode isEqual:@"wrong-self"]) encoding="@#:@";
    if([mode isEqual:@"wrong-command"]) encoding="@@@@";
    if(!inherited) assert(class_addMethod([mode isEqual:@"class-only"]?object_getClass(waClass):waClass,invokeSelector,(IMP)Original,encoding));
    objc_registerClassPair(waClass);
    IMP before=class_getMethodImplementation(waClass,invokeSelector);
    WUInstallMiniAds();
    if(![mode isEqual:@"full"]) {
        assert(!WUMiniAdsAvailable(@"miniBannerAds") && !atomic_load(&records));
        assert(class_getMethodImplementation(waClass,invokeSelector)==before);
        printf("miniads %s PASS\n",argv[1]); return 0;
    }
    assert(WUMiniAdsAvailable(@"miniBannerAds") && WUMiniAdsAvailable(@"miniInterstitialAds"));
    assert(!WUMiniAdsAvailable(@"rewardFast"));
    IMP installed=class_getMethodImplementation(waClass,invokeSelector); WUInstallMiniAds();
    assert(installed!=before && installed==class_getMethodImplementation(waClass,invokeSelector) && atomic_load(&records)==1);
    assert([JSContext currentContext]==nil);
    unsigned r=atomic_load(&reads), calls=atomic_load(&originalCalls);
    assert(Call([waClass new])==returnToken);
    assert(atomic_load(&reads)==r && atomic_load(&originalCalls)==calls+1);
    id savedOpaque=opaque, savedReturn=returnToken;
    opaque=nil; returnToken=nil; assert(Call([waClass new])==nil);
    opaque=savedOpaque; returnToken=savedReturn;
    throwOriginal=YES;
    @try { (void)Call([waClass new]); assert(0 && "original exception swallowed"); }
    @catch(NSException *exception) { assert(exception==nativeException); }
    throwOriginal=NO;
    SmallCases();
    NSString *fixture=[NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:NULL]; assert(fixture);
    Full(fixture,NO);
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ Full(fixture,YES); dispatch_semaphore_signal(done); });
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC))==0);
    puts("miniads full PASS: production bridge/currentContext/arguments/worker VM/Promise/errors/rollback");
} return 0; }
