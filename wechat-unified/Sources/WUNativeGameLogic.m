#import "WUNative.h"
#include <limits.h>
#include <string.h>
// The 8.0.79 header declares these extension properties @dynamic; they can
// be forwarded by CMessageWrap rather than installed as concrete Methods.
static NSString *GameProperty(NSString *selector) {
    if([selector isEqual:@"m_uiGameType"]) return @"m_uiGameType";
    if([selector isEqual:@"m_uiGameContent"] || [selector isEqual:@"setM_uiGameContent:"]) return @"m_uiGameContent";
    if([selector isEqual:@"setM_nsEmoticonMD5:"]) return @"m_nsEmoticonMD5";
    return nil;
}
BOOL WUNativeGameFieldAvailable(Class cls, NSString *selector, const char *ret, NSArray *args) {
    SEL sel=NSSelectorFromString(selector);
    Method method=cls?class_getInstanceMethod(cls,sel):NULL;
    if(method) return WUMatches(method,ret,args);
    NSString *key=GameProperty(selector);
    if(!key || cls!=NSClassFromString(@"CMessageWrap")) return NO;
    objc_property_t property=class_getProperty(cls,key.UTF8String);
    const char *attrs=property?property_getAttributes(property):NULL;
    if(!attrs || attrs[0]!='T') return NO;
    BOOL object=[key isEqual:@"m_nsEmoticonMD5"];
    if(object ? attrs[1]!='@' : !(attrs[1]=='I' && attrs[2]==',')) return NO;
    if([selector hasPrefix:@"set"]) return !strcmp(ret,"v") && args.count==1 && [args[0] isEqual:(object?@"@":@"I")];
    return !object && !strcmp(ret,"I") && !args.count;
}
static BOOL Has(id x,NSString *s,const char *ret,NSArray *args) {
    if(!x) return NO;
    Class cls=object_getClass(x); SEL sel=NSSelectorFromString(s);
    Method method=class_getInstanceMethod(cls,sel);
    if(method) return WUMatches(method,ret,args);
    BOOL forwardedClassMethod=x==(id)NSClassFromString(@"GameController") &&
        [s isEqual:@"getMD5ByGameContent:"];
    if(!forwardedClassMethod && !WUNativeGameFieldAvailable(cls,s,ret,args)) return NO;
    @try {
        NSMethodSignature *sig=[x methodSignatureForSelector:sel];
        if(!sig || sig.numberOfArguments!=args.count+2 || strcmp(sig.methodReturnType,ret)) return NO;
        for(NSUInteger i=0;i<args.count;i++) if(strcmp([sig getArgumentTypeAtIndex:i+2],[args[i] UTF8String])) return NO;
        return YES;
    } @catch(NSException *e) { return NO; }
}
unsigned WUNativeGameNumber(id x,NSString *s) {
    SEL sel=NSSelectorFromString(s);
    if(Has(x,s,"I",@[])) return ((unsigned(*)(id,SEL))objc_msgSend)(x,sel);
    if(Has(x,s,"Q",@[])) { unsigned long long n=((unsigned long long(*)(id,SEL))objc_msgSend)(x,sel); return n<=UINT_MAX?(unsigned)n:UINT_MAX; }
    if(Has(x,s,"q",@[])) { long long n=((long long(*)(id,SEL))objc_msgSend)(x,sel); return n>=0 && n<=UINT_MAX?(unsigned)n:UINT_MAX; }
    return UINT_MAX;
}
BOOL WUNativeGameControllerAvailable(void) {
    id c=NSClassFromString(@"GameController"); NSString *s=@"getMD5ByGameContent:";
    return Has(c,s,"@",@[@"I"]) || Has(c,s,"@",@[@"Q"]) || Has(c,s,"@",@[@"q"]);
}
static id MD5(unsigned content) {
    id c=NSClassFromString(@"GameController"); SEL s=NSSelectorFromString(@"getMD5ByGameContent:");
    id md5=nil;
    if(Has(c,NSStringFromSelector(s),"@",@[@"I"])) md5=((id(*)(id,SEL,unsigned))objc_msgSend)(c,s,content);
    else if(Has(c,NSStringFromSelector(s),"@",@[@"Q"])) md5=((id(*)(id,SEL,unsigned long long))objc_msgSend)(c,s,content);
    else if(Has(c,NSStringFromSelector(s),"@",@[@"q"])) md5=((id(*)(id,SEL,long long))objc_msgSend)(c,s,content);
    if(![md5 isKindOfClass:NSString.class] || [md5 length]!=32) return nil;
    NSCharacterSet *hex=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    return [md5 rangeOfCharacterFromSet:hex.invertedSet].location==NSNotFound?md5:nil;
}
BOOL WUNativeApplyGameChoice(id wrap,unsigned type,unsigned choice) {
    unsigned content=WUNativeGameContent(type,choice);
    if(!content || WUNativeGameNumber(wrap,@"m_uiMessageType")!=47 || WUNativeGameNumber(wrap,@"m_uiGameType")!=type ||
       !Has(wrap,@"setM_nsEmoticonMD5:","v",@[@"@"])) return NO;
    NSString *setter=@"setM_uiGameContent:";
    BOOL i=Has(wrap,setter,"v",@[@"I"]),q=Has(wrap,setter,"v",@[@"Q"]),sq=Has(wrap,setter,"v",@[@"q"]);
    if(!i && !q && !sq) return NO;
    id md5=MD5(content); if(!md5) return NO;
    ((void(*)(id,SEL,id))objc_msgSend)(wrap,NSSelectorFromString(@"setM_nsEmoticonMD5:"),md5);
    if(i) ((void(*)(id,SEL,unsigned))objc_msgSend)(wrap,NSSelectorFromString(setter),content);
    else if(q) ((void(*)(id,SEL,unsigned long long))objc_msgSend)(wrap,NSSelectorFromString(setter),content);
    else ((void(*)(id,SEL,long long))objc_msgSend)(wrap,NSSelectorFromString(setter),content);
    return WUNativeGameNumber(wrap,@"m_uiGameContent")==content;
}
