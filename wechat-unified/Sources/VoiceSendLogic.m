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
        char *r=method_copyReturnType(m); BOOL ok=!strcmp(r,result); free(r);
        for(NSUInteger i=0;i<args.count;i++) {
            const char *expected=args[i].UTF8String; char *t=method_copyArgumentType(m,(unsigned)i+2);
            ok=ok && !strcmp(t,expected) && !strcmp([sig getArgumentTypeAtIndex:i+2],expected); free(t);
        }
        return ok;
    } @catch(NSException *e) { return NO; }
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
            if(!NSThread.isMainThread || !current || !current() || !self.account.length || !self.target.length || !self.data.length || !self.milliseconds || self.milliseconds>60000 || !WUVoiceExactSignature(manager,@"AddLocalMsg:MsgWrap:","v",@[@"@",@"@"]) || !WUVoiceExactSignature(audio,@"ResendVoiceMsg:MsgWrap:","v",@[@"@",@"@"])) { self.status=@"失败：上下文或语音服务不可用，未提交"; return self.status; }
            id message=WUCreateMessage(cls,34,self.account);
            if(!message) { self.status=@"失败：消息构造ABI不可用或初始化失败，未提交"; return self.status; }
            NSArray *objects=@[@"setM_nsContent:",@"setM_nsFromUsr:",@"setM_nsToUsr:",@"setM_dtVoice:"];
            NSArray *numbers=@[@"setM_uiVoiceTime:",@"setM_uiVoiceFormat:",@"setM_uiVoiceEndFlag:",@"setM_uiCreateTime:"];
            for(NSString *s in objects) if(!WUVoiceExactSignature(message,s,"v",@[@"@"])) { self.status=@"失败：消息对象字段ABI不可用，未提交"; return self.status; }
            for(NSString *s in numbers) if(!WUVoiceExactSignature(message,s,"v",@[@"I"])) { self.status=@"失败：消息整数宽度不符，未提交"; return self.status; }
            NSArray *values=@[[NSString stringWithFormat:@"<msg><voicemsg voicelength=\"%u\" voiceformat=\"4\" forwardflag=\"0\" /></msg>",self.milliseconds],self.account,self.target,self.data];
            for(NSUInteger i=0;i<objects.count;i++) ((void(*)(id,SEL,id))objc_msgSend)(message,NSSelectorFromString(objects[i]),values[i]);
            uint32_t ints[]={self.milliseconds,4,1,(uint32_t)NSDate.date.timeIntervalSince1970};
            for(NSUInteger i=0;i<numbers.count;i++) ((void(*)(id,SEL,unsigned))objc_msgSend)(message,NSSelectorFromString(numbers[i]),ints[i]);
            if(!current()) { self.status=@"失败：确认已失效，未提交"; return self.status; }
            // Consume before the first host side effect. Repository invocation has no fallback.
            attempted=YES; self.status=@"未知：已尝试本地插入，未获发送回执";
            NSString *insert=WURepositoryInvoke(manager,@"AddLocalMsg:MsgWrap:",self.target,message);
            if(![insert hasPrefix:@"已请求"] || !current()) return self.status;
            NSString *send=WURepositoryInvoke(audio,@"ResendVoiceMsg:MsgWrap:",self.target,message);
            self.status=[send hasPrefix:@"已请求"]?@"已请求（非送达）；不自动重试":@"未知：可能已插入或请求，请核对宿主，未重试";
        } @catch(NSException *e) { self.status=attempted?@"未知：提交边界异常，请核对宿主，未重试":@"失败：构造异常，未提交"; }
        return self.status;
    }
}
@end
