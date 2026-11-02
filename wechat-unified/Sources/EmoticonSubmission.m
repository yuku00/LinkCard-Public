#import "EmoticonSubmission.h"
#import "MessageConstruction.h"
#import "EmoticonLogic.h"
#import "EmoticonLibraryLogic.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <limits.h>
#include <string.h>
#include <math.h>
extern BOOL WUMatches(Method method, const char *returns, NSArray<NSString *> *arguments);
static BOOL Has(id o, NSString *s, const char *r, NSArray *args) { return o && WUMatches(class_getInstanceMethod(object_getClass(o),NSSelectorFromString(s)),r,args); }
static id Object(id o, NSString *s) { return Has(o,s,"@",@[])?((id(*)(id,SEL))objc_msgSend)(o,NSSelectorFromString(s)):nil; }
static char NumericEncoding(id o, NSString *name, BOOL setter) {
    @try {
        SEL sel=NSSelectorFromString(name);
        Method method=o?class_getInstanceMethod(object_getClass(o),sel):NULL;
        NSMethodSignature *sig=o?[o methodSignatureForSelector:sel]:nil;
        if(!method || !sig || method_getNumberOfArguments(method)!=(setter?3u:2u) || sig.numberOfArguments!=(setter?3u:2u) || strcmp([sig getArgumentTypeAtIndex:0],"@") || strcmp([sig getArgumentTypeAtIndex:1],":")) return 0;
        for(NSString *type in @[@"I",@"i",@"Q",@"q"]) {
            const char *t=type.UTF8String;
            if(WUMatches(method,setter?"v":t,setter?@[type]:@[]) && !strcmp(sig.methodReturnType,setter?"v":t) && (setter ? !strcmp([sig getArgumentTypeAtIndex:2],t) && sig.methodReturnLength==0 : sig.methodReturnLength==((*t=='I'||*t=='i')?4u:8u))) return *t;
        }
    } @catch(NSException *e) { }
    return 0;
}
static BOOL Numeric(id o, NSString *s, BOOL setter) { return NumericEncoding(o,s,setter)!=0; }
static uint64_t Number(id o, NSString *s) {
    SEL sel=NSSelectorFromString(s);
    switch(NumericEncoding(o,s,NO)) {
        case 'I': return ((uint32_t(*)(id,SEL))objc_msgSend)(o,sel);
        case 'i': { int32_t n=((int32_t(*)(id,SEL))objc_msgSend)(o,sel); return n<0?UINT64_MAX:(uint64_t)n; }
        case 'Q': return ((uint64_t(*)(id,SEL))objc_msgSend)(o,sel);
        case 'q': { int64_t n=((int64_t(*)(id,SEL))objc_msgSend)(o,sel); return n<0?UINT64_MAX:(uint64_t)n; }
    }
    return UINT64_MAX;
}
static BOOL SetNumber(id o, NSString *s, uint64_t value) {
    SEL sel=NSSelectorFromString(s);
    switch(NumericEncoding(o,s,YES)) {
        case 'I': if(value<=UINT32_MAX) { ((void(*)(id,SEL,uint32_t))objc_msgSend)(o,sel,(uint32_t)value); return YES; } break;
        case 'i': if(value<=INT32_MAX) { ((void(*)(id,SEL,int32_t))objc_msgSend)(o,sel,(int32_t)value); return YES; } break;
        case 'Q': ((void(*)(id,SEL,uint64_t))objc_msgSend)(o,sel,value); return YES;
        case 'q': if(value<=INT64_MAX) { ((void(*)(id,SEL,int64_t))objc_msgSend)(o,sel,(int64_t)value); return YES; } break;
    }
    return NO;
}
BOOL WUEmoticonSourceReady(id source, id manager) {
    @try {
        Class c=NSClassFromString(@"CMessageWrap");
        if(![source isKindOfClass:c] || Number(source,@"m_uiMessageType")!=47 || !WUMessageCanConstruct(c) || !Has(source,@"copyToMsg:","v",@[@"@"]) || !Has(manager,@"AddEmoticonMsg:MsgWrap:","v",@[@"@",@"@"])) return NO;
        for(NSString *s in @[@"m_nsFromUsr",@"m_nsToUsr",@"m_nsRealChatUsr"]) if(!Has(source,s,"@",@[])) return NO;
        for(NSString *s in @[@"setM_nsFromUsr:",@"setM_nsToUsr:",@"setM_nsRealChatUsr:"]) if(!Has(source,s,"v",@[@"@"])) return NO;
        for(NSString *s in @[@"setM_uiCreateTime:",@"setM_uiMesLocalID:",@"setM_n64MesSvrID:"]) if(!Numeric(source,s,YES)) return NO;
        return YES;
    } @catch(NSException *e) { return NO; }
}
BOOL WUEmoticonDataAvailable(id manager) {
    @try { return WUMessageCanConstruct(NSClassFromString(@"CMessageWrap")) && Has(manager,@"AddEmoticonMsg:MsgWrap:","v",@[@"@",@"@"]) && Has(NSClassFromString(@"CEmoticonMgr"),@"emoticonMsgForImageData:errorMsg:","@",@[@"@",@"^@"]); }
    @catch(NSException *e) { return NO; }
}
NSString *WUSubmitEmoticonCopy(id source, id manager, NSString *account, NSString *target, BOOL (^current)(void)) {
    BOOL attempted=NO;
    @try {
        if(!NSThread.isMainThread || !account.length || !target.length || !current || !current() || !WUEmoticonSourceReady(source,manager)) return @"表情接口或上下文不可用，未提交";
        id message=WUCreateMessage(NSClassFromString(@"CMessageWrap"),47,account);
        if(!message || message==source || !WUEmoticonSourceReady(message,manager)) return @"无法构造独立表情消息，未提交";
        ((void(*)(id,SEL,id))objc_msgSend)(source,NSSelectorFromString(@"copyToMsg:"),message);
        if(Number(message,@"m_uiMessageType")!=47) return @"复制后消息类型不符，未提交";
        ((void(*)(id,SEL,id))objc_msgSend)(message,NSSelectorFromString(@"setM_nsFromUsr:"),account);
        ((void(*)(id,SEL,id))objc_msgSend)(message,NSSelectorFromString(@"setM_nsToUsr:"),target);
        ((void(*)(id,SEL,id))objc_msgSend)(message,NSSelectorFromString(@"setM_nsRealChatUsr:"),nil);
        double now=NSDate.date.timeIntervalSince1970;
        if(!isfinite(now) || now<=0 || now>UINT32_MAX || !SetNumber(message,@"setM_uiCreateTime:",(uint64_t)now) || !SetNumber(message,@"setM_uiMesLocalID:",0) || !SetNumber(message,@"setM_n64MesSvrID:",0)) return @"消息数值字段ABI或范围不符，未提交";
        id real=Object(message,@"m_nsRealChatUsr");
        if((real && (![real isKindOfClass:NSString.class] || [real length])) || !current() || ![Object(message,@"m_nsFromUsr") isEqual:account] || ![Object(message,@"m_nsToUsr") isEqual:target] || Number(message,@"m_uiMesLocalID")!=0 || Number(message,@"m_n64MesSvrID")!=0) return @"身份清理或会话复核失败，未提交";
        attempted=YES;
        ((void(*)(id,SEL,id,id))objc_msgSend)(manager,NSSelectorFromString(@"AddEmoticonMsg:MsgWrap:"),target,message);
        return @"表情发送已请求；送达状态以微信为准，不自动重试";
    } @catch(NSException *e) { return attempted?@"发送结果未知；未重试，请核对聊天记录":@"消息构造失败；未提交，不自动重试"; }
}
NSString *WUSubmitEmoticonData(NSData *original, id manager, NSString *account, NSString *target, BOOL (^current)(void)) {
    @try {
        NSData *bytes=[original copy]; Class factory=NSClassFromString(@"CEmoticonMgr"); NSString *selector=@"emoticonMsgForImageData:errorMsg:";
        if(!NSThread.isMainThread || !current || !current() || !WUEmoticonDataAvailable(manager) || !WUEmoticonType(bytes) || !Has(factory,selector,"@",@[@"@",@"^@"])) return @"完整原始媒体或CEmoticonMgr数据工厂签名不可用；未提交";
        // WCRefine 0xfac850/0xfacd50-70: class receiver, raw NSData, autoreleasing error out-pointer.
        id error=nil; id source=((id(*)(id,SEL,id,id __autoreleasing *))objc_msgSend)(factory,NSSelectorFromString(selector),bytes,&error);
        if(!source || !current()) return @"生成表情失败或上下文失效，未提交";
        id md5=Object(source,@"m_nsEmoticonMD5")?:Object(Object(source,@"m_extendInfoWithMsgType"),@"m_nsEmoticonMD5");
        if(![md5 isKindOfClass:NSString.class] || ![[md5 lowercaseString] isEqual:WUEmoticonDigest(bytes)]) return @"宿主工厂返回的表情身份与原始字节不符，未提交；不转码或改写缓存补救";
        return WUSubmitEmoticonCopy(source,manager,account,target,current);
    } @catch(NSException *e) { return @"表情工厂异常；未提交，未尝试备用发送器"; }
}
