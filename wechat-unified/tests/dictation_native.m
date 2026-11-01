#import "WU.h"
#import "WUDictation.h"
#include <string.h>
#include <stdlib.h>
static NSMutableDictionary<NSString *, NSString *> *hooks;
#include "dictation_core_hooks.inc"
// Real ObjC runtime + exact production WUHook/WUMatches and complete production module.
#include "../Sources/WUDictation.m"
static NSUInteger checks, failures;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { failures++; NSLog(@"FAIL dictation line %d: %s",__LINE__,#__VA_ARGS__); } } while(0)
static BOOL enabled=YES, hide=NO, guard=YES;
static NSString *account=@"A", *session=@"chat-A";
static NSUInteger generation=1;
NSString *const WUChanged=@"fixture.changed";
NSString *const UIApplicationWillResignActiveNotification=@"fixture.resign";
NSString *const UIApplicationDidBecomeActiveNotification=@"fixture.active";
BOOL WUEnabled(NSString *key) { return enabled && ([key isEqual:WUDictationHideKey]?hide:([key isEqual:WUDictationGuardKey]?guard:NO)); }
NSString *WUCurrentAccount(void) { return account; }
NSString *WUChatSession(UIViewController *owner) { return owner?session:nil; }
NSUInteger WUContextGeneration(void) { return generation; }
@implementation UIResponder @end
@implementation UIView
- (instancetype)init { if((self=[super init])) { _alpha=1; _userInteractionEnabled=YES; _bounds=CGRectMake(0,0,30,30); _subviews=[NSMutableArray array]; } return self; }
- (UIWindow *)window { return [self isKindOfClass:UIWindow.class]?(id)self:self.superview.window; }
- (void)addSubview:(UIView *)v { [v removeFromSuperview]; [self.subviews addObject:v]; v.superview=self; v.nextResponder=self; }
- (void)removeFromSuperview { [self.superview.subviews removeObject:self]; self.superview=nil; self.nextResponder=nil; }
- (BOOL)isDescendantOfView:(UIView *)v { for(UIView *p=self;p;p=p.superview) if(p==v) return YES; return NO; }
- (CGRect)convertRect:(CGRect)r toView:(UIView *)v { r.origin=self.frame.origin; return r; }
- (BOOL)becomeFirstResponder { self.focusCalls++; self.firstResponder=YES; return YES; }
- (void)setNeedsLayout {}
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { return self; }
- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e {}
- (void)touchesMoved:(NSSet *)t withEvent:(UIEvent *)e {}
- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {}
- (void)touchesCancelled:(NSSet *)t withEvent:(UIEvent *)e {}
@end
@implementation UIImageView @end
@implementation UIWindow @end
@implementation UIViewController @end
@implementation UINavigationController @end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *a; if(!a) a=[UIApplication new]; return a; }
@end
@implementation UITouch
- (CGPoint)locationInView:(UIView *)v { return self.point; }
@end
@implementation UIEvent @end
@interface BaseMsgContentViewController : UIViewController @end
@implementation BaseMsgContentViewController @end
@interface HostIcon : UIView
@property(nonatomic) NSUInteger hiddenCalls;
@end
@implementation HostIcon
- (void)setHidden:(BOOL)b { self.hiddenCalls++; [super setHidden:b]; }
@end
@interface DictationFixtureInput : UIView
@property(nonatomic, strong) UIView *icon, *hitResult;
@property(nonatomic) NSUInteger getters, hits, begins, moves, ends, cancels;
@property(nonatomic, copy) void (^endAction)(DictationFixtureInput *, NSSet *, UIEvent *);
- (id)dictationIcon;
@end
@implementation DictationFixtureInput
- (id)dictationIcon { self.getters++; return self.icon; }
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { self.hits++; return self.hitResult; }
- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e { self.begins++; }
- (void)touchesMoved:(NSSet *)t withEvent:(UIEvent *)e { self.moves++; }
- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e { self.ends++; if(self.endAction) self.endAction(self,t,e); }
- (void)touchesCancelled:(NSSet *)t withEvent:(UIEvent *)e { self.cancels++; }
@end
@interface Scene : NSObject
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) BaseMsgContentViewController *chat;
@property(nonatomic, strong) DictationFixtureInput *input;
@property(nonatomic, strong) UITouch *touch;
@property(nonatomic, strong) UIEvent *event;
@end
@implementation Scene
- (instancetype)init { if((self=[super init])) {
    enabled=YES; hide=NO; guard=YES; account=@"A"; session=@"chat-A";
    UIApplication.sharedApplication.applicationState=UIApplicationStateActive;
    _window=[UIWindow new]; _window.keyWindow=YES;
    _chat=[BaseMsgContentViewController new]; _input=[NSClassFromString(@"MMGrowTextView") new];
    [_window addSubview:_input]; _input.nextResponder=_chat;
    _input.icon=[UIImageView new]; [_input addSubview:_input.icon]; _input.hitResult=_input.icon;
    _touch=[UITouch new]; _touch.point=CGPointMake(5,5); _touch.phase=UITouchPhaseBegan;
    _event=[UIEvent new]; _event.allTouches=[NSSet setWithObject:_touch];
} return self; }
@end
static void Begin(Scene *f) {
    f.touch.timestamp=0; f.touch.phase=UITouchPhaseBegan;
    UIView *hit=[f.input hitTest:f.touch.point withEvent:f.event]; CHECK(hit==f.input);
    f.touch.view=hit; [f.input touchesBegan:f.event.allTouches withEvent:f.event];
}
static void End(Scene *f, double time) {
    f.touch.phase=UITouchPhaseEnded; f.touch.timestamp=time;
    [f.input touchesEnded:[NSSet setWithObject:f.touch] withEvent:f.event];
}
static void Changed(void) { [NSNotificationCenter.defaultCenter postNotificationName:WUChanged object:nil]; }
static void ForeignBegan(DictationFixtureInput *v, SEL s, NSSet *t, UIEvent *e) { v.begins++; }
static void WrongGetter(id v,SEL s) {}
static int Finish(NSString *mode) {
    printf("DICTATION_NATIVE %s: %lu checks, %lu failures (production module + Core hooks; UIKit mock)\n",mode.UTF8String,(unsigned long)checks,(unsigned long)failures);
    return failures?1:0;
}
int main(int argc, const char **argv) { @autoreleasepool {
    hooks=[NSMutableDictionary dictionary];
    NSString *mode=argc>1?@(argv[1]):@"normal";
    Class runtimeInput=objc_allocateClassPair(DictationFixtureInput.class,"MMGrowTextView",0);
    CHECK(runtimeInput!=Nil);
    if([mode isEqual:@"bad-abi"]) CHECK(class_addMethod(runtimeInput,@selector(dictationIcon),(IMP)WrongGetter,"v@:"));
    objc_registerClassPair(runtimeInput);
    if([mode isEqual:@"bad-abi"]) {
        WUInstallDictation(); CHECK(!ready && !iconOriginal && !beganOriginal);
        CHECK(method_getImplementation(class_getInstanceMethod(runtimeInput,@selector(dictationIcon)))==(IMP)WrongGetter);
        return Finish(mode);
    }
    if([mode isEqual:@"conflict"]) {
        IMP foreignOriginal=NULL;
        CHECK(WUHook(@"MMGrowTextView",@"touchesBegan:withEvent:",NO,"v",@[@"@",@"@"],(IMP)ForeignBegan,&foreignOriginal));
        WUInstallDictation(); CHECK(!ready && !beganOriginal && iconOriginal && endedOriginal);
        IMP first=iconOriginal; WUInstallDictation(); CHECK(!ready && iconOriginal==first && !beganOriginal);
        Scene *f=[Scene new]; CHECK([f.input dictationIcon]==f.input.icon && f.input.getters==1);
        CHECK([f.input hitTest:CGPointMake(5,5) withEvent:f.event]==f.input.icon);
        [f.input touchesBegan:f.event.allTouches withEvent:f.event]; End(f,0.1);
        [f.input touchesCancelled:f.event.allTouches withEvent:f.event];
        CHECK(f.input.begins==1 && f.input.ends==1 && f.input.cancels==1 && f.input.focusCalls==0);
        CHECK(!WUDictationAvailable(WUDictationGuardKey)); return Finish(mode);
    }
    WUInstallDictation(); CHECK(ready && movedOriginal && cancelOriginal);
    IMP saved=iconOriginal; WUInstallDictation(); CHECK(ready && iconOriginal==saved);
    CHECK(!WUDictationAvailable(@"unknown"));
    Scene *f=[Scene new]; Begin(f); End(f,0.349);
    CHECK(f.input.focusCalls==1 && f.input.begins==1 && f.input.ends==1 && f.input.hits==1);
    End(f,0.349); CHECK(f.input.focusCalls==1 && f.input.ends==2);
    CHECK(WUDictationAvailable(WUDictationGuardKey) && WUDictationAvailable(WUDictationHideKey));
    for(NSNumber *duration in @[@0.35,@0.5,@(-0.01),@(NAN),@(INFINITY)]) {
        f=[Scene new]; Begin(f); End(f,duration.doubleValue); CHECK(f.input.focusCalls==0 && f.input.ends==1);
    }
    f=[Scene new]; f.input.firstResponder=YES;
    CHECK([f.input hitTest:f.touch.point withEvent:f.event]==f.input.icon && f.input.hits==1);
    f.input.firstResponder=NO; f.input.hitResult=f.input;
    CHECK([f.input hitTest:f.touch.point withEvent:f.event]==f.input); End(f,0.1); CHECK(f.input.focusCalls==0);
    f=[Scene new]; guard=NO; CHECK([f.input hitTest:f.touch.point withEvent:f.event]==f.input.icon);
    End(f,0.1); CHECK(f.input.focusCalls==0);
    f=[Scene new]; Begin(f); [f.input touchesCancelled:f.event.allTouches withEvent:f.event]; End(f,0.1);
    CHECK(f.input.cancels==1 && f.input.ends==1 && f.input.focusCalls==0);
    f=[Scene new]; Begin(f); f.touch.point=CGPointMake(60,60); f.touch.phase=UITouchPhaseMoved;
    [f.input touchesMoved:f.event.allTouches withEvent:f.event]; f.touch.point=CGPointMake(5,5); End(f,0.1);
    CHECK(f.input.moves==1 && f.input.focusCalls==0);
    f=[Scene new]; Begin(f); f.touch.phase=UITouchPhaseMoved;
    [f.input touchesMoved:f.event.allTouches withEvent:f.event]; End(f,0.1); CHECK(f.input.focusCalls==1);
    f=[Scene new]; Begin(f); f.event.allTouches=[NSSet setWithObjects:f.touch,[UITouch new],nil];
    [f.input touchesMoved:[NSSet setWithObject:f.touch] withEvent:f.event];
    f.event.allTouches=[NSSet setWithObject:f.touch]; End(f,0.1); CHECK(f.input.focusCalls==0);
    f=[Scene new]; f.event.allTouches=[NSSet setWithObjects:f.touch,[UITouch new],nil];
    CHECK([f.input hitTest:f.touch.point withEvent:f.event]==f.input.icon);
    f=[Scene new]; Begin(f); [f.input touchesBegan:f.event.allTouches withEvent:f.event]; End(f,0.1);
    CHECK(f.input.begins==2 && f.input.focusCalls==0);
    f=[Scene new]; CHECK([f.input hitTest:f.touch.point withEvent:f.event]==f.input);
    CHECK([f.input hitTest:f.touch.point withEvent:f.event]==f.input);
    f.touch.view=f.input; [f.input touchesBegan:f.event.allTouches withEvent:f.event]; End(f,0.1);
    CHECK(f.input.focusCalls==1 && f.input.hits==2 && f.input.begins==1 && f.input.ends==1);
    for(NSUInteger invalid=0; invalid<9; invalid++) {
        f=[Scene new]; Begin(f);
        switch(invalid) {
            case 0: account=@"B"; generation++; break;
            case 1: session=@"chat-B"; break;
            case 2: UIApplication.sharedApplication.applicationState=UIApplicationStateBackground; break;
            case 3: f.window.keyWindow=NO; break;
            case 4: guard=NO; Changed(); break;
            case 5: f.chat.presentedViewController=[UIViewController new]; break;
            case 6: [f.input removeFromSuperview]; WURefreshDictation(f.input); break;
            case 7: f.input.icon=[UIImageView new]; [f.input addSubview:f.input.icon]; break;
            case 8: [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil]; break;
        }
        End(f,0.1); CHECK(f.input.focusCalls==0 && f.input.ends==1);
    }
    for(NSUInteger action=0; action<5; action++) {
        f=[Scene new]; Begin(f);
        f.input.endAction=^(DictationFixtureInput *v,NSSet *touches,UIEvent *event) {
            v.endAction=nil;
            if(action==0) [v touchesEnded:touches withEvent:event];
            if(action==1) [v touchesCancelled:touches withEvent:event];
            if(action==2) { account=@"C"; generation++; WURefreshDictation(v); }
            if(action==3) { UITouch *t=event.allTouches.anyObject; t.phase=UITouchPhaseBegan; CHECK([v hitTest:t.point withEvent:event]==v.icon); }
            if(action==4) { v.icon=[UIImageView new]; [v addSubview:v.icon]; WURefreshDictation(v); }
        };
        End(f,0.1); CHECK(f.input.focusCalls==0 && f.input.ends==(action==0?2:1));
    }
    // No global UIKit hooks; UIImageView uses only the observed instance's alpha snapshot.
    IMP uiHidden=method_getImplementation(class_getInstanceMethod(UIView.class,@selector(setHidden:)));
    IMP imageHidden=method_getImplementation(class_getInstanceMethod(UIImageView.class,@selector(setHidden:)));
    f=[Scene new]; UIView *unrelated=[UIImageView new]; hide=YES;
    f.input.icon.alpha=0.8; WURefreshDictation(f.input);
    CHECK(f.input.icon.alpha==0 && !f.input.icon.hidden && unrelated.alpha==1 && !unrelated.hidden);
    f.input.icon.hidden=YES; hide=NO; Changed();
    CHECK(f.input.icon.hidden && f.input.icon.alpha==0.8);
    f.input.icon.hidden=NO; hide=YES; WURefreshDictation(f.input); f.input.icon.hidden=NO;
    hide=NO; WURefreshDictation(f.input); CHECK(!f.input.icon.hidden && f.input.icon.alpha==0.8);
    hide=YES; WURefreshDictation(f.input); f.input.icon.alpha=0.6; WURefreshDictation(f.input);
    hide=NO; WURefreshDictation(f.input); CHECK(f.input.icon.alpha==0.6);
    hide=YES; WURefreshDictation(f.input); UIView *old=f.input.icon; [old removeFromSuperview];
    f.input.icon=[UIImageView new]; [f.input addSubview:f.input.icon]; WURefreshDictation(f.input);
    CHECK(old.alpha==0.6 && f.input.icon.alpha==0);
    [f.input removeFromSuperview]; WURefreshDictation(f.input); CHECK(f.input.icon.alpha==1);
    CHECK(method_getImplementation(class_getInstanceMethod(UIView.class,@selector(setHidden:)))==uiHidden);
    CHECK(method_getImplementation(class_getInstanceMethod(UIImageView.class,@selector(setHidden:)))==imageHidden);
    // Custom app icon tracks all host setHidden writes, including same-value writes while masked.
    f=[Scene new]; [f.input.icon removeFromSuperview]; HostIcon *host=[HostIcon new];
    f.input.icon=host; [f.input addSubview:host]; f.input.hitResult=host; hide=YES; WURefreshDictation(f.input);
    CHECK(maskedClass==HostIcon.class && hiddenOriginal && host.hidden && host.alpha==1);
    NSUInteger writes=host.hiddenCalls; host.hidden=NO;
    CHECK(host.hidden && host.hiddenCalls==writes+1); hide=NO; Changed(); CHECK(!host.hidden);
    hide=YES; WURefreshDictation(f.input); host.hidden=YES; hide=NO; Changed(); CHECK(host.hidden);
    host.hidden=NO; hide=YES; WURefreshDictation(f.input);
    // Configuration changes before delivery of its notification must not restore the old mask.
    hide=NO; host.hidden=YES; WURefreshDictation(f.input); CHECK(host.hidden);
    host.hidden=NO; hide=YES; WURefreshDictation(f.input); [host removeFromSuperview]; host.hidden=NO;
    CHECK(!host.hidden); WURefreshDictation(f.input); CHECK(!host.hidden);
    [f.input addSubview:host]; WURefreshDictation(f.input); host.hidden=YES;
    account=@"B"; generation++; WURefreshDictation(f.input); hide=NO; Changed(); CHECK(host.hidden);
    host.hidden=NO; hide=YES; WURefreshDictation(f.input); enabled=NO; Changed(); CHECK(!host.hidden);
    enabled=YES; hide=YES; WURefreshDictation(f.input); [f.input removeFromSuperview];
    WURefreshDictation(f.input); CHECK(!host.hidden);
    // Weak owner disappearing still restores tracked icons on the next configuration refresh.
    @autoreleasepool { Scene *ephemeral=[Scene new]; ephemeral.input.icon=host;
        [ephemeral.input addSubview:host]; hide=YES; WURefreshDictation(ephemeral.input); CHECK(host.hidden); }
    hide=NO; Changed(); CHECK(!host.hidden);
    return Finish(mode);
} }
