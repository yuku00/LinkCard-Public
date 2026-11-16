#import "WUHostService.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#import "WUDiagnostics.h"

extern BOOL WUMatches(Method method, const char *result, NSArray<NSString *> *arguments);

static const char *UnqualifiedType(const char *type) {
    if(!type) return "";
    while(*type && strchr("rnNoORV",*type)) type++;
    return type;
}
BOOL WUAccountServiceHasSelfContact(id service) {
    if(!service) return NO;
    SEL selector=sel_registerName("getSelfContact");
    Method method=class_getInstanceMethod(object_getClass(service),selector);
    if(method) return WUMatches(method,"@",@[]);
    // Do not broaden forwarding to ordinary objects or to unverified selectors.
    BOOL proxy=NO;
    for(Class c=object_getClass(service); c; c=class_getSuperclass(c)) {
        if(c==objc_getClass("NSProxy")) { proxy=YES; break; }
    }
    if(!proxy) return NO;
    @try {
        NSMethodSignature *signature=[service methodSignatureForSelector:selector];
        return signature && signature.numberOfArguments==2 &&
            strcmp(UnqualifiedType(signature.methodReturnType),"@")==0 &&
            strcmp(UnqualifiedType([signature getArgumentTypeAtIndex:0]),"@")==0 &&
            strcmp(UnqualifiedType([signature getArgumentTypeAtIndex:1]),":")==0;
    } @catch(NSException *exception) { return NO; }
}
static BOOL Has(id target, NSString *name, const char *result, NSArray *arguments) {
    return target && WUMatches(class_getInstanceMethod(object_getClass(target), NSSelectorFromString(name)), result, arguments);
}
static id Object(id target, NSString *name) {
    if(!Has(target, name, "@", @[])) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, NSSelectorFromString(name));
}
static id FromProvider(id provider, Class service) {
    if(!Has(provider, @"getService:", "@", @[@"#"]) && !Has(provider, @"getService:", "@", @[@"@"])) return nil;
    return ((id (*)(id, SEL, Class))objc_msgSend)(provider, NSSelectorFromString(@"getService:"), service);
}
id WUHostService(NSString *name) { return WUHostServiceWithPath(name, NULL); }
id WUHostServiceWithPath(NSString *name, WUProviderPath *path) {
    if(path) *path=WUProviderUnknown;
    BOOL account=[name isEqualToString:@"CContactMgr"];
#define REPORT(e) do { if(account) WURecordAccountDiagnosticEvent(e); } while(0)
    @try {
        Class service=NSClassFromString(name);
        if(!service) return nil;
        Class context=NSClassFromString(@"MMContext");
        if(!context) REPORT(WUDiagContextClassMissing);
        id provider=nil;
        if(context && !Has(context,@"activeUserContext","@",@[])) REPORT(WUDiagActiveSignature);
        else if(context && !(provider=Object(context,@"activeUserContext"))) REPORT(WUDiagActiveMissing);
        if(provider && path) *path=WUProviderActive;
        if(!provider && context) {
            if(!Has(context,@"currentContext","@",@[])) REPORT(WUDiagCurrentSignature);
            else if(!(provider=Object(context,@"currentContext"))) REPORT(WUDiagCurrentMissing);
            if(provider && path) *path=WUProviderCurrent;
        }
        if(provider) {
            if(!Has(provider,@"getService:","@",@[@"#"]) && !Has(provider,@"getService:","@",@[@"@"])) { REPORT(WUDiagContextServiceSignature); return nil; }
            id result=FromProvider(provider,service);
            if(!result) REPORT(WUDiagContextServiceMissing);
            return result; // never cross into a potentially stale legacy account
        }
        Class legacy=NSClassFromString(@"MMServiceCenter");
        if(!legacy) { REPORT(WUDiagLegacyClassMissing); return nil; }
        if(!Has(legacy,@"defaultCenter","@",@[])) { REPORT(WUDiagLegacySignature); return nil; }
        provider=Object(legacy,@"defaultCenter");
        if(!provider) { REPORT(WUDiagLegacyMissing); return nil; }
        if(path) *path=WUProviderLegacy;
        if(!Has(provider,@"getService:","@",@[@"#"]) && !Has(provider,@"getService:","@",@[@"@"])) { REPORT(WUDiagLegacyServiceSignature); return nil; }
        id result=FromProvider(provider,service);
        if(!result) REPORT(WUDiagLegacyServiceMissing);
        return result;
    } @catch(NSException *exception) { REPORT(WUDiagHostServiceException); return nil; }
#undef REPORT
}

@interface WUHostDiagnosticLock : NSObject @end
@implementation WUHostDiagnosticLock @end
static NSString *WUAccountServiceSnapshot;

void WURecordAccountServiceMismatch(id service, WUProviderPath path) {
    if(!service) return;
    @try {
        @synchronized(WUHostDiagnosticLock.class) {
            static WUDiagnosticRate rate;
            if(!WUDiagnosticRateAllow(&rate, NSProcessInfo.processInfo.systemUptime)) return;
            Class cls=object_getClass(service), base=objc_getClass("CContactMgr");
            BOOL isContactManager=NO;
            for(Class cursor=cls; cursor; cursor=class_getSuperclass(cursor)) {
                if(cursor==base && base) { isContactManager=YES; break; }
            }
            const char *raw=cls?class_getName(cls):NULL;
            NSString *className=(raw && strnlen(raw,97)<=96)?[NSString stringWithUTF8String:raw]:nil;
            NSCharacterSet *badName=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.$"] invertedSet];
            if(!className.length || className.length>96 || [className rangeOfCharacterFromSet:badName].location!=NSNotFound) className=@"不可用或超限";
            Method method=cls?class_getInstanceMethod(cls,sel_registerName("getSelfContact")):NULL;
            const char *encoding=method?method_getTypeEncoding(method):NULL;
            NSString *type=(encoding && strnlen(encoding,97)<=96)?[NSString stringWithUTF8String:encoding]:nil;
            // Named or complex encodings can contain arbitrary strings; do not export them.
            NSCharacterSet *badType=[[NSCharacterSet characterSetWithCharactersInString:@"vBcCsSiIlLqQfdD@#:^*?0123456789+-rnoORV"] invertedSet];
            if(!type.length || type.length>96 || [type rangeOfCharacterFromSet:badType].location!=NSNotFound) type=method?@"不可用、复杂或超限":@"无";
            NSString *provider=@"未知";
            if(path==WUProviderActive) provider=@"activeUserContext";
            else if(path==WUProviderCurrent) provider=@"currentContext";
            else if(path==WUProviderLegacy) provider=@"defaultCenter";
            WUAccountServiceSnapshot=[NSString stringWithFormat:@"账号服务接收类：%@；CContactMgr或子类：%@；getSelfContact：%@；类型编码：%@；provider：%@",className,isContactManager?@"是":@"否",method?@"存在":@"不存在",type,provider];
        }
    } @catch(NSException *exception) { }
}
NSString *WUAccountServiceDiagnosticSnapshot(void) {
    @synchronized(WUHostDiagnosticLock.class) { return WUAccountServiceSnapshot; }
}
