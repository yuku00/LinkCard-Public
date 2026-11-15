// Optional legacy host adapter. Import after ChatInputToolbar.inc and WU.h.
#import <objc/runtime.h>
#import <objc/message.h>
#import "WUInputReservationGeometry.h"

static const CGFloat WUInputExtra=44.0;
static char WUInputStateKey, WUInputFailureKey;
static IMP WUInputHeightOriginal;
static BOOL WUInputHookReady;

@interface WUInputReservation : NSObject
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,weak) UIView *tool;
@property(nonatomic,weak) UIView *bar;
@property(nonatomic,strong) WUInputToolbar *toolbar;
@property(nonatomic) WUInputRect oldTool, oldBar;
@property(nonatomic) BOOL enabled, ready;
@property(nonatomic,copy) BOOL (^current)(void);
@end
@implementation WUInputReservation @end

static WUInputRect WUInputWindowRect(UIView *v) {
    CGRect r=[v convertRect:v.bounds toView:v.window];
    return (WUInputRect){r.origin.x,r.origin.y,r.size.width,r.size.height};
}
static BOOL WUInputSignature(id object, SEL sel, const char *result) {
    Method method=class_getInstanceMethod([object class],sel);
    if(!method || method_getNumberOfArguments(method)!=2) return NO;
    char *ret=method_copyReturnType(method), *a=method_copyArgumentType(method,0), *b=method_copyArgumentType(method,1);
    BOOL ok=ret && a && b && !strcmp(ret,result) && !strcmp(a,"@") && !strcmp(b,":");
    free(ret); free(a); free(b); return ok;
}
static double WUInputHeight(id self, SEL cmd) {
    double base=((double(*)(id,SEL))WUInputHeightOriginal)(self,cmd);
    if(!NSThread.isMainThread) return base;
    WUInputReservation *s=objc_getAssociatedObject(self,&WUInputStateKey);
    return s.enabled && isfinite(base) && base>=0 && base<1000 ? base+WUInputExtra : base;
}
static BOOL WUInputInstall(void) {
    if(WUInputHookReady) {
        Class c=NSClassFromString(@"MMInputToolView");
        Method m=c?class_getInstanceMethod(c,NSSelectorFromString(@"getGroupUndoneBarHeight")):NULL;
        return m && method_getImplementation(m)==(IMP)WUInputHeight;
    }
    Class cls=NSClassFromString(@"MMInputToolView");
    if(!cls || ![cls isSubclassOfClass:UIView.class]) return NO;
    Method m=class_getInstanceMethod(cls,NSSelectorFromString(@"getGroupUndoneBarHeight"));
    if(!m || method_getNumberOfArguments(m)!=2) return NO;
    char *ret=method_copyReturnType(m), *a=method_copyArgumentType(m,0), *b=method_copyArgumentType(m,1);
    BOOL valid=ret && a && b && !strcmp(ret,@encode(double)) && !strcmp(a,"@") && !strcmp(b,":");
    free(ret); free(a); free(b);
    if(!valid) return NO;
    WUInputHookReady=WUHook(@"MMInputToolView",@"getGroupUndoneBarHeight",NO,@encode(double),@[],(IMP)WUInputHeight,&WUInputHeightOriginal);
    return WUInputHookReady && WUInputHeightOriginal;
}
// The new strip may not intersect any visible host sibling. Reject uncertain layouts.
static BOOL WUInputClear(UIView *container, UIView *except, CGRect strip) {
    for(UIView *child in container.subviews) {
        if(child==except || child.hidden || child.alpha<=0.01) continue;
        // A noninteractive image behind the input is decoration, not a list or control.
        if(except && [child isKindOfClass:UIImageView.class] && !child.userInteractionEnabled && [container.subviews indexOfObjectIdenticalTo:child]<[container.subviews indexOfObjectIdenticalTo:except]) continue;
        CGRect r=[child convertRect:child.bounds toView:container];
        if(!CGRectIsNull(r) && !CGRectIsInfinite(r) && CGRectIntersectsRect(CGRectInset(strip,0,0.5),r)) return NO;
    }
    return YES;
}
static BOOL WUInputStillSafe(WUInputReservation *s) {
    UIView *tool=s.tool, *root=s.owner.viewIfLoaded, *bar=s.bar;
    if(!tool || !bar || !tool.window || tool.window!=root.window || tool.superview!=root || ![bar isDescendantOfView:tool] || tool.hidden || tool.alpha<=0.01 || tool.bounds.size.width<=0 || tool.bounds.size.height<WUInputExtra) return NO;
    CGRect strip=CGRectMake(CGRectGetMinX(tool.bounds),CGRectGetMinY(tool.bounds),tool.bounds.size.width,WUInputExtra);
    CGRect rootStrip=[tool convertRect:strip toView:root];
    if(!CGRectContainsRect(root.bounds,rootStrip)) return NO;
    return WUInputClear(tool,s.toolbar,strip) && WUInputClear(root,tool,rootStrip);
}
static void WUInputStop(UIViewController *owner, BOOL failed) {
    WUInputReservation *s=objc_getAssociatedObject(owner,&WUInputStateKey);
    if(!s) { if(!failed) objc_setAssociatedObject(owner,&WUInputFailureKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); return; }
    s.enabled=NO;
    [s.toolbar removeFromSuperview]; s.toolbar=nil;
    if(objc_getAssociatedObject(s.tool,&WUInputStateKey)==s) objc_setAssociatedObject(s.tool,&WUInputStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(owner,&WUInputStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(owner,&WUInputFailureKey,failed?@YES:nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [s.tool setNeedsLayout]; [owner.viewIfLoaded setNeedsLayout];
}
static void WUInputRemove(UIViewController *owner) { if(NSThread.isMainThread && owner) WUInputStop(owner,NO); }
// Call after host layout. The navigation action remains available throughout staging and failure.
static void WUInputSyncChecked(UIViewController *owner, NSArray<NSDictionary *> *entries, BOOL (^current)(void)) {
    if(!NSThread.isMainThread || !owner) return;
    WUInputReservation *s=objc_getAssociatedObject(owner,&WUInputStateKey);
    if(!owner.viewIfLoaded.window || !entries.count || (current && !current())) { WUInputStop(owner,NO); return; }
    if(s) {
        if((s.current && !s.current()) || (s.ready && (!WUInputInstall() || !WUInputStillSafe(s)))) WUInputStop(owner,YES);
        return;
    }
    if(objc_getAssociatedObject(owner,&WUInputFailureKey) || !WUInputInstall()) return;
    UIView *bar=WUInputBarForOwner(owner), *root=owner.viewIfLoaded, *tool=bar;
    Class cls=NSClassFromString(@"MMInputToolView");
    while(tool && ![tool isKindOfClass:cls]) tool=tool.superview;
    if(!tool || tool.superview!=root || tool.window!=root.window || !WUInputSignature(tool,NSSelectorFromString(@"toolPanelView"),"@")) return;
    id panel=nil;
    @try { panel=((id(*)(id,SEL))objc_msgSend)(tool,NSSelectorFromString(@"toolPanelView")); } @catch(__unused NSException *e) { return; }
    if(![panel isKindOfClass:UIView.class] || ![(UIView *)panel isDescendantOfView:tool]) return;
    if(objc_getAssociatedObject(tool,&WUInputStateKey)) return;
    s=[WUInputReservation new]; s.owner=owner; s.tool=tool; s.bar=bar; s.oldTool=WUInputWindowRect(tool); s.oldBar=WUInputWindowRect(bar); s.current=current; s.enabled=YES;
    objc_setAssociatedObject(owner,&WUInputStateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(tool,&WUInputStateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [tool setNeedsLayout]; [root setNeedsLayout];
    __weak UIViewController *weakOwner=owner;
    dispatch_async(dispatch_get_main_queue(),^{
        UIViewController *o=weakOwner;
        if(!o || objc_getAssociatedObject(o,&WUInputStateKey)!=s) return;
        @try {
            [o.viewIfLoaded layoutIfNeeded];
            if((s.current && !s.current()) || !WUInputInstall() || !s.tool.window || !WUInputReserved(s.oldTool,WUInputWindowRect(s.tool),s.oldBar,WUInputWindowRect(s.bar),WUInputExtra) || !WUInputStillSafe(s)) { WUInputStop(o,YES); return; }
            WUInputToolbar *toolbar=[[WUInputToolbar alloc] initWithEntries:entries]; s.toolbar=toolbar;
            toolbar.frame=CGRectMake(CGRectGetMinX(s.tool.bounds),CGRectGetMinY(s.tool.bounds),s.tool.bounds.size.width,WUInputExtra);
            toolbar.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;
            [s.tool addSubview:toolbar]; s.ready=YES;
        } @catch(__unused NSException *e) { WUInputStop(o,YES); }
    });
}

static __attribute__((unused)) void WUInputSync(UIViewController *owner, NSArray<NSDictionary *> *entries) {
    WUInputSyncChecked(owner,entries,nil);
}
