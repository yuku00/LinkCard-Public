#import "WUHostService.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "WUDiagnostics.h"

extern BOOL WUMatches(Method method, const char *result, NSArray<NSString *> *arguments);

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
id WUHostService(NSString *name) {
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
        if(!provider && context) {
            if(!Has(context,@"currentContext","@",@[])) REPORT(WUDiagCurrentSignature);
            else if(!(provider=Object(context,@"currentContext"))) REPORT(WUDiagCurrentMissing);
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
        if(!Has(provider,@"getService:","@",@[@"#"]) && !Has(provider,@"getService:","@",@[@"@"])) { REPORT(WUDiagLegacyServiceSignature); return nil; }
        id result=FromProvider(provider,service);
        if(!result) REPORT(WUDiagLegacyServiceMissing);
        return result;
    } @catch(NSException *exception) { REPORT(WUDiagHostServiceException); return nil; }
#undef REPORT
}
