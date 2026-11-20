#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <string.h>

// Never trusts a proxy alone: a real CMessageMgr Method and the forwarded
// signature must both agree. Compare canonical argument encodings, not offsets.
static inline BOOL WUMessageServiceMatches(Method method, NSString *result, NSArray<NSString *> *arguments) {
    if (!method || method_getNumberOfArguments(method)!=arguments.count+2) return NO;
    NSMethodSignature *s=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (!s || strcmp(s.methodReturnType,result.UTF8String) || strcmp([s getArgumentTypeAtIndex:0],"@") || strcmp([s getArgumentTypeAtIndex:1],":")) return NO;
    for (NSUInteger i=0;i<arguments.count;i++) if (strcmp([s getArgumentTypeAtIndex:i+2],arguments[i].UTF8String)) return NO;
    return YES;
}

typedef NS_ENUM(NSUInteger, WUMessageServiceOperation) {
    WUMessageServiceRevokeLong, WUMessageServiceRevokeShort,
    WUMessageServiceStatsPage, WUMessageServiceStatsAppPage
};

static inline NSString *WUMessageServiceEncoding(id service, WUMessageServiceOperation op) {
    if (!service) return nil;
    NSString *name; NSArray *prefix; NSUInteger integerCount; BOOL page=NO;
    switch (op) {
        case WUMessageServiceRevokeLong: name=@"RevokeMsg:MsgWrap:Counter:revokeTicket:viewController:"; prefix=@[@"@",@"@"]; integerCount=1; break;
        case WUMessageServiceRevokeShort: name=@"RevokeMsg:MsgWrap:Counter:"; prefix=@[@"@",@"@"]; integerCount=1; break;
        case WUMessageServiceStatsPage: name=@"GetMsgByCreateTime:FromID:FromCreateTime:Limit:LeftCount:"; prefix=@[@"@"]; integerCount=3; page=YES; break;
        case WUMessageServiceStatsAppPage: name=@"GetAppMsgList:FromID:CreateTime:Limit:"; prefix=@[@"@"]; integerCount=3; break;
        default: return nil;
    }
    @try {
        Class host=NSClassFromString(@"CMessageMgr"), cls=object_getClass(service);
        if (!cls) return nil;
        BOOL proxy=NO, instance=NO;
        for (Class c=cls;c;c=class_getSuperclass(c)) {
            if (c==objc_getClass("NSProxy")) proxy=YES;
            if (c==host) instance=YES;
        }
        SEL sel=NSSelectorFromString(name);
        Method real=host?class_getInstanceMethod(host,sel):NULL;
        BOOL revoke=op==WUMessageServiceRevokeLong || op==WUMessageServiceRevokeShort;
        // A concrete revoke service retains the original ABI-checked path.
        if ((proxy && (!real || class_getInstanceMethod(cls,sel))) || (!proxy && !instance && !revoke)) return nil;
        Method method=proxy?real:class_getInstanceMethod(cls,sel);
        if (!method) return nil;
        NSMethodSignature *s=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (!s || s.numberOfArguments!=2+prefix.count+integerCount+(page?1:0)+(op==WUMessageServiceRevokeLong?2:0)) return nil;
        NSString *ret=[NSString stringWithUTF8String:s.methodReturnType];
        if (!(revoke?([ret isEqual:@"v"] || [ret isEqual:@"@"]):[ret isEqual:@"@"])) return nil;
        NSMutableArray *args=[prefix mutableCopy];
        for (NSUInteger i=0;i<integerCount;i++) {
            const char *t=[s getArgumentTypeAtIndex:2+prefix.count+i];
            if (strlen(t)!=1 || !strchr(page?"iI":"iIqQ",*t)) return nil;
            [args addObject:[NSString stringWithUTF8String:t]];
        }
        if (page) { const char *t=[s getArgumentTypeAtIndex:5+prefix.count]; if (strcmp(t,"^i") && strcmp(t,"^I")) return nil; [args addObject:[NSString stringWithUTF8String:t]]; }
        if (op==WUMessageServiceRevokeLong) [args addObjectsFromArray:@[@"@",@"@"]];
        if (!WUMessageServiceMatches(method,ret,args) || (proxy && !WUMessageServiceMatches(real,ret,args))) return nil;
        if (proxy) {
            NSMethodSignature *forward=[service methodSignatureForSelector:sel];
            if (!forward || forward.numberOfArguments!=s.numberOfArguments || strcmp(forward.methodReturnType,s.methodReturnType)) return nil;
            for (NSUInteger i=0;i<s.numberOfArguments;i++) if (strcmp([forward getArgumentTypeAtIndex:i],[s getArgumentTypeAtIndex:i])) return nil;
        }
        return [NSString stringWithUTF8String:method_getTypeEncoding(method)];
    } @catch (NSException *exception) { return nil; }
}
