#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "VoiceSendLogic.h"
#import "VoicePackLogic.h"
#if __has_include("MessageConstruction.h")
#import "MessageConstruction.h"
#endif
static NSUInteger checks,failures;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { failures++; NSLog(@"FAIL shared constructor line %d",__LINE__); } } while(0)
@interface SharedWrap : NSObject
@property(nonatomic) unsigned int m_uiMessageType,m_uiVoiceFormat,m_uiVoiceTime,m_uiVoiceEndFlag,m_uiCreateTime,m_uiMesLocalID;
@property(nonatomic) long long m_n64MesSvrID;
@property(nonatomic,copy) NSData *m_dtVoice;
@property(nonatomic,copy) NSString *m_nsContent,*m_nsFromUsr,*m_nsToUsr,*m_nsRealChatUsr;
- (void)copyToMsg:(id)message;
@end
@implementation SharedWrap
- (void)copyToMsg:(id)message { (void)message; }
@end
#define CONSTRUCTOR(NAME,TYPE) \
@interface NAME : SharedWrap \
- (instancetype)initWithMsgType:(TYPE)n nsFromUsr:(NSString *)a; \
@end \
@implementation NAME \
- (instancetype)initWithMsgType:(TYPE)n nsFromUsr:(NSString *)a { if((self=[super init])) { self.m_uiMessageType=(unsigned)n; self.m_nsFromUsr=a; } return self; } \
@end
CONSTRUCTOR(InitI,unsigned int)
CONSTRUCTOR(Initq,long long)
CONSTRUCTOR(Initi,int)
CONSTRUCTOR(InitQ,unsigned long long)
@interface SharedHost : NSObject
@property(nonatomic) NSUInteger inserts,sends;
@property(nonatomic,strong) SharedWrap *last;
- (void)AddLocalMsg:(id)a MsgWrap:(id)b;
- (void)ResendVoiceMsg:(id)a MsgWrap:(id)b;
- (void)AddEmoticonMsg:(id)a MsgWrap:(id)b;
@end
@implementation SharedHost
- (void)AddLocalMsg:(id)a MsgWrap:(id)b { self.inserts++; self.last=b; }
- (void)ResendVoiceMsg:(id)a MsgWrap:(id)b { self.sends++; CHECK(self.last==b); }
- (void)AddEmoticonMsg:(id)a MsgWrap:(id)b { self.last=b; }
@end
static SharedHost *host;
static id Service(NSString *name) { return host; }
// The exact production RepeatReady, Has/NumberSetter and WUMatches definitions follow.
#include "p0_repeat_gate.inc"
int main(int argc, const char **argv) { @autoreleasepool {
    NSString *encoding=argc>1?[NSString stringWithUTF8String:argv[1]]:@"I";
    Class parent=NSClassFromString([@"Init" stringByAppendingString:encoding]);
    Class cls=objc_allocateClassPair(parent,"CMessageWrap",0); objc_registerClassPair(cls);
    host=[SharedHost new];
    id source=[cls new];
    CHECK(RepeatReady(source));
#if __has_include("MessageConstruction.h")
    SharedWrap *emoticon=WUCreateMessage(cls,47,@"self");
    CHECK(emoticon.m_uiMessageType==47 && [emoticon.m_nsFromUsr isEqual:@"self"]);
    CHECK(RepeatReady(emoticon));
#endif
    NSString *hex=[[NSString stringWithContentsOfFile:@"tests/fixtures/synthetic.amr.hex" encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    hex=[[hex componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
    NSMutableData *data=[NSMutableData data]; for(NSUInteger i=0;i<hex.length;i+=2) { unsigned n=0; CHECK([[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i,2)]] scanHexInt:&n]); unsigned char b=n; [data appendBytes:&b length:1]; }
    BOOL (^current)(void)=^BOOL{ return YES; };
    WUVoiceForwardOperation *op=[[WUVoiceForwardOperation alloc] initWithData:data account:@"self" target:@"recipient"];
    CHECK([[op submitWithManager:host audioSender:host messageClass:cls current:current] hasPrefix:@"已请求"]);
    CHECK(host.inserts==1 && host.sends==1 && host.last.m_uiMessageType==34);
    CHECK(host.last.m_uiVoiceTime==1000 && host.last.m_uiVoiceFormat==4 && [host.last.m_dtVoice isEqual:data]);
    // A saved voice pack reaches the exact same production forwarding operation and class.
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES].URLByResolvingSymlinksInPath;
    WUVoicePackStore *store=[[WUVoicePackStore alloc] initWithRoot:root account:@"self"];
    CHECK([store saveData:data format:@4 version:@"test/1" name:@"synthetic" current:current error:NULL]);
    NSString *identifier=[store load:NULL].firstObject[@"id"];
    NSDictionary *held=[store acquire:identifier error:NULL]; CHECK(held!=nil);
    op=[[WUVoiceForwardOperation alloc] initWithData:held[@"data"] account:@"self" target:@"recipient"];
    CHECK([[op submitWithManager:host audioSender:host messageClass:cls current:current] hasPrefix:@"已请求"]);
    CHECK(host.inserts==2 && host.sends==2 && host.last.m_uiMessageType==34);
    [store releaseResource:identifier]; CHECK([NSFileManager.defaultManager removeItemAtURL:root error:NULL]);
    printf("P0_MESSAGE_%s: %lu checks, %lu failures (same class repeat/voice/pack)\n",encoding.UTF8String,(unsigned long)checks,(unsigned long)failures);
} return failures?1:0; }
