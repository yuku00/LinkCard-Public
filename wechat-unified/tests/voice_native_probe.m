#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "MessageConstruction.h"
#import "VoiceSendLogic.h"
#import "RepositoryLogic.h"
#import "OfflineVoice.h"
#include <stdlib.h>
#include <string.h>
int WUOfflineDecode(const uint8_t *b,size_t n,WUVoiceCancel c,void *ctx,WUOfflinePCM *o){ (void)b;(void)n;(void)c;(void)ctx;o->samples=calloc(1,sizeof(float));o->frames=16000;o->rate=16000;return 0; }
#define CHECK(x) do { if(!(x)) { NSLog(@"FAIL line %d",__LINE__); exit(1); } } while(0)
@interface CExtendInfoOfVoiceMsg : NSObject
@property(nonatomic,weak) id m_refMessageWrap;
@property(nonatomic,strong) NSData *m_dtVoice;
@property(nonatomic) unsigned int m_uiVoiceTime,m_uiVoiceFormat,m_uiVoiceEndFlag;
@end
@implementation CExtendInfoOfVoiceMsg @end
@interface CMessageWrap : NSObject
@property(nonatomic,strong) CExtendInfoOfVoiceMsg *m_extendInfoWithMsgType;
@property(nonatomic,copy) NSString *m_nsContent,*m_nsFromUsr,*m_nsToUsr;
@property(nonatomic) unsigned int m_uiMessageType,m_uiCreateTime,m_uiStatus,m_uiDownloadStatus;
- (id)initWithMsgType:(long long)n nsFromUsr:(id)account;
@end
@implementation CMessageWrap
- (id)initWithMsgType:(long long)n nsFromUsr:(id)account { if((self=[super init])){_m_uiMessageType=(unsigned)n;_m_nsFromUsr=[account copy];_m_extendInfoWithMsgType=[CExtendInfoOfVoiceMsg new];_m_extendInfoWithMsgType.m_refMessageWrap=self;}return self; }
- (id)forwardingTargetForSelector:(SEL)s { if([self.m_extendInfoWithMsgType respondsToSelector:s]) return self.m_extendInfoWithMsgType; return [super forwardingTargetForSelector:s]; }
@end
@interface MisboundWrap : CMessageWrap
@property(nonatomic,strong) CExtendInfoOfVoiceMsg *other;
@end
@implementation MisboundWrap
- (id)forwardingTargetForSelector:(SEL)s { if([self.other respondsToSelector:s]) return self.other; return [super forwardingTargetForSelector:s]; }
@end
static void wrongFormat(id o,SEL s,unsigned long long n){(void)o;(void)s;(void)n;}
@interface CMessageMgr : NSObject
@property(nonatomic) unsigned inserts,sends,texts;
- (void)AddLocalMsg:(id)t MsgWrap:(id)w;
- (void)ResendVoiceMsg:(id)t MsgWrap:(id)w;
- (void)AddMsg:(id)t MsgWrap:(id)w;
@end
@implementation CMessageMgr
- (id)m_upload { return self; }
- (void)AddLocalMsg:(id)t MsgWrap:(id)w {(void)t;(void)w;_inserts++;}
- (void)ResendVoiceMsg:(id)t MsgWrap:(id)w {(void)t;(void)w;_sends++;}
- (void)AddMsg:(id)t MsgWrap:(id)w {(void)t;(void)w;_texts++;}
@end
@interface MMNewSessionMgr : NSObject
- (unsigned int)GenSendMsgTime;
@end
@implementation MMNewSessionMgr
- (unsigned int)GenSendMsgTime {return 1234;}
@end
int main(void) { @autoreleasepool {
 SEL init=NSSelectorFromString(@"initWithMsgType:nsFromUsr:"); Method m=class_getInstanceMethod(CMessageWrap.class,init); CHECK(m); char *type=method_copyArgumentType(m,2); printf("constructor Method arg2=%s argc=%u\n",type,method_getNumberOfArguments(m)); CHECK(!strcmp(type,"q"));free(type);
 CMessageWrap *wrap=WUCreateVoiceMessage(CMessageWrap.class,34,@"self"); CHECK(wrap && wrap.m_uiMessageType==34 && [wrap.m_nsFromUsr isEqual:@"self"]); puts("constructor: PASS (q, type=34, account)");
 SEL set=NSSelectorFromString(@"setM_uiVoiceFormat:"); SEL get=NSSelectorFromString(@"m_uiVoiceFormat"); ((void(*)(id,SEL,unsigned))objc_msgSend)(wrap,set,4); unsigned value=((unsigned(*)(id,SEL))objc_msgSend)(wrap,get); CHECK(value==4); puts("fast forwarding: PASS (actual message dispatch)");
 BOOL gate=WUVoiceExactSignature(wrap,@"setM_uiVoiceFormat:","v",@[@"I"]); printf("voice signature gate=%d; live methodSignature=%s\n",gate,[wrap methodSignatureForSelector:set]?"present":"nil");
MisboundWrap *mis=[[MisboundWrap alloc] initWithMsgType:34 nsFromUsr:@"self"]; mis.other=[CExtendInfoOfVoiceMsg new]; CHECK(!WUVoiceExactSignature(mis,@"setM_uiVoiceFormat:","v",@[@"I"]));
 Class bad=objc_allocateClassPair(CExtendInfoOfVoiceMsg.class,"BadVoiceExt",0); CHECK(class_addMethod(bad,set,(IMP)wrongFormat,"v@:Q")); objc_registerClassPair(bad); wrap.m_extendInfoWithMsgType=[bad new]; CHECK(!WUVoiceExactSignature(wrap,@"setM_uiVoiceFormat:","v",@[@"I"])); puts("fast forwarding safety: PASS (unbound and wrong-width rejected)");
 CMessageMgr *mgr=[CMessageMgr new]; WUVoiceForwardOperation *op=[[WUVoiceForwardOperation alloc] initWithData:[NSData dataWithBytes:"abcdef" length:6] account:@"self" target:@"target"]; NSString *status=[op submitWithManager:mgr audioSender:mgr messageClass:CMessageWrap.class current:^BOOL{return YES;}]; printf("voice status=%s inserts=%u sends=%u\n",status.UTF8String,mgr.inserts,mgr.sends); CHECK(gate && [status hasPrefix:@"已请求"] && mgr.inserts==1 && mgr.sends==1);
 CMessageWrap *text=WUCreateVoiceMessage(CMessageWrap.class,1,@"self"); NSString *ts=WURepositorySendText(mgr,[MMNewSessionMgr new],text,@"self",@"target",@"test",^BOOL{return YES;}); printf("repository text status=%s calls=%u\n",ts.UTF8String,mgr.texts); CHECK([ts hasPrefix:@"已请求"] && mgr.texts==1);
 puts("PASS: fast-forwarding accepted; constructor and text paths checked, no device or simulator"); return 0;
} }
