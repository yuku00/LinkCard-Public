#import "VoiceSendLogic.h"
#import "RepositoryLogic.h"
#import "OfflineVoice.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#include <stdlib.h>
#import "MessageConstruction.h"
BOOL WUVoiceExactSignature(id o, NSString *name, const char *result, NSArray<NSString *> *args) {
    @try {
        SEL s=NSSelectorFromString(name); Method m=o?class_getInstanceMethod(object_getClass(o),s):NULL;
        if(!m || method_getNumberOfArguments(m)!=args.count+2) return NO;
        NSMethodSignature *sig=[o methodSignatureForSelector:s];
        if(!sig || sig.numberOfArguments!=args.count+2 || strcmp(sig.methodReturnType,result)) return NO;
        char *r=method_copyReturnType(m); BOOL ok=r && !strcmp(r,result); free(r);
        for(NSUInteger i=0;i<args.count+2;i++) {
            const char *expected=i==0?"@":(i==1?":":args[i-2].UTF8String); char *t=method_copyArgumentType(m,(unsigned)i);
            const char *actual=[sig getArgumentTypeAtIndex:i];
            ok=ok && t && actual && !strcmp(t,expected) && !strcmp(actual,expected); free(t);
        }
        return ok;
    } @catch(NSException *e) { return NO; }
}
// Only the three host methods observed with v@:@@ may be forwarded by an NSProxy.
// The actual host class and the proxy must both expose the exact same ABI.
static BOOL VoiceServiceReady(id receiver, NSString *className, NSString *selector) {
    if(WUVoiceExactSignature(receiver,selector,"v",@[@"@",@"@"])) return YES;
    @try {
        BOOL proxy=NO;
        for(Class c=object_getClass(receiver); c; c=class_getSuperclass(c)) if(c==objc_getClass("NSProxy")) { proxy=YES; break; }
        if(!proxy) return NO;
        SEL sel=NSSelectorFromString(selector);
        if(class_getInstanceMethod(object_getClass(receiver),sel)) return NO;
        Class host=NSClassFromString(className);
        Method method=host?class_getInstanceMethod(host,sel):NULL;
        if(!method || method_getNumberOfArguments(method)!=4) return NO;
        char *r=method_copyReturnType(method), *a=method_copyArgumentType(method,2), *b=method_copyArgumentType(method,3);
        BOOL ok=r && a && b && !strcmp(r,"v") && !strcmp(a,"@") && !strcmp(b,"@");
        free(r); free(a); free(b);
        NSMethodSignature *s=[receiver methodSignatureForSelector:sel];
        return ok && s && s.numberOfArguments==4 && !strcmp(s.methodReturnType,"v") && !strcmp([s getArgumentTypeAtIndex:0],"@") && !strcmp([s getArgumentTypeAtIndex:1],":") && !strcmp([s getArgumentTypeAtIndex:2],"@") && !strcmp([s getArgumentTypeAtIndex:3],"@");
    } @catch(NSException *e) { return NO; }
}
static NSString *VoiceServiceInvoke(id receiver, NSString *className, NSString *selector, id first, id second) {
    if(!first || !second || !VoiceServiceReady(receiver,className,selector)) return @"失败：接口不可用，未提交";
    BOOL invoked=NO;
    @try {
        SEL sel=NSSelectorFromString(selector);
        NSInvocation *inv=[NSInvocation invocationWithMethodSignature:[receiver methodSignatureForSelector:sel]];
        inv.target=receiver; inv.selector=sel;
        __unsafe_unretained id a=first,b=second;
        [inv setArgument:&a atIndex:2]; [inv setArgument:&b atIndex:3];
        invoked=YES; [inv invoke];
        return @"已请求（非送达）";
    } @catch(NSException *e) { return invoked?@"未知：调用异常，请核对宿主，勿盲重发":@"失败：未提交"; }
}
NSData *WUVoiceSelectedData(id wrap) {
    @try {
        if(!WUVoiceExactSignature(wrap,@"m_uiMessageType","I",@[]) || !WUVoiceExactSignature(wrap,@"m_uiVoiceFormat","I",@[]) || !WUVoiceExactSignature(wrap,@"m_dtVoice","@",@[])) return nil;
        if(((unsigned(*)(id,SEL))objc_msgSend)(wrap,NSSelectorFromString(@"m_uiMessageType"))!=34 || ((unsigned(*)(id,SEL))objc_msgSend)(wrap,NSSelectorFromString(@"m_uiVoiceFormat"))!=4) return nil;
        id data=((id(*)(id,SEL))objc_msgSend)(wrap,NSSelectorFromString(@"m_dtVoice"));
        return [data isKindOfClass:NSData.class] && [data length]>=6 && [data length]<=8*1024*1024 ? [data copy] : nil;
    } @catch(NSException *e) { return nil; }
}
uint32_t WUVoiceMeasuredMS(NSData *data) {
    if(![data isKindOfClass:NSData.class] || data.length<6 || data.length>8*1024*1024) return 0;
    WUOfflinePCM pcm={0}; if(WUOfflineDecode(data.bytes,data.length,NULL,NULL,&pcm)) return 0;
    uint64_t numerator=(uint64_t)pcm.frames*1000;
    uint32_t ms=pcm.rate && numerator%pcm.rate==0 && numerator/pcm.rate<=60000 ? (uint32_t)(numerator/pcm.rate) : 0;
    free(pcm.samples); return ms;
}
@interface WUVoiceForwardOperation ()
@property(nonatomic,readwrite,copy) NSString *status;
@property(nonatomic,copy) NSData *data;
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSString *target;
@property(nonatomic) uint32_t milliseconds;
@property(nonatomic) BOOL consumed;
@end
@implementation WUVoiceForwardOperation
- (instancetype)initWithData:(NSData *)data account:(NSString *)account target:(NSString *)target {
    if((self=[super init])) { _data=[data copy]; _milliseconds=WUVoiceMeasuredMS(_data); _account=[account copy]; _target=[target copy]; _status=@"未提交"; } return self;
}
- (NSString *)submitWithManager:(id)manager audioSender:(id)audio messageClass:(Class)cls current:(BOOL (^)(void))current {
    @synchronized(self) {
        if(self.consumed) return self.status; self.consumed=YES;
        BOOL attempted=NO;
        @try {
            // WCPulse uses CMessageMgr only when AudioSender is absent; choose before side effects.
            id sender=audio ?: manager;
            NSString *senderClass=audio?@"AudioSender":@"CMessageMgr";
            NSString *sendSelector=audio?@"ResendVoiceMsg:MsgWrap:":@"ResendMsg:MsgWrap:";
            if(!NSThread.isMainThread || !current || !current() || !self.account.length || !self.target.length || !self.data.length || !self.milliseconds || self.milliseconds>60000 || !VoiceServiceReady(manager,@"CMessageMgr",@"AddLocalMsg:MsgWrap:") || !VoiceServiceReady(sender,senderClass,sendSelector)) { self.status=@"失败：上下文或语音服务不可用，未提交"; return self.status; }
            id message=WUCreateVoiceMessage(cls,34,self.account);
            if(!message) { self.status=@"失败：消息构造ABI不可用或初始化失败，未提交"; return self.status; }
            NSArray *objects=@[@"setM_nsContent:",@"setM_nsFromUsr:",@"setM_nsToUsr:",@"setM_dtVoice:"];
            NSArray *numbers=@[@"setM_uiVoiceTime:",@"setM_uiVoiceFormat:",@"setM_uiVoiceEndFlag:",@"setM_uiCreateTime:"];
            NSArray *objectGetters=@[@"m_nsContent",@"m_nsFromUsr",@"m_nsToUsr",@"m_dtVoice"];
            NSArray *numberGetters=@[@"m_uiVoiceTime",@"m_uiVoiceFormat",@"m_uiVoiceEndFlag",@"m_uiCreateTime"];
            for(NSString *s in objects) if(!WUVoiceExactSignature(message,s,"v",@[@"@"])) { self.status=@"失败：消息对象字段ABI不可用，未提交"; return self.status; }
            for(NSString *s in numbers) if(!WUVoiceExactSignature(message,s,"v",@[@"I"])) { self.status=@"失败：消息整数宽度不符，未提交"; return self.status; }
            for(NSString *s in objectGetters) if(!WUVoiceExactSignature(message,s,"@",@[])) { self.status=@"失败：消息字段无法核验，未提交"; return self.status; }
            for(NSString *s in numberGetters) if(!WUVoiceExactSignature(message,s,"I",@[])) { self.status=@"失败：消息字段无法核验，未提交"; return self.status; }
            if(!WUVoiceExactSignature(message,@"m_uiMessageType","I",@[])) { self.status=@"失败：消息类型无法核验，未提交"; return self.status; }
            NSArray *values=@[[NSString stringWithFormat:@"<msg><voicemsg voicelength=\"%u\" voiceformat=\"4\" forwardflag=\"0\" /></msg>",self.milliseconds],self.account,self.target,self.data];
            for(NSUInteger i=0;i<objects.count;i++) ((void(*)(id,SEL,id))objc_msgSend)(message,NSSelectorFromString(objects[i]),values[i]);
            uint32_t ints[]={self.milliseconds,4,1,(uint32_t)NSDate.date.timeIntervalSince1970};
            for(NSUInteger i=0;i<numbers.count;i++) ((void(*)(id,SEL,unsigned))objc_msgSend)(message,NSSelectorFromString(numbers[i]),ints[i]);
            if(((unsigned(*)(id,SEL))objc_msgSend)(message,NSSelectorFromString(@"m_uiMessageType"))!=34) { self.status=@"失败：消息类型核验不符，未提交"; return self.status; }
            for(NSUInteger i=0;i<objectGetters.count;i++) {
                id value=((id(*)(id,SEL))objc_msgSend)(message,NSSelectorFromString(objectGetters[i]));
                if(![values[i] isEqual:value]) { self.status=@"失败：消息字段核验不符，未提交"; return self.status; }
            }
            for(NSUInteger i=0;i<numberGetters.count;i++) if(((unsigned(*)(id,SEL))objc_msgSend)(message,NSSelectorFromString(numberGetters[i]))!=ints[i]) { self.status=@"失败：消息字段核验不符，未提交"; return self.status; }
            if(!current() || !VoiceServiceReady(manager,@"CMessageMgr",@"AddLocalMsg:MsgWrap:") || !VoiceServiceReady(sender,senderClass,sendSelector)) { self.status=@"失败：确认或语音服务已失效，未提交"; return self.status; }
            // Consume before the first host side effect. Repository invocation has no fallback.
            attempted=YES; self.status=@"未知：已尝试本地插入，未获发送回执";
            NSString *insert=VoiceServiceInvoke(manager,@"CMessageMgr",@"AddLocalMsg:MsgWrap:",self.target,message);
            if(![insert hasPrefix:@"已请求"] || !current()) return self.status;
            NSString *send=VoiceServiceInvoke(sender,senderClass,sendSelector,self.target,message);
            self.status=[send hasPrefix:@"已请求"]?@"已请求（非送达）；不自动重试":@"未知：可能已插入或请求，请核对宿主，未重试";
        } @catch(NSException *e) { self.status=attempted?@"未知：提交边界异常，请核对宿主，未重试":@"失败：构造异常，未提交"; }
        return self.status;
    }
}
@end
