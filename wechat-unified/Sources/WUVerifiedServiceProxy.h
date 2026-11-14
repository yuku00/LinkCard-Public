#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <string.h>

// Only the exact selector/ABI pairs observed on the target classes are eligible.
extern BOOL WUMatches(Method method, const char *result, NSArray<NSString *> *arguments);
typedef NS_ENUM(NSUInteger, WUVerifiedServiceMethod) {
    WUVerifiedEmoticonSend, WUVerifiedMessageLocalID,
    WUVerifiedSessionNames, WUVerifiedSessionLookup
};
static inline BOOL WUVerifiedProxyMethod(id service, WUVerifiedServiceMethod method) {
    if(!service) return NO;
    NSString *name=nil, *result=nil; NSArray<NSString *> *args=nil;
    switch(method) {
        case WUVerifiedEmoticonSend: name=@"AddEmoticonMsg:MsgWrap:"; result=@"v"; args=@[@"@",@"@"]; break;
        case WUVerifiedMessageLocalID: name=@"GetMsg:LocalID:"; result=@"@"; args=@[@"@",@"I"]; break;
        case WUVerifiedSessionNames: name=@"GetUserNamesOnSessionList"; result=@"@"; args=@[]; break;
        case WUVerifiedSessionLookup: name=@"GetSessionByUserName:"; result=@"@"; args=@[@"@"]; break;
        default: return NO;
    }
    Class cls=object_getClass(service); BOOL proxy=NO;
    for(Class c=cls; c; c=class_getSuperclass(c)) if(c==objc_getClass("NSProxy")) { proxy=YES; break; }
    SEL sel=NSSelectorFromString(name);
    if(!proxy || class_getInstanceMethod(cls,sel)) return NO;
    NSString *hostName=(method==WUVerifiedEmoticonSend || method==WUVerifiedMessageLocalID)?@"CMessageMgr":@"MMNewSessionMgr";
    Class host=NSClassFromString(hostName);
    if(!host || !WUMatches(class_getInstanceMethod(host,sel),result.UTF8String,args)) return NO;
    @try {
        NSMethodSignature *sig=[service methodSignatureForSelector:sel];
        if(!sig || sig.numberOfArguments!=args.count+2 || strcmp(sig.methodReturnType,result.UTF8String) || strcmp([sig getArgumentTypeAtIndex:0],"@") || strcmp([sig getArgumentTypeAtIndex:1],":")) return NO;
        for(NSUInteger i=0;i<args.count;i++) if(strcmp([sig getArgumentTypeAtIndex:i+2],args[i].UTF8String)) return NO;
        return YES;
    } @catch(NSException *e) { return NO; }
}
