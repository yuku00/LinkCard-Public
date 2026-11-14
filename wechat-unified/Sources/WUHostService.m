#import "WUHostService.h"
#import <objc/runtime.h>
#import <objc/message.h>

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
    @try {
        Class service=NSClassFromString(name);
        if(!service) return nil;
        Class context=NSClassFromString(@"MMContext");
        // AFN 0x23cd0–0x23da4 / 0x2f3cc–0x2f51c: active/current context then getService:.
        id provider=Object(context,@"activeUserContext");
        if(!provider) provider=Object(context,@"currentContext");
        // A present context is authoritative: never cross into a potentially stale legacy account.
        if(provider) return FromProvider(provider,service);
        return FromProvider(Object(NSClassFromString(@"MMServiceCenter"),@"defaultCenter"),service);
    } @catch(NSException *exception) { return nil; }
}
