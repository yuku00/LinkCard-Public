#import "WUNative.h"
#include <limits.h>
static BOOL Has(id x,NSString *s,const char *ret,NSArray *args) {
    return x && WUMatches(class_getInstanceMethod(object_getClass(x),NSSelectorFromString(s)),ret,args);
}
unsigned WUNativeGameNumber(id x,NSString *s) {
    SEL sel=NSSelectorFromString(s);
    if(Has(x,s,"I",@[])) return ((unsigned(*)(id,SEL))objc_msgSend)(x,sel);
    if(Has(x,s,"Q",@[])) { unsigned long long n=((unsigned long long(*)(id,SEL))objc_msgSend)(x,sel); return n<=UINT_MAX?(unsigned)n:UINT_MAX; }
    if(Has(x,s,"q",@[])) { long long n=((long long(*)(id,SEL))objc_msgSend)(x,sel); return n>=0 && n<=UINT_MAX?(unsigned)n:UINT_MAX; }
    return UINT_MAX;
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
