#import <Foundation/Foundation.h>
#import "VoiceSendLogic.h"
static NSUInteger checks;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { NSLog(@"FAIL line %d",__LINE__); abort(); } } while(0)
@interface VoiceWrap : NSObject
@property(nonatomic) unsigned int m_uiMessageType, m_uiVoiceFormat, m_uiVoiceTime, m_uiVoiceEndFlag, m_uiCreateTime;
@property(nonatomic,copy) NSData *m_dtVoice;
@property(nonatomic,copy) NSString *m_nsContent, *m_nsFromUsr, *m_nsToUsr;
- (instancetype)initWithMsgType:(unsigned int)n nsFromUsr:(NSString *)a;
@end
@implementation VoiceWrap
- (instancetype)initWithMsgType:(unsigned int)n nsFromUsr:(NSString *)a { if((self=[super init])) { _m_uiMessageType=n; _m_nsFromUsr=[a copy]; } return self; }
@end
@interface VoiceHost : NSObject
@property(nonatomic) NSUInteger inserts, sends;
@property(nonatomic) BOOL insertRaises, sendRaises, invalidate;
@property(nonatomic,strong) VoiceWrap *last;
@property(nonatomic,copy) NSString *target;
- (void)AddLocalMsg:(id)target MsgWrap:(id)wrap;
- (void)ResendVoiceMsg:(id)target MsgWrap:(id)wrap;
@end
@implementation VoiceHost
- (void)AddLocalMsg:(id)target MsgWrap:(id)wrap { self.inserts++; self.last=wrap; self.target=target; if(self.insertRaises) [NSException raise:@"fixture" format:@"after insertion"]; }
- (void)ResendVoiceMsg:(id)target MsgWrap:(id)wrap { self.sends++; CHECK(self.last==wrap); CHECK([self.target isEqual:target]); if(self.sendRaises) [NSException raise:@"fixture" format:@"after request"]; }
@end
@interface WrongWidth : VoiceWrap
@end
@implementation WrongWidth
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { if(s==@selector(setM_uiVoiceTime:)) return [NSMethodSignature signatureWithObjCTypes:"v@:Q"]; return [super methodSignatureForSelector:s]; }
@end
@interface BooleanSender : NSObject
- (BOOL)ResendVoiceMsg:(id)a MsgWrap:(id)b;
@end
@implementation BooleanSender
- (BOOL)ResendVoiceMsg:(id)a MsgWrap:(id)b { abort(); return NO; }
@end
static NSData *Fixture(NSString *name) {
    NSString *text=[NSString stringWithContentsOfFile:[@"tests/fixtures/" stringByAppendingString:name] encoding:NSUTF8StringEncoding error:NULL]; CHECK(text.length>0);
    NSMutableData *data=[NSMutableData data]; NSScanner *scanner=[NSScanner scannerWithString:text];
    NSString *hex=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""]; (void)scanner;
    for(NSUInteger i=0;i<hex.length;i+=2) { unsigned n=0; CHECK([[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i,2)]] scanHexInt:&n]); unsigned char b=n; [data appendBytes:&b length:1]; } return data;
}
static WUVoiceForwardOperation *Operation(NSData *data) { return [[WUVoiceForwardOperation alloc] initWithData:data account:@"self" target:@"recipient"]; }
static NSString *Submit(WUVoiceForwardOperation *op, VoiceHost *host, BOOL (^current)(void)) { return [op submitWithManager:host audioSender:host messageClass:VoiceWrap.class current:current]; }
int main(void) { @autoreleasepool {
    NSData *silk=Fixture(@"standard.silk.hex"), *tencent=Fixture(@"tencent.silk.hex"), *amr=Fixture(@"synthetic.amr.hex");
    CHECK(WUVoiceMeasuredMS(silk)==1000); CHECK(WUVoiceMeasuredMS(tencent)==1000); CHECK(WUVoiceMeasuredMS(amr)==1000);
    CHECK(!WUVoiceMeasuredMS(nil)); CHECK(!WUVoiceMeasuredMS([@"0000ftypM4A invalid" dataUsingEncoding:NSUTF8StringEncoding]));
    CHECK(!WUVoiceMeasuredMS([silk subdataWithRange:NSMakeRange(0,13)]));
    NSMutableData *longVoice=[NSMutableData dataWithBytes:"#!AMR\n" length:6]; for(int i=0;i<61;i++) [longVoice appendData:[amr subdataWithRange:NSMakeRange(6,amr.length-6)]];
    CHECK(!WUVoiceMeasuredMS(longVoice)); [longVoice setLength:6+60*(amr.length-6)]; CHECK(WUVoiceMeasuredMS(longVoice)==60000);
    VoiceWrap *source=[[VoiceWrap alloc] initWithMsgType:34 nsFromUsr:@"original"]; source.m_uiVoiceFormat=4; source.m_dtVoice=tencent;
    CHECK([WUVoiceSelectedData(source) isEqual:tencent]); source.m_uiVoiceFormat=0; CHECK(!WUVoiceSelectedData(source)); source.m_uiVoiceFormat=4; source.m_uiMessageType=1; CHECK(!WUVoiceSelectedData(source)); source.m_uiMessageType=34;
    CHECK(!WUVoiceSelectedData([NSObject new])); CHECK(!WUVoiceSelectedData(nil)); source.m_dtVoice=[NSData data]; CHECK(!WUVoiceSelectedData(source));
    VoiceHost *host=[VoiceHost new]; WUVoiceForwardOperation *op=Operation(tencent); CHECK([op.status isEqual:@"未提交"]); CHECK(op.milliseconds==1000);
    CHECK([Submit(op,host,^BOOL{ return YES; }) hasPrefix:@"已请求"]); CHECK(host.inserts==1 && host.sends==1);
    CHECK(host.last.m_uiMessageType==34 && host.last.m_uiVoiceFormat==4 && host.last.m_uiVoiceTime==1000 && host.last.m_uiVoiceEndFlag==1);
    CHECK([host.last.m_dtVoice isEqual:tencent]); CHECK([host.last.m_nsFromUsr isEqual:@"self"] && [host.last.m_nsToUsr isEqual:@"recipient"]);
    CHECK([host.last.m_nsContent containsString:@"voicelength=\"1000\""]); CHECK(host.last.m_uiCreateTime>0);
    CHECK([Submit(op,host,^BOOL{ return YES; }) hasPrefix:@"已请求"]); CHECK(host.inserts==1 && host.sends==1);
    host=[VoiceHost new]; host.insertRaises=YES; op=Operation(amr); CHECK([Submit(op,host,^BOOL{ return YES; }) hasPrefix:@"未知"]); CHECK(host.inserts==1 && host.sends==0); Submit(op,host,^BOOL{ return YES; }); CHECK(host.inserts==1 && host.sends==0);
    host=[VoiceHost new]; host.sendRaises=YES; op=Operation(silk); CHECK([Submit(op,host,^BOOL{ return YES; }) hasPrefix:@"未知"]); CHECK(host.inserts==1 && host.sends==1); Submit(op,host,^BOOL{ return YES; }); CHECK(host.inserts==1 && host.sends==1);
    host=[VoiceHost new]; op=Operation(amr); CHECK([[op submitWithManager:host audioSender:nil messageClass:VoiceWrap.class current:^BOOL{ return YES; }] hasPrefix:@"失败"]); CHECK(host.inserts==0);
    op=Operation(amr); CHECK([[op submitWithManager:nil audioSender:host messageClass:VoiceWrap.class current:^BOOL{ return YES; }] hasPrefix:@"失败"]); CHECK(host.sends==0);
    op=Operation(amr); CHECK([[op submitWithManager:host audioSender:[BooleanSender new] messageClass:VoiceWrap.class current:^BOOL{ return YES; }] hasPrefix:@"失败"]); CHECK(host.inserts==0);
    op=Operation(amr); CHECK([[op submitWithManager:host audioSender:host messageClass:WrongWidth.class current:^BOOL{ return YES; }] hasPrefix:@"失败"]); CHECK(host.inserts==0);
    op=Operation(amr); CHECK([Submit(op,host,^BOOL{ return NO; }) hasPrefix:@"失败"]); Submit(op,host,^BOOL{ return YES; }); CHECK(host.inserts==0);
    __block NSUInteger calls=0; op=Operation(amr); CHECK([Submit(op,host,^BOOL{ return ++calls<2; }) hasPrefix:@"失败"]); CHECK(host.inserts==0);
    calls=0; op=Operation(amr); CHECK([Submit(op,host,^BOOL{ return ++calls<3; }) hasPrefix:@"未知"]); CHECK(host.inserts==1 && host.sends==0);
    host=[VoiceHost new]; op=Operation([NSData data]); CHECK([Submit(op,host,^BOOL{ return YES; }) hasPrefix:@"失败"]); CHECK(host.inserts==0);
    op=[[WUVoiceForwardOperation alloc] initWithData:amr account:@"" target:@"recipient"]; CHECK([Submit(op,host,^BOOL{ return YES; }) hasPrefix:@"失败"]); CHECK(host.inserts==0);
    NSMutableData *mutable=[amr mutableCopy]; op=Operation(mutable); [mutable resetBytesInRange:NSMakeRange(0,mutable.length)]; CHECK([Submit(op,host,^BOOL{ return YES; }) hasPrefix:@"已请求"]); CHECK([host.last.m_dtVoice isEqual:amr]);
    printf("Voice forwarding production decode/ABI/one-shot mocks: %lu assertions passed\n",(unsigned long)checks);
} return 0; }
