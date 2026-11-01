#import "WU.h"
#import "VoiceLogic.h"
#import "VoiceAudio.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>
static BOOL installed;
static IMP layoutOriginal, playingOriginal, windowOriginal;
static char bindingKey;
static BOOL Option(NSString *key) { id v=WUValue(key); return v ? [v boolValue] : ![key isEqual:@"voiceCountdown"]; }
static id Object(id obj, NSString *key) {
    @try { return obj ? [obj valueForKey:key] : nil; } @catch(NSException *e) { return nil; }
}
static BOOL Signature(id obj, NSString *name, const char *ret, NSArray *args) {
    return obj && WUMatches(class_getInstanceMethod(object_getClass(obj),NSSelectorFromString(name)),ret,args);
}
static id CallObject(id obj, NSString *name) {
    if(!Signature(obj,name,"@",@[])) return nil;
    @try { return ((id(*)(id,SEL))objc_msgSend)(obj,NSSelectorFromString(name)); } @catch(NSException *e) { return nil; }
}
static id Facade(void) {
    id context=CallObject(NSClassFromString(@"MMContext"),@"currentContext");
    Class cls=NSClassFromString(@"MsgPlayingFacade");
    if(!cls || (!Signature(context,@"getService:","@",@[@"#"]) && !Signature(context,@"getService:","@",@[@"@"]))) return nil;
    @try { return ((id(*)(id,SEL,Class))objc_msgSend)(context,NSSelectorFromString(@"getService:"),cls); } @catch(NSException *e) { return nil; }
}
static BOOL ClockReady(id f) { return Signature(f,@"currentPlayTime","I",@[]) || Signature(f,@"currentPlayTime","i",@[]); }
static double ClockMS(id f) {
    @try {
        if(Signature(f,@"currentPlayTime","I",@[])) return ((unsigned(*)(id,SEL))objc_msgSend)(f,NSSelectorFromString(@"currentPlayTime"));
        if(Signature(f,@"currentPlayTime","i",@[])) return ((int(*)(id,SEL))objc_msgSend)(f,NSSelectorFromString(@"currentPlayTime"));
    } @catch(NSException *e) {} return -1;
}
static BOOL SeekReady(id f) { return Signature(f,@"seekToTime:","v",@[@"I"]); }
static BOOL Playing(id vm) {
    if(!Signature(vm,@"isPlaying",@encode(BOOL),@[])) return NO;
    @try { return ((BOOL(*)(id,SEL))objc_msgSend)(vm,NSSelectorFromString(@"isPlaying")); } @catch(NSException *e) { return NO; }
}
@class WUVoiceBinding;
@interface WUVoiceWave : UIView <UIGestureRecognizerDelegate>
@property(nonatomic,weak) WUVoiceBinding *binding;
@property(nonatomic,strong) UILabel *time;
@property(nonatomic,strong) NSArray<NSNumber *> *peaks;
@property(nonatomic) double progress, phase, preview;
@property(nonatomic) BOOL pulsing, dragging;
@end
@interface WUVoiceBinding : NSObject
@property(nonatomic,weak) UIView *cell;
@property(nonatomic,weak) id model, message;
@property(nonatomic,copy) NSString *account, *path;
@property(nonatomic) NSUInteger generation, request;
@property(nonatomic) BOOL loading, attempted;
@property(nonatomic,strong) WUVoiceWave *wave;
@property(nonatomic,strong) NSDictionary *audio;
@property(nonatomic,strong) NSProgress *cancellation;
- (BOOL)valid;
- (void)clear;
- (void)refresh;
- (BOOL)canSeek;
- (void)seek:(double)fraction;
@end
@interface WUVoiceClock : NSObject
@property(nonatomic,strong) CADisplayLink *link;
@property(nonatomic,weak) id model, facade;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,copy) NSString *account;
- (void)stop;
- (void)tick:(CADisplayLink *)link;
@end
static WUVoiceClock *clockOwner;
static NSHashTable<WUVoiceBinding *> *bindings;
static dispatch_queue_t audioQueue;
static BOOL Foreground(void) { return UIApplication.sharedApplication.applicationState==UIApplicationStateActive; }
@implementation WUVoiceWave
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor; self.isAccessibilityElement=YES;
        self.time=[UILabel new]; self.time.font=[UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium];
        self.time.textAlignment=NSTextAlignmentRight; self.time.textColor=UIColor.labelColor; [self addSubview:self.time];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        pan.maximumNumberOfTouches=1; pan.delegate=self; pan.cancelsTouchesInView=NO; [self addGestureRecognizer:pan];
    } return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.time.frame=CGRectMake(0,0,self.bounds.size.width,12); }
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)event { return [self.binding canSeek] && [super pointInside:p withEvent:event]; }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    CGPoint v=[(UIPanGestureRecognizer *)g velocityInView:self]; return [self.binding canSeek] && fabs(v.x)>fabs(v.y);
}
- (void)pan:(UIPanGestureRecognizer *)g {
    if(![self.binding canSeek]) { self.dragging=NO; [self setNeedsDisplay]; return; }
    if(g.state==UIGestureRecognizerStateBegan || g.state==UIGestureRecognizerStateChanged) {
        self.dragging=YES; self.preview=fmax(0,fmin(1,[g locationInView:self].x/fmax(1,self.bounds.size.width)));
    } else {
        BOOL commit=g.state==UIGestureRecognizerStateEnded && self.dragging; self.dragging=NO;
        if(commit) [self.binding seek:self.preview];
    } [self setNeedsDisplay];
}
- (void)accessibilityIncrement { if([self.binding canSeek]) [self.binding seek:self.progress+0.05]; }
- (void)accessibilityDecrement { if([self.binding canSeek]) [self.binding seek:self.progress-0.05]; }
- (void)drawRect:(CGRect)rect {
    CGContextRef c=UIGraphicsGetCurrentContext(); if(!c) return;
    CGFloat w=self.bounds.size.width, h=self.bounds.size.height-14;
    if(h<=0) return;
    for(NSUInteger i=0;i<self.peaks.count;i++) {
        double a=self.peaks[i].doubleValue;
        // Pulse changes only the measured bar's scale; silence remains silence.
        if(self.pulsing && !UIAccessibilityIsReduceMotionEnabled()) a*=0.82+0.18*sin(self.phase+i*0.35);
        CGFloat x=(i+0.5)*w/self.peaks.count, height=a*h;
        UIColor *color=((i+0.5)/self.peaks.count<=self.progress)?UIColor.systemGreenColor:UIColor.secondaryLabelColor;
        CGContextSetStrokeColorWithColor(c,color.CGColor); CGContextSetLineWidth(c,2);
        CGContextMoveToPoint(c,x,14+(h-height)/2); CGContextAddLineToPoint(c,x,14+(h+height)/2); CGContextStrokePath(c);
    }
    if(self.dragging) {
        CGContextSetStrokeColorWithColor(c,UIColor.systemOrangeColor.CGColor); CGContextSetLineWidth(c,1);
        CGContextMoveToPoint(c,self.preview*w,12); CGContextAddLineToPoint(c,self.preview*w,self.bounds.size.height); CGContextStrokePath(c);
    }
}
@end
@implementation WUVoiceBinding
- (BOOL)valid {
    id vm=Object(self.cell,@"viewModel");
    return WUVoiceLease(self.account,WUCurrentAccount(),self.generation,WUContextGeneration(),self.cell.window!=nil,WUEnabled(@"voiceProgress"),Foreground(),vm && vm==self.model && self.message && Object(vm,@"messageWrap")==self.message);
}
- (void)clear {
    [self.cancellation cancel]; self.request++; self.loading=NO; self.attempted=NO; self.audio=nil; self.path=nil;
    [self.wave removeFromSuperview]; self.wave=nil;
}
- (BOOL)canSeek {
    return [self valid] && Option(@"voiceSeek") && self.audio && clockOwner.model==self.model &&
        Playing(self.model) && clockOwner.facade==Facade() && SeekReady(clockOwner.facade);
}
- (void)seek:(double)fraction {
    if(![self canSeek]) return;
    id f=Facade(); if(f!=clockOwner.facade) return;
    uint32_t ms=WUVoiceSeekMS(fraction,[self.audio[@"duration"] doubleValue]);
    @try { ((void(*)(id,SEL,unsigned))objc_msgSend)(f,NSSelectorFromString(@"seekToTime:"),ms); } @catch(NSException *e) { [clockOwner stop]; }
    // Never set progress here: only a subsequent host clock read can confirm a seek.
}
- (void)refresh {
    if(![self valid]) { [self clear]; return; }
    UIView *bg=Object(self.cell,@"m_bgImageView");
    if(![bg isKindOfClass:UIView.class] || ![bg isDescendantOfView:self.cell] || bg.bounds.size.width<60 || bg.bounds.size.height<32) { [self clear]; return; }
    if(!self.wave) { self.wave=[[WUVoiceWave alloc] initWithFrame:CGRectZero]; self.wave.binding=self; }
    if(self.wave.superview!=self.cell) [self.cell addSubview:self.wave];
    CGRect area=[bg convertRect:bg.bounds toView:self.cell];
    self.wave.frame=CGRectMake(area.origin.x+8,CGRectGetMaxY(area)-30,MAX(0,area.size.width-16),28);
    id path=CallObject(self.message,@"getVoicePath");
    if(![path isKindOfClass:NSString.class]) path=nil;
    if(![self.path isEqual:path] && (self.path || path)) { [self.cancellation cancel]; self.request++; self.loading=NO; self.attempted=NO; self.audio=nil; self.path=[path copy]; }
    if(!self.attempted && path) {
        self.attempted=YES; self.loading=YES; NSUInteger request=++self.request; __weak WUVoiceBinding *weak=self;
        NSProgress *cancellation=[NSProgress progressWithTotalUnitCount:1]; self.cancellation=cancellation;
        dispatch_async(audioQueue,^{ @autoreleasepool {
            NSDictionary *audio=cancellation.cancelled?nil:WUVoiceDecodeCancellable(WUVoiceReadLocal(path),cancellation);
            dispatch_async(dispatch_get_main_queue(),^{
                WUVoiceBinding *b=weak; if(!b || b.request!=request || ![b valid]) return;
                b.loading=NO; b.audio=audio; [b refresh];
            });
        }});
    }
    BOOL active=clockOwner.model==self.model && Playing(self.model) && clockOwner.facade==Facade();
    double current=active?ClockMS(clockOwner.facade):0, total=[self.audio[@"duration"] doubleValue];
    if(current<0 || current>180000) { active=NO; current=0; }
    self.wave.progress=total>0?fmax(0,fmin(1,current/total)):0;
    self.wave.peaks=Option(@"voiceWaveform") && (active || Option(@"voiceAlways")) ? self.audio[@"peaks"] : nil;
    self.wave.pulsing=active && Option(@"voicePulse");
    NSString *text;
    if(total>0 && Option(@"voiceRealDuration")) {
        double shown=Option(@"voiceCountdown") && active?fmax(0,total-current):current;
        text=active?[NSString stringWithFormat:@"%@ / %@",WUVoiceTime(shown,Option(@"voiceCarry")),WUVoiceTime(total,Option(@"voiceCarry"))]:WUVoiceTime(total,Option(@"voiceCarry"));
    } else text=active?[NSString stringWithFormat:@"%@ · 总时长未解码",WUVoiceTime(current,Option(@"voiceCarry"))]:(self.loading?@"采样中…":@"此编码波形不可用");
    if(!Option(@"voiceRealDuration") && total>0) text=active?WUVoiceTime(current,Option(@"voiceCarry")):@"";
    self.wave.time.text=text;
    self.wave.accessibilityLabel=@"语音真实播放进度"; self.wave.accessibilityValue=text;
    self.wave.accessibilityTraits=[self canSeek]?UIAccessibilityTraitAdjustable:UIAccessibilityTraitStaticText;
    self.wave.accessibilityHint=[self canSeek]?@"左右拖动，松手定位；上下轻扫调整5%":@"当前不可拖动";
    [self.wave setNeedsDisplay];
}
@end
@implementation WUVoiceClock
- (void)stop {
    [self.link invalidate]; self.link=nil; self.model=nil; self.facade=nil; self.account=nil;
    for(WUVoiceBinding *b in bindings.allObjects) { b.wave.pulsing=NO; b.wave.dragging=NO; [b.wave setNeedsDisplay]; }
}
- (void)tick:(CADisplayLink *)link {
    id cell=Object(self.model,@"cellView"); WUVoiceBinding *b=objc_getAssociatedObject(cell,&bindingKey);
    if(![b valid] || b.model!=self.model || !Playing(self.model) || self.facade!=Facade() || self.generation!=WUContextGeneration() || ![self.account isEqual:WUCurrentAccount()]) {
        [self stop]; for(WUVoiceBinding *item in bindings.allObjects) [item refresh]; return;
    }
    b.wave.phase=link.timestamp*8; [b refresh];
}
@end
static void Bind(UIView *cell) {
    if(!NSThread.isMainThread) return;
    WUVoiceBinding *b=objc_getAssociatedObject(cell,&bindingKey);
    if(!WUEnabled(@"voiceProgress") || !Foreground() || !cell.window) { [b clear]; return; }
    id vm=Object(cell,@"viewModel"), msg=Object(vm,@"messageWrap");
    NSString *account=WUCurrentAccount(); NSUInteger gen=WUContextGeneration();
    if(!vm || !msg || !account.length) { [b clear]; return; }
    if(!b) { b=[WUVoiceBinding new]; b.cell=cell; objc_setAssociatedObject(cell,&bindingKey,b,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [bindings addObject:b]; }
    if(b.model!=vm || b.message!=msg || b.generation!=gen || ![b.account isEqual:account]) {
        [b clear]; b.model=vm; b.message=msg; b.generation=gen; b.account=account;
    }
    [b refresh];
}
static void Layout(id cell, SEL cmd) { ((void(*)(id,SEL))layoutOriginal)(cell,cmd); Bind(cell); }
static void Window(id cell, SEL cmd) {
    ((void(*)(id,SEL))windowOriginal)(cell,cmd);
    if(![cell window]) {
        WUVoiceBinding *b=objc_getAssociatedObject(cell,&bindingKey);
        if(b.model==clockOwner.model) [clockOwner stop]; [b clear];
    } else Bind(cell);
}
static void SetPlaying(id vm, SEL cmd, BOOL value) {
    ((void(*)(id,SEL,BOOL))playingOriginal)(vm,cmd,value);
    if(!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{ [clockOwner stop]; }); return; }
    if(!value) { if(clockOwner.model==vm) [clockOwner stop]; }
    else {
        [clockOwner stop];
        id f=Facade();
        if(installed && WUEnabled(@"voiceProgress") && Foreground() && ClockReady(f) && Playing(vm)) {
            clockOwner.account=WUCurrentAccount(); clockOwner.generation=WUContextGeneration();
            if(clockOwner.account.length) {
                clockOwner.model=vm; clockOwner.facade=f;
                clockOwner.link=[CADisplayLink displayLinkWithTarget:clockOwner selector:@selector(tick:)];
                clockOwner.link.preferredFramesPerSecond=15; [clockOwner.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
            }
        }
    }
    id cell=Object(vm,@"cellView"); if([cell isKindOfClass:UIView.class]) Bind(cell);
}
void WUCancelVoice(void) {
    if(!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{ WUCancelVoice(); }); return; }
    [clockOwner stop]; for(WUVoiceBinding *b in bindings.allObjects) [b clear];
}
BOOL WUVoiceAvailable(NSString *key) {
    if(!installed) return NO;
    id f=Facade(); return ClockReady(f) && (![key isEqual:@"voiceSeek"] || SeekReady(f));
}
void WUInstallVoice(void) {
    static dispatch_once_t once; dispatch_once(&once,^{
        bindings=[NSHashTable weakObjectsHashTable]; clockOwner=[WUVoiceClock new]; audioQueue=dispatch_queue_create("org.wechatunified.voice-decode",DISPATCH_QUEUE_SERIAL);
        for(NSString *name in @[UIApplicationWillResignActiveNotification,WUChanged]) [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            WUCancelVoice(); if([n.name isEqual:WUChanged] && Foreground() && WUEnabled(@"voiceProgress")) for(WUVoiceBinding *b in bindings.allObjects) Bind(b.cell);
        }];
    });
    if(installed) return;
    Class cell=NSClassFromString(@"VoiceMessageCellView"), vm=NSClassFromString(@"VoiceMessageViewModel");
    if(!WUMatches(class_getInstanceMethod(cell,@selector(layoutSubviews)),"v",@[]) ||
       !WUMatches(class_getInstanceMethod(cell,@selector(didMoveToWindow)),"v",@[]) ||
       !WUMatches(class_getInstanceMethod(vm,NSSelectorFromString(@"setIsPlaying:")),"v",@[@(@encode(BOOL))]) ||
       !WUMatches(class_getInstanceMethod(vm,NSSelectorFromString(@"isPlaying")),@encode(BOOL),@[])) return;
    BOOL a=WUHook(@"VoiceMessageCellView",@"layoutSubviews",NO,"v",@[],(IMP)Layout,&layoutOriginal);
    BOOL b=WUHook(@"VoiceMessageCellView",@"didMoveToWindow",NO,"v",@[],(IMP)Window,&windowOriginal);
    BOOL c=WUHook(@"VoiceMessageViewModel",@"setIsPlaying:",NO,"v",@[@(@encode(BOOL))],(IMP)SetPlaying,&playingOriginal);
    installed=a && b && c;
}
