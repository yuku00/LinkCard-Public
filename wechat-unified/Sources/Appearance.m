#import "WU.h"
#import "WUDictation.h"
#import <QuartzCore/QuartzCore.h>
#import "InteractionLogic.h"
#include <math.h>
static IMP inputWindow;
static BOOL pulseReady, inputSuspended;
static NSHashTable<UIView *> *inputs;
static NSTimer *pulseWatch;
static IMP inputLayout, noticeLayout, homeLayout;
static NSHashTable<UIView *> *decorated;
static NSHashTable<UITableView *> *tables;
static char layerKey, separatorKey;
static void Remove(UIView *v) { CALayer *l=objc_getAssociatedObject(v,&layerKey); [l removeAllAnimations]; [l removeFromSuperlayer]; objc_setAssociatedObject(v,&layerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void Decorate(UIView *v,NSString *key) {
    Remove(v);
    if(!WUEnabled(key) || !v.window || CGRectIsEmpty(v.bounds)) return;
    Class chat=NSClassFromString(@"BaseMsgContentViewController"); BOOL inChat=NO;
    for(UIResponder *r=v; r; r=r.nextResponder) if(chat && [r isKindOfClass:chat]) { inChat=YES; break; }
    if(!inChat) return;
    WUApplyConfiguredSurface(v,key,10,YES); [decorated addObject:v];
}
static BOOL Visible(UIView *v) {
    if(!v.window || !v.window.isKeyWindow || CGRectIsEmpty(v.bounds)) return NO;
    for(UIView *p=v;p;p=p.superview) {
        if(p.hidden || p.alpha<0.01) return NO;
        if(p.clipsToBounds && !CGRectIntersectsRect([v convertRect:v.bounds toView:p],p.bounds)) return NO;
    }
    return CGRectIntersectsRect([v convertRect:v.bounds toView:v.window],v.window.bounds);
}
static BOOL Editing(UIView *v,NSUInteger depth) {
    if(!depth || v.subviews.count>64) return NO;
    if([v isKindOfClass:UITextView.class] && [(UITextView *)v isEditable] && v.isFirstResponder && Visible(v)) return YES;
    for(UIView *c in v.subviews) if(Editing(c,depth-1)) return YES;
    return NO;
}
static void RefreshInput(UIView *v) {
    BOOL chat=NO; Class cls=NSClassFromString(@"BaseMsgContentViewController");
    for(UIResponder *r=v;r;r=r.nextResponder) if(cls && [r isKindOfClass:cls]) { UIViewController *owner=(id)r; chat=owner.viewIfLoaded.window && !owner.presentedViewController && !owner.navigationController.presentedViewController && !owner.isBeingDismissed; break; }
    NSUInteger effect=WUInputEffect(WUEnabled(@"inputBorder"),pulseReady && WUEnabled(@"inputPulse"),chat && Visible(v),Editing(v,8),!inputSuspended && UIApplication.sharedApplication.applicationState==UIApplicationStateActive,UIAccessibilityIsReduceMotionEnabled());
    if(!effect) { Remove(v); return; }
    CAShapeLayer *l=objc_getAssociatedObject(v,&layerKey);
    if(l && l.superlayer!=v.layer) { Remove(v); l=nil; }
    if(!l) { l=[CAShapeLayer layer]; l.name=@"org.wechatunified.input"; l.fillColor=UIColor.clearColor.CGColor; [v.layer addSublayer:l]; objc_setAssociatedObject(v,&layerKey,l,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [decorated addObject:v]; }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    NSDictionary *style=WUSurfaceStyle(@"inputBorder"); CGFloat radius=style[@"radius"]?[style[@"radius"] doubleValue]:10;
    l.frame=v.bounds; l.path=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(v.bounds,1,1) cornerRadius:radius].CGPath;
    l.strokeColor=WUSurfaceColor(@"inputBorder",@"border",v.traitCollection,UIColor.systemTealColor).CGColor; l.lineWidth=style[@"borderWidth"]?[style[@"borderWidth"] doubleValue]:(effect==2?2:1);
    [CATransaction commit];
    if(effect==2 && ![l animationForKey:@"wu.breathe"]) { CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"opacity"]; a.fromValue=@0.25; a.toValue=@1; a.duration=1.2; a.autoreverses=YES; a.repeatCount=HUGE_VALF; [l addAnimation:a forKey:@"wu.breathe"]; }
    if(effect!=2) [l removeAnimationForKey:@"wu.breathe"];
    if(effect==2 && !pulseWatch) {
        pulseWatch=[NSTimer timerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *timer) {
            BOOL any=NO; for(UIView *input in inputs.allObjects) { RefreshInput(input); CALayer *layer=objc_getAssociatedObject(input,&layerKey); if([layer animationForKey:@"wu.breathe"]) any=YES; }
            if(!any) { [timer invalidate]; pulseWatch=nil; }
        }]; [NSRunLoop.mainRunLoop addTimer:pulseWatch forMode:NSRunLoopCommonModes];
    }
}
BOOL WUInputPulseAvailable(void) { return pulseReady; }
static void Input(UIView *v,SEL s) { WURestoreConfiguredSurface(v); ((void(*)(id,SEL))inputLayout)(v,s); [inputs addObject:v]; WUApplyConfiguredSurface(v,@"inputBorder",10,YES); RefreshInput(v); WURefreshDictation(v); }
static void InputWindow(UIView *v,SEL s) { WURestoreConfiguredSurface(v); Remove(v); ((void(*)(id,SEL))inputWindow)(v,s); [inputs addObject:v]; WUApplyConfiguredSurface(v,@"inputBorder",10,YES); RefreshInput(v); WURefreshDictation(v); }
static void Notice(UIView *v,SEL s) { WURestoreConfiguredSurface(v); Remove(v); ((void(*)(id,SEL))noticeLayout)(v,s); Decorate(v,@"noticeBorder"); }
static void RestoreTables(void) {
    for(UITableView *t in tables) {
        NSNumber *baseline=objc_getAssociatedObject(t,&separatorKey);
        if(baseline && t.separatorStyle==UITableViewCellSeparatorStyleNone) t.separatorStyle=baseline.integerValue;
        objc_setAssociatedObject(t,&separatorKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [tables removeAllObjects];
}
static void Walk(UIView *v) {
    if([v isKindOfClass:UITableView.class]) {
        UITableView *t=(UITableView *)v;
        if(!objc_getAssociatedObject(t,&separatorKey)) objc_setAssociatedObject(t,&separatorKey,@(t.separatorStyle),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        t.separatorStyle=UITableViewCellSeparatorStyleNone; [tables addObject:t]; return;
    }
    for(UIView *c in v.subviews) Walk(c);
}
static void Home(UIViewController *v,SEL s) {
    RestoreTables(); ((void(*)(id,SEL))homeLayout)(v,s);
    if(WUEnabled(@"separators")) Walk(v.view);
    WURefreshHome(v);
}
void WUInstallAppearance(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{
        decorated=NSHashTable.weakObjectsHashTable; tables=NSHashTable.weakObjectsHashTable; inputs=NSHashTable.weakObjectsHashTable;
        for(NSString *name in @[WUChanged,UIApplicationWillResignActiveNotification,UIApplicationDidBecomeActiveNotification,UIAccessibilityReduceMotionStatusDidChangeNotification,UITextViewTextDidBeginEditingNotification,UITextViewTextDidEndEditingNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if([n.name isEqual:UIApplicationWillResignActiveNotification]) inputSuspended=YES;
            if([n.name isEqual:UIApplicationDidBecomeActiveNotification]) inputSuspended=NO;
            RestoreTables(); [pulseWatch invalidate]; pulseWatch=nil;
            for(UIView *v in decorated.allObjects) { WURestoreConfiguredSurface(v); Remove(v); [v setNeedsLayout]; }
            if(![n.name isEqual:UIApplicationWillResignActiveNotification]) for(UIView *v in inputs.allObjects) RefreshInput(v);
        }];
    });
    BOOL a=WUHook(@"MMGrowTextView",@"layoutSubviews",NO,"v",@[],(IMP)Input,&inputLayout);
    BOOL b=WUHook(@"MMGrowTextView",@"didMoveToWindow",NO,"v",@[],(IMP)InputWindow,&inputWindow);
    pulseReady=a && b;
    WUHook(@"SystemMessageCellView",@"layoutSubviews",NO,"v",@[],(IMP)Notice,&noticeLayout);
    WUHook(@"NewMainFrameViewController",@"viewDidLayoutSubviews",NO,"v",@[],(IMP)Home,&homeLayout);
}
