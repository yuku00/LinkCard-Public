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
        // 8.0.79 CMessageWrap forwards its @dynamic voice properties to the
        // typed extension; their IMPs need not exist on CMessageWrap itself.
        if(!m && o) {
            static NSSet *voiceSelectors;
            static dispatch_once_t once;
            dispatch_once(&once, ^{ voiceSelectors=[NSSet setWithArray:@[@"m_dtVoice",@"setM_dtVoice:",@"m_uiVoiceTime",@"setM_uiVoiceTime:",@"m_uiVoiceFormat",@"setM_uiVoiceFormat:",@"m_uiVoiceEndFlag",@"setM_uiVoiceEndFlag:"]]; });
            Class wrap=NSClassFromString(@"CMessageWrap"), ext=NSClassFromString(@"CExtendInfoOfVoiceMsg");
            if(wrap && ext && [o isKindOfClass:wrap] && [voiceSelectors containsObject:name]) m=class_getInstanceMethod(ext,s);
        }
        if(!m || method_getNumberOfArguments(m)!=args.count+2) return NO;
        // Direct dispatch uses the concrete Method ABI, not forwarding signatures.
        // Forwarded voice properties require a live signature or a verified fast target.
        BOOL forwarded=class_getInstanceMethod(object_getClass(o),s)==NULL;
        NSMethodSignature *sig=forwarded?[o methodSignatureForSelector:s]:nil;
        if(forwarded && !sig) {
            // NSObject fast forwarding may work without a method signature. Only
            // accept the exact voice extension currently bound to this wrap.
            if(!WUVoiceExactSignature(o,@"m_extendInfoWithMsgType","@",@[]) ||
               !WUVoiceExactSignature(o,@"forwardingTargetForSelector:","@",@[@":"])) return NO;
            id bound=((id(*)(id,SEL))objc_msgSend)(o,NSSelectorFromString(@"m_extendInfoWithMsgType"));
            id target=((id(*)(id,SEL,SEL))objc_msgSend)(o,@selector(forwardingTargetForSelector:),s);
            Class ext=NSClassFromString(@"CExtendInfoOfVoiceMsg");
            if(!bound || target!=bound || !ext || ![target isKindOfClass:ext]) return NO;
            m=class_getInstanceMethod(object_getClass(target),s);
            if(!m || method_getNumberOfArguments(m)!=args.count+2) return NO;
            forwarded=NO; // Validate the actual forwarding target's concrete Method.
        }
        if(forwarded && (sig.numberOfArguments!=args.count+2 || strcmp(sig.methodReturnType,result))) return NO;
        char *r=method_copyReturnType(m); BOOL ok=r && !strcmp(r,result); free(r);
        for(NSUInteger i=0;i<args.count+2;i++) {
            const char *expected=i==0?"@":(i==1?":":args[i-2].UTF8String); char *t=method_copyArgumentType(m,(unsigned)i);
            const char *actual=forwarded?[sig getArgumentTypeAtIndex:i]:expected;
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
        invoked=YES; ((void(*)(id,SEL,id,id))objc_msgSend)(receiver,sel,first,second);
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
    return [self submitWithManager:manager audioSender:audio uploadManager:nil messageClass:cls current:current];
}
- (NSString *)submitWithManager:(id)manager audioSender:(id)audio uploadManager:(id)upload messageClass:(Class)cls current:(BOOL (^)(void))current {
    @synchronized(self) {
        if(self.consumed) return self.status; self.consumed=YES;
        BOOL attempted=NO;
        @try {
            if(!NSThread.isMainThread || !current || !current() || !self.account.length || !self.target.length || !self.data.length || !self.milliseconds || self.milliseconds>60000) { self.status=@"失败：上下文或语音数据不可用，未提交"; return self.status; }
            // WCVoice selects AudioSender.m_upload, otherwise MMNewUploadVoiceMgr.
            // Resolve and validate both before AddLocalMsg; never fall back after it.
            id sender=nil;
            @try { if(audio) sender=[audio valueForKey:@"m_upload"]; } @catch(NSException *e) { sender=nil; }
            NSString *senderClass=@"BaseUploadVoiceMgr";
            NSString *sendSelector=@"ResendVoiceMsg:MsgWrap:";
            if(!VoiceServiceReady(sender,senderClass,sendSelector)) { sender=upload; senderClass=@"MMNewUploadVoiceMgr"; }
            if(!VoiceServiceReady(manager,@"CMessageMgr",@"AddLocalMsg:MsgWrap:") || !VoiceServiceReady(sender,senderClass,sendSelector)) { self.status=@"失败：语音服务不可用，未提交"; return self.status; }
            id message=WUCreateVoiceMessage(cls,34,self.account);
            if(!message) { self.status=@"失败：消息构造ABI不可用或初始化失败，未提交"; return self.status; }
            // Bind the extension before touching dynamic voice properties.
            // Only use it when the declared host getter/setter are both present and checked.
            if(WUVoiceExactSignature(message,@"m_extendInfoWithMsgType","@",@[]) && WUVoiceExactSignature(message,@"setM_extendInfoWithMsgType:","v",@[@"@"])) {
                id extension=((id(*)(id,SEL))objc_msgSend)(message,NSSelectorFromString(@"m_extendInfoWithMsgType"));
                if(!extension) {
                    Class extClass=NSClassFromString(@"CExtendInfoOfVoiceMsg");
                    if(!extClass) { self.status=@"失败：语音扩展不可用，未提交"; return self.status; }
                    id allocated=[extClass alloc];
                    if(!WUVoiceExactSignature(allocated,@"init","@",@[])) { self.status=@"失败：语音扩展初始化ABI不可用，未提交"; return self.status; }
                    extension=[allocated init];
                    if(!extension || !WUVoiceExactSignature(extension,@"setM_refMessageWrap:","v",@[@"@"]) || !WUVoiceExactSignature(extension,@"m_refMessageWrap","@",@[])) { self.status=@"失败：语音扩展ABI不可用，未提交"; return self.status; }
                    ((void(*)(id,SEL,id))objc_msgSend)(extension,NSSelectorFromString(@"setM_refMessageWrap:"),message);
                    if(((id(*)(id,SEL))objc_msgSend)(extension,NSSelectorFromString(@"m_refMessageWrap"))!=message) { self.status=@"失败：语音扩展回指未绑定，未提交"; return self.status; }
                    ((void(*)(id,SEL,id))objc_msgSend)(message,NSSelectorFromString(@"setM_extendInfoWithMsgType:"),extension);
                    if(((id(*)(id,SEL))objc_msgSend)(message,NSSelectorFromString(@"m_extendInfoWithMsgType"))!=extension) { self.status=@"失败：语音扩展未绑定，未提交"; return self.status; }
                }
            }
            NSArray *objects=@[@"setM_nsContent:",@"setM_nsFromUsr:",@"setM_nsToUsr:",@"setM_dtVoice:"];
            NSArray *numbers=@[@"setM_uiVoiceTime:",@"setM_uiVoiceFormat:",@"setM_uiVoiceEndFlag:",@"setM_uiCreateTime:",@"setM_uiStatus:",@"setM_uiDownloadStatus:"];
            NSArray *objectGetters=@[@"m_nsContent",@"m_nsFromUsr",@"m_nsToUsr",@"m_dtVoice"];
            NSArray *numberGetters=@[@"m_uiVoiceTime",@"m_uiVoiceFormat",@"m_uiVoiceEndFlag",@"m_uiCreateTime",@"m_uiStatus",@"m_uiDownloadStatus"];
            for(NSString *s in objects) if(!WUVoiceExactSignature(message,s,"v",@[@"@"])) { self.status=@"失败：消息对象字段ABI不可用，未提交"; return self.status; }
            for(NSString *s in numbers) if(!WUVoiceExactSignature(message,s,"v",@[@"I"])) { self.status=@"失败：消息整数宽度不符，未提交"; return self.status; }
            for(NSString *s in objectGetters) if(!WUVoiceExactSignature(message,s,"@",@[])) { self.status=@"失败：消息字段无法核验，未提交"; return self.status; }
            for(NSString *s in numberGetters) if(!WUVoiceExactSignature(message,s,"I",@[])) { self.status=@"失败：消息字段无法核验，未提交"; return self.status; }
            if(!WUVoiceExactSignature(message,@"m_uiMessageType","I",@[])) { self.status=@"失败：消息类型无法核验，未提交"; return self.status; }
            NSArray *values=@[[NSString stringWithFormat:@"<msg><voicemsg voicelength=\"%u\" voiceformat=\"4\" forwardflag=\"0\" /></msg>",self.milliseconds],self.account,self.target,self.data];
            for(NSUInteger i=0;i<objects.count;i++) ((void(*)(id,SEL,id))objc_msgSend)(message,NSSelectorFromString(objects[i]),values[i]);
            // WCVoice initializes outgoing status=1 and download status=9.
            uint32_t ints[]={self.milliseconds,4,1,(uint32_t)NSDate.date.timeIntervalSince1970,1,9};
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
