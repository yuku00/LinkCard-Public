#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "MessageConstruction.h"
#import "VoiceSendLogic.h"
#include <limits.h>
static NSUInteger checks, calls, live;
static uint64_t seen;
static NSString *seenAccount;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { NSLog(@"FAIL construction line %d",__LINE__); abort(); } } while(0)
@interface Tracked : NSObject
@end
@implementation Tracked
+ (instancetype)allocWithZone:(struct _NSZone *)zone { id x=[super allocWithZone:zone]; live++; return x; }
- (void)dealloc { live--; }
@end
#define CONSTRUCTOR(NAME,TYPE) \
@interface NAME : Tracked \
- (instancetype)initWithMsgType:(TYPE)n nsFromUsr:(NSString *)a; \
@end \
@implementation NAME \
- (instancetype)initWithMsgType:(TYPE)n nsFromUsr:(NSString *)a { if((self=[super init])) { calls++; seen=(uint64_t)n; seenAccount=[a copy]; } return self; } \
@end
CONSTRUCTOR(ConstructI,unsigned int)
CONSTRUCTOR(Constructi,int)
CONSTRUCTOR(Constructq,long long)
CONSTRUCTOR(ConstructQ,unsigned long long)
@interface Replacement : Tracked @end
@implementation Replacement @end
static int initMode;
@interface SpecialInit : Tracked
- (instancetype)initWithMsgType:(unsigned int)n nsFromUsr:(NSString *)a;
@end
@implementation SpecialInit
- (instancetype)initWithMsgType:(unsigned int)n nsFromUsr:(NSString *)a {
    if((self=[super init])) {
        calls++;
        if(initMode==1) return nil;
        if(initMode==2) [NSException raise:@"fixture" format:@"init throws before any send"];
        if(initMode==3) self=(id)[Replacement new];
    }
    return self;
}
@end
static const char *spoof;
@interface InstanceMismatch : ConstructI @end
@implementation InstanceMismatch
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { if(s==NSSelectorFromString(@"initWithMsgType:nsFromUsr:")) return [NSMethodSignature signatureWithObjCTypes:spoof]; return [super methodSignatureForSelector:s]; }
@end
@interface ClassMismatch : ConstructI @end
@implementation ClassMismatch
+ (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)s { if(s==NSSelectorFromString(@"initWithMsgType:nsFromUsr:")) return [NSMethodSignature signatureWithObjCTypes:spoof]; return [super instanceMethodSignatureForSelector:s]; }
@end
@interface SignatureThrows : ConstructI @end
@implementation SignatureThrows
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { [NSException raise:@"fixture" format:@"signature throws"]; return nil; }
@end
static id NeverCalled(id object, SEL selector, ...) { calls++; return nil; }
static Class BadShape(const char *encoding) {
    static unsigned index;
    Class cls=objc_allocateClassPair(Tracked.class,[[NSString stringWithFormat:@"BadConstructor%u",++index] UTF8String],0);
    CHECK(class_addMethod(cls,NSSelectorFromString(@"initWithMsgType:nsFromUsr:"),(IMP)NeverCalled,encoding)); objc_registerClassPair(cls); return cls;
}
@interface NoSendHost : NSObject
@property(nonatomic) NSUInteger inserts,sends;
- (void)AddLocalMsg:(id)a MsgWrap:(id)b;
- (void)ResendVoiceMsg:(id)a MsgWrap:(id)b;
@end
@implementation NoSendHost
- (void)AddLocalMsg:(id)a MsgWrap:(id)b { self.inserts++; }
- (void)ResendVoiceMsg:(id)a MsgWrap:(id)b { self.sends++; }
@end
static NSData *Fixture(void) {
    NSString *text=[NSString stringWithContentsOfFile:@"tests/fixtures/synthetic.amr.hex" encoding:NSUTF8StringEncoding error:NULL];
    NSString *hex=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
    NSMutableData *data=[NSMutableData data];
    for(NSUInteger i=0;i<hex.length;i+=2) { unsigned n=0; CHECK([[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i,2)]] scanHexInt:&n]); unsigned char b=n; [data appendBytes:&b length:1]; }
    return data;
}
static void Accepted(Class cls, uint64_t n) {
    NSUInteger before=calls;
    @autoreleasepool { __weak id weak; @autoreleasepool { id result=WUCreateMessage(cls,n,@"account"); CHECK(result!=nil); weak=result; CHECK(calls==before+1 && seen==n && [seenAccount isEqual:@"account"]); } CHECK(weak==nil); }
    CHECK(live==0);
}
static void Rejected(Class cls, uint64_t n) {
    NSUInteger before=calls;
    @autoreleasepool { CHECK(WUCreateMessage(cls,n,@"account")==nil); }
    CHECK(calls==before); CHECK(live==0);
}
int main(void) { @autoreleasepool {
    Class classes[]={ConstructI.class,Constructq.class,Constructi.class,ConstructQ.class};
    for(unsigned i=0;i<4;i++) { CHECK(WUMessageCanConstruct(classes[i])); Accepted(classes[i],34); Accepted(classes[i],47); Accepted(classes[i],0); }
    Accepted(ConstructI.class,UINT_MAX); Rejected(ConstructI.class,(uint64_t)UINT_MAX+1);
    Accepted(Constructi.class,INT_MAX); Rejected(Constructi.class,(uint64_t)INT_MAX+1);
    Accepted(Constructq.class,LLONG_MAX); Rejected(Constructq.class,(uint64_t)LLONG_MAX+1);
    Accepted(ConstructQ.class,UINT64_MAX); Accepted(ConstructQ.class,((uint64_t)1<<63)+47);
    const char *bad[]={"I@:I@","v@:I@","@@:I","@@:I@@","@@:II","@@:@@","@@:f@","@@:d@","@@:B@","@@:^i@","@@:s@","@@:C@","@@:I#","#@:I@"};
    for(unsigned i=0;i<sizeof(bad)/sizeof(*bad);i++) { Class cls=BadShape(bad[i]); CHECK(!WUMessageCanConstruct(cls)); Rejected(cls,34); }
    const char *mismatches[]={"@@:q@","I@:I@","@@:II","@@:I","@@:I@@"};
    for(unsigned i=0;i<sizeof(mismatches)/sizeof(*mismatches);i++) { spoof=mismatches[i]; CHECK(!WUMessageCanConstruct(ClassMismatch.class)); Rejected(ClassMismatch.class,47); Rejected(InstanceMismatch.class,34); }
    Rejected(SignatureThrows.class,34); Rejected(Nil,34); Rejected(NSObject.class,34);
    @autoreleasepool { CHECK(!WUCreateMessage(ConstructI.class,34,@"")); CHECK(!WUCreateMessage(ConstructI.class,34,nil)); } CHECK(live==0);
    for(initMode=1;initMode<=3;initMode++) {
        NSUInteger before=calls;
        @autoreleasepool {
            __weak id weak;
            @autoreleasepool { id result=WUCreateMessage(SpecialInit.class,34,@"account"); weak=result; CHECK(initMode==3?[result isKindOfClass:Replacement.class]:result==nil); CHECK(calls==before+1); }
            CHECK(weak==nil);
        }
        CHECK(live==0);
    }
    NSData *data=Fixture(); NoSendHost *host=[NoSendHost new];
    for(initMode=1;initMode<=3;initMode++) { @autoreleasepool {
        WUVoiceForwardOperation *op=[[WUVoiceForwardOperation alloc] initWithData:data account:@"account" target:@"recipient"];
        CHECK([[op submitWithManager:host audioSender:host messageClass:SpecialInit.class current:^BOOL{ return YES; }] hasPrefix:@"失败"]);
        CHECK(host.inserts==0 && host.sends==0);
        [op submitWithManager:host audioSender:host messageClass:SpecialInit.class current:^BOOL{ return YES; }]; CHECK(host.inserts==0 && host.sends==0);
    } CHECK(live==0); }
    printf("Message construction production ABI/range/ARC/exception tests: %lu assertions passed\n",(unsigned long)checks);
} return 0; }
