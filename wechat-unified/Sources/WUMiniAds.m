#import "WU.h"
#import "WUMiniAds.h"
#import <JavaScriptCore/JavaScriptCore.h>
#include <stdatomic.h>
#include <string.h>
#include <stdlib.h>

static IMP invokeOriginal;
static Class invokerClass;
static atomic_bool ready;
static atomic_uint diagnostics;
static _Thread_local BOOL installing;
static const char setupSource[] =
#include "WUMiniAdsScript.inc"
;

unsigned WUMiniAdsDiagnostics(void) { return atomic_load(&diagnostics); }
BOOL WUMiniAdsAvailable(NSString *key) {
    return atomic_load(&ready) &&
        ([key isEqual:@"miniBannerAds"] || [key isEqual:@"miniInterstitialAds"]);
}
NSString *WUMiniAdsStatus(void) {
    unsigned d=WUMiniAdsDiagnostics();
    return [NSString stringWithFormat:@"仅当前WA→JSC realm；接口仍需逐对象核验。%@%@%@",
        d&4 ? @" 已遇到不支持的广告对象；该对象原路。" : @"",
        d&8 ? @" 已遇到第三方覆盖；不抢回。" : @"",
        d&48 ? @" 已遇到缺接口或安装异常；原路执行。" : @""];
}

static const char probeSource[] =
"(()=>{const d=Object.getOwnPropertyDescriptor;const p=d(globalThis,'__wuMiniAds_current_v1__');"
"if(p){const f=p.value,n=typeof f==='function'&&d(f,'name');return !p.writable&&!p.configurable&&!p.enumerable&&n&&n.value==='WUCurrentMiniAdsV1Heartbeat'?f:8;}"
"const w=d(globalThis,'wx'),x=w&&w.value;if(!x||typeof x!=='object')return 16;"
"for(const k of ['createBannerAd','createInterstitialAd']){const v=d(x,k);if(v&&typeof v.value==='function'&&v.writable)return 0;}return 16;})()";
static JSValueRef Evaluate(JSGlobalContextRef vm,const char *text,JSValueRef *error) {
    JSStringRef source=JSStringCreateWithUTF8CString(text);
    if(!source) return NULL;
    JSValueRef value=JSEvaluateScript(vm,source,NULL,NULL,1,error);
    JSStringRelease(source); return value;
}
// Only this synchronous callback's VM is touched. No native realm cache is retained.
static void SetupCurrent(void) {
    JSContext *context=[JSContext currentContext];
    if(!context || installing) return;
    installing=YES;
    JSValue *savedException=context.exception;
    void (^savedHandler)(JSContext *,JSValue *)=context.exceptionHandler;
    BOOL touched=NO;
    @try {
        // Off means no JS work; old wrappers read these same native flags on their next call.
        if(!WUEnabled(@"miniBannerAds") && !WUEnabled(@"miniInterstitialAds")) return;
        touched=YES;
        context.exceptionHandler=^(JSContext *c,JSValue *e) { (void)c; (void)e; };
        JSGlobalContextRef vm=context.JSGlobalContextRef;
        JSValueRef error=NULL, result=Evaluate(vm,probeSource,&error);
        if(!error && result && JSValueIsNumber(vm,result)) {
            double code=JSValueToNumber(vm,result,&error);
            if(!error && code==0) {
                // Allocate native BOOL functions only for first installation in this realm.
                JSValue *banner=[JSValue valueWithObject:^BOOL { return WUEnabled(@"miniBannerAds"); } inContext:context];
                JSValue *interstitial=[JSValue valueWithObject:^BOOL { return WUEnabled(@"miniInterstitialAds"); } inContext:context];
                result=banner && interstitial?Evaluate(vm,setupSource,&error):NULL;
                if(!error && result && JSValueIsObject(vm,result)) {
                    JSObjectRef setup=JSValueToObject(vm,result,&error);
                    JSValueRef args[]={banner.JSValueRef,interstitial.JSValueRef};
                    result=!error && JSObjectIsFunction(vm,setup)?JSObjectCallAsFunction(vm,setup,NULL,2,args,&error):NULL;
                }
            }
        } else if(!error && result && JSValueIsObject(vm,result)) {
            JSObjectRef heartbeat=JSValueToObject(vm,result,&error);
            result=!error && JSObjectIsFunction(vm,heartbeat)?JSObjectCallAsFunction(vm,heartbeat,NULL,0,NULL,&error):NULL;
        }
        if(error || !result) atomic_fetch_or(&diagnostics,32u);
        else if(JSValueIsNumber(vm,result)) {
            double code=JSValueToNumber(vm,result,&error);
            if(!error && code>=0 && code<=63) atomic_fetch_or(&diagnostics,(unsigned)code);
        }
    } @catch(NSException *exception) {
        (void)exception; atomic_fetch_or(&diagnostics,32u);
    } @finally {
        if(touched) { context.exception=savedException; context.exceptionHandler=savedHandler; }
        installing=NO;
    }
}
static id Invoke(id object,SEL selector,id opaqueArgument) {
    if(object_getClass(object)==invokerClass) SetupCurrent();
    // No argument probing, nil substitution, original exception catch or return conversion.
    return ((id(*)(id,SEL,id))invokeOriginal)(object,selector,opaqueArgument);
}
void WUInstallMiniAds(void) {
    if(atomic_load(&ready)) return;
    Class c=NSClassFromString(@"WAJSInvoker");
    SEL s=NSSelectorFromString(@"invokeInJsContext:");
    unsigned count=0; Method *methods=c?class_copyMethodList(c,&count):NULL;
    Method own=NULL;
    for(unsigned i=0;i<count;i++) if(method_getName(methods[i])==s) { own=methods[i]; break; }
    BOOL matches=own && method_getNumberOfArguments(own)==3;
    // WUHook below performs the exact object return/object argument check.
    if(matches) {
        char *selfType=method_copyArgumentType(own,0), *cmdType=method_copyArgumentType(own,1);
        matches=selfType && cmdType && !strcmp(selfType,"@") && !strcmp(cmdType,":");
        free(selfType); free(cmdType);
    }
    free(methods);
    if(!matches) return; // No inherited WCJSInvoker or guessed ABI.
    invokerClass=c;
    atomic_store(&ready,WUHook(@"WAJSInvoker",@"invokeInJsContext:",NO,"@",@[@"@"],(IMP)Invoke,&invokeOriginal) && invokeOriginal!=NULL);
}
