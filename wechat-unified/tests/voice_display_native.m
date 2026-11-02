#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "VoiceDisplay.h"
#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include "voice_display_matches.inc"
static unsigned hooks;
BOOL WUHook(NSString *name,NSString *selector,BOOL meta,const char *ret,NSArray *args,IMP replacement,IMP *original) {
    (void)meta;
    Class cls=NSClassFromString(name); SEL sel=NSSelectorFromString(selector);
    Method method=class_getInstanceMethod(cls,sel);
    if(!WUMatches(method,ret,args)) return NO;
    *original=method_getImplementation(method); hooks++;
    if(!class_addMethod(cls,sel,replacement,method_getTypeEncoding(method))) method_setImplementation(class_getInstanceMethod(cls,sel),replacement);
    return YES;
}
@interface MockMessage : NSObject
@property(nonatomic) unsigned stored, kind, writes;
@end
@implementation MockMessage @end
static unsigned ReadMS(MockMessage *m,SEL cmd) { return m.stored; }
static uint64_t BadMS(MockMessage *m,SEL cmd) { return m.stored; }
static unsigned Kind(MockMessage *m,SEL cmd) { return m.kind; }
static void WriteMS(MockMessage *m,SEL cmd,unsigned ms) { m.stored=ms; m.writes++; }
static unsigned Read(id m) { return ((unsigned(*)(id,SEL))objc_msgSend)(m,NSSelectorFromString(@"m_uiVoiceTime")); }
@interface MockModel : NSObject
@property(nonatomic,strong) id messageWrap;
@property(nonatomic) BOOL throws;
- (NSString *)voiceTimeStirng;
@end
@implementation MockModel
- (NSString *)voiceTimeStirng {
    if(self.throws) [NSException raise:@"mock" format:@"original getter"];
    return [NSString stringWithFormat:@"host:%u",Read(self.messageWrap)];
}
@end
@interface UIView : NSObject
@property(nonatomic,strong) MockModel *viewModel;
@property(nonatomic,strong) id m_secLabel;
@property(nonatomic) NSUInteger layouts;
@property(nonatomic,copy) void (^body)(void);
- (void)setNeedsLayout;
@end
@implementation UIView
- (void)setNeedsLayout { self.layouts++; }
@end
@interface UILabel : NSObject
@property(nonatomic,copy) NSString *text;
@property(nonatomic,weak) UIView *owner;
- (BOOL)isDescendantOfView:(UIView *)v;
@end
@implementation UILabel
- (BOOL)isDescendantOfView:(UIView *)v { return self.owner==v; }
@end
static BOOL real=YES, carry=YES;
static BOOL Option(NSString *key) { return [key isEqual:@"voiceCarry"]?carry:real; }
static id Object(id object,NSString *key) { @try { return [object valueForKey:key]; } @catch(NSException *e) { return nil; } }
static id CallObject(id object,NSString *key) {
    @try { return ((id(*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(key)); } @catch(NSException *e) { return nil; }
}
@interface MockPathMessage : MockMessage
- (NSString *)getVoicePath;
@end
@implementation MockPathMessage
- (NSString *)getVoicePath { return @"/mock/voice"; }
@end
@interface WUVoiceBinding : NSObject
@property(nonatomic,strong) UIView *cell;
@property(nonatomic,strong) id model,message;
@property(nonatomic,strong) WUVoiceDisplay *display;
@property(nonatomic,weak) UILabel *hostLabel;
@property(nonatomic,weak) id labelModel;
@property(nonatomic,copy) NSString *appliedText,*savedText,*sourceVersion,*path;
@property(nonatomic,strong) NSDictionary *audio;
@property(nonatomic) NSUInteger generation,request;
@property(nonatomic) uint64_t cacheVersion;
@property(nonatomic) BOOL live;
- (BOOL)valid;
- (void)clearDisplay;
- (void)refreshDisplay;
@end
@implementation WUVoiceBinding
- (BOOL)valid { return self.live && self.cell.viewModel==self.model && [self.model messageWrap]==self.message; }
/* Exact production clearDisplay/refreshDisplay bodies, extracted by the runner. */
#include "voice_display_binding.inc"
@end
static char bindingKey;
static IMP layoutOriginal;
static void Bind(id cell) { WUVoiceBinding *b=objc_getAssociatedObject(cell,&bindingKey); [b refreshDisplay]; }
static void HostLayout(UIView *cell, SEL cmd) { if(cell.body) cell.body(); }
#include "voice_display_layout.inc"
static WUVoiceBinding *Binding(MockModel *model) {
    WUVoiceBinding *b=[WUVoiceBinding new]; b.model=model; b.message=model.messageWrap;
    b.cell=[UIView new]; b.cell.viewModel=model;
    objc_setAssociatedObject(b.cell,&bindingKey,b,OBJC_ASSOCIATION_RETAIN_NONATOMIC); layoutOriginal=(IMP)HostLayout;
    UILabel *label=[UILabel new]; label.owner=b.cell; label.text=[model voiceTimeStirng]; b.cell.m_secLabel=label;
    b.path=@"/mock/voice"; b.sourceVersion=@"v1"; b.cacheVersion=1; b.generation=1; b.request=1;
    b.audio=@{@"duration":@2500}; b.live=YES; [b refreshDisplay]; return b;
}
int main(int argc,const char **argv) { @autoreleasepool {
    NSString *mode=argc>1?@(argv[1]):@"normal";
    Class message=objc_allocateClassPair(MockPathMessage.class,"CMessageWrap",0);
    if(![mode isEqual:@"missing"])
        class_addMethod(message,NSSelectorFromString(@"m_uiVoiceTime"),[mode isEqual:@"bad-type"]?(IMP)BadMS:(IMP)ReadMS,[mode isEqual:@"bad-type"]?"Q@:":"I@:");
    class_addMethod(message,NSSelectorFromString(@"m_uiMessageType"),(IMP)Kind,"I@:");
    class_addMethod(message,NSSelectorFromString(@"setM_uiVoiceTime:"),(IMP)WriteMS,"v@:I");
    objc_registerClassPair(message);
    Class model=objc_allocateClassPair(MockModel.class,"VoiceMessageViewModel",0); objc_registerClassPair(model);
    WUInstallVoiceDisplay(); WUInstallVoiceDisplay();
    MockMessage *m=[message new]; m.stored=9000; m.kind=34;
    MockModel *vm=[model new]; vm.messageWrap=m;
    if(![mode isEqual:@"normal"]) {
        assert(hooks==0); WUVoiceDisplay *d=[WUVoiceDisplay new];
        assert(![d applyModel:vm message:m milliseconds:2500]);
        puts("PASS native: unsupported ABI/missing getter falls back without hooks"); return 0;
    }
    assert(hooks==2);
    NSString *fixture=[NSHomeDirectory() stringByAppendingPathComponent:[@".wu-voice-display-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    @try {
        assert([[@"000000000000" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:fixture options:NSDataWritingAtomic error:NULL]);
        NSString *v1=WUVoiceDisplaySourceVersion(fixture); assert(v1.length);
        assert([[@"111111111111" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:fixture options:NSDataWritingAtomic error:NULL]);
        assert(![v1 isEqual:WUVoiceDisplaySourceVersion(fixture)]);
    } @finally { [NSFileManager.defaultManager removeItemAtPath:fixture error:NULL]; }
    assert(!WUVoiceDisplaySourceVersion(fixture) && !WUVoiceDisplaySourceVersion(@"relative"));
    WUVoiceBinding *b=Binding(vm); UILabel *label=b.cell.m_secLabel;
    assert([label.text isEqual:@"0:02"] && [[vm voiceTimeStirng] isEqual:@"0:02"]);
    assert(Read(m)==9000 && m.stored==9000 && m.writes==0);
    __block double width=0;
    b.cell.body=^{ width=40+Read(m)/1000.0; };
    Layout(b.cell,NSSelectorFromString(@"layoutSubviews"));
    assert(width==42.5 && b.display.layoutConsumedDuration);
    [b.display layout:^{ (void)[vm voiceTimeStirng]; }];
    assert(b.display.layoutObserved && !b.display.layoutConsumedDuration);
    [b.display layout:^{
        WUVoiceDisplayLayout(nil,^{ assert(Read(m)==9000); });
        assert(Read(m)==2500);
    }];
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(0,0),^{
        assert(!NSThread.isMainThread);
        assert(Read(m)==9000 && [[vm voiceTimeStirng] isEqual:@"host:9000"]);
        dispatch_semaphore_signal(done);
    });
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    m.stored=12000; real=NO; [b refreshDisplay];
    assert([label.text isEqual:@"host:12000"] && [[vm voiceTimeStirng] isEqual:label.text]);
    assert(Read(m)==12000);
    b.cell.body=^{ width=40+Read(m)/1000.0; };
    Layout(b.cell,NSSelectorFromString(@"layoutSubviews")); assert(width==52);
    real=YES; [b refreshDisplay];
    MockModel *sameMessageModel=[model new]; sameMessageModel.messageWrap=m;
    assert([[sameMessageModel voiceTimeStirng] isEqual:@"host:12000"]);
    b.request++;
    assert([[vm voiceTimeStirng] isEqual:@"host:12000"]); /* Stale same-message async lease. */
    [b refreshDisplay]; b.cacheVersion++; assert([[vm voiceTimeStirng] isEqual:@"host:12000"]);
    [b refreshDisplay]; b.generation++; assert([[vm voiceTimeStirng] isEqual:@"host:12000"]);
    [b refreshDisplay]; b.live=NO; assert([[vm voiceTimeStirng] isEqual:@"host:12000"]); b.live=YES;
    MockMessage *other=[message new]; other.stored=7000; other.kind=34;
    MockModel *newModel=[model new]; newModel.messageWrap=other;
    b.cell.viewModel=newModel; [b clearDisplay];
    assert([label.text isEqual:@"host:7000"] && [[vm voiceTimeStirng] isEqual:@"host:12000"]);
    b.cell.viewModel=vm; [b refreshDisplay]; label.text=@"host-updated"; [b clearDisplay];
    assert([label.text isEqual:@"host-updated"]); /* Do not clobber a new host-owned label. */
    [b refreshDisplay]; vm.throws=YES; [b clearDisplay];
    assert([label.text isEqual:@"host-updated"]); vm.throws=NO;
    [b refreshDisplay];
    b.cell.body=^{ [NSException raise:@"mock" format:@"layout"]; };
    @try { Layout(b.cell,NSSelectorFromString(@"layoutSubviews")); assert(0); }
    @catch(NSException *e) { assert(Read(m)==12000 && [label.text isEqual:@"host:12000"]); }
    b.cell.body=nil;
    [b refreshDisplay]; m.kind=1; [b refreshDisplay]; assert(!b.appliedText); m.kind=34;
    b.audio=@{@"duration":@(NAN)}; [b refreshDisplay]; assert(!b.appliedText);
    b.audio=@{@"duration":@61001}; [b refreshDisplay];
    assert([label.text isEqual:@"1:01"]);
    [b.display layout:^{ assert(Read(m)==60000); }];
    carry=NO; [b refreshDisplay]; assert([label.text isEqual:@"61秒"]); carry=YES;
    assert(Read(m)==12000 && m.writes==0 && other.writes==0);
    [b clearDisplay]; assert([label.text isEqual:@"host:12000"]);
    puts("PASS native: original label/model, host bubble input, off/reuse/async/cache/generation, latest host, exceptions, no payload setter");
} return 0; }
