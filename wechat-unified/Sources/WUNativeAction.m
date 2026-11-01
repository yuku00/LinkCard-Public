#import "WUNativeAction.h"
#include <limits.h>
static NSMutableSet<WUNativeAction *> *actions;
static NSTimer *poll;
static BOOL Has(id x, NSString *s, const char *r, NSArray *a) {
    return x && WUMatches(class_getInstanceMethod(object_getClass(x),NSSelectorFromString(s)),r,a);
}
id WUNativeObject(id x,NSString *s) {
    if(!Has(x,s,"@",@[])) return nil;
    @try { return ((id(*)(id,SEL))objc_msgSend)(x,NSSelectorFromString(s)); }
    @catch(NSException *e) { return nil; }
}
NSString *WUNativeString(id x,NSString *s) {
    id v=WUNativeObject(x,s); return [v isKindOfClass:NSString.class]?[v copy]:nil;
}
NSNumber *WUNativeUnsigned(id x,NSString *s) {
    SEL sel=NSSelectorFromString(s);
    @try {
        if(Has(x,s,"I",@[])) return @(((unsigned(*)(id,SEL))objc_msgSend)(x,sel));
        if(Has(x,s,"Q",@[])) return @(((unsigned long long(*)(id,SEL))objc_msgSend)(x,sel));
        if(Has(x,s,"i",@[])) { int v=((int(*)(id,SEL))objc_msgSend)(x,sel); return v<0?nil:@(v); }
        if(Has(x,s,"q",@[])) { long long v=((long long(*)(id,SEL))objc_msgSend)(x,sel); return v<0?nil:@(v); }
    } @catch(NSException *e) {}
    return nil;
}
BOOL WUNativeSetUnsigned(id x,NSString *s,uint64_t n) {
    SEL sel=NSSelectorFromString(s);
    if(Has(x,s,"v",@[@"I"]) && n<=UINT_MAX) ((void(*)(id,SEL,unsigned))objc_msgSend)(x,sel,(unsigned)n);
    else if(Has(x,s,"v",@[@"Q"])) ((void(*)(id,SEL,unsigned long long))objc_msgSend)(x,sel,n);
    else if(Has(x,s,"v",@[@"i"]) && n<=INT_MAX) ((void(*)(id,SEL,int))objc_msgSend)(x,sel,(int)n);
    else if(Has(x,s,"v",@[@"q"]) && n<=LLONG_MAX) ((void(*)(id,SEL,long long))objc_msgSend)(x,sel,(long long)n);
    else return NO;
    return YES;
}
BOOL WUNativeNumberField(Class cls,NSString *getter,NSString *setter) {
    for(NSString *t in @[@"I",@"Q",@"i",@"q"])
        if(WUMatches(class_getInstanceMethod(cls,NSSelectorFromString(getter)),t.UTF8String,@[]) &&
           WUMatches(class_getInstanceMethod(cls,NSSelectorFromString(setter)),"v",@[t])) return YES;
    return NO;
}
NSDictionary *WUNativeMessageIdentity(id msg) {
    NSMutableDictionary *out=[NSMutableDictionary dictionary];
    for(NSString *k in @[@"m_nsFromUsr",@"m_nsToUsr",@"m_nsRealChatUsr"]) {
        NSString *s=WUNativeString(msg,k);
        if(!s && ![k isEqual:@"m_nsRealChatUsr"]) return nil;
        out[k]=s?:@"";
    }
    for(NSString *k in @[@"m_n64MesSvrID",@"m_uiMesLocalID",@"m_uiCreateTime",@"m_uiMessageType"]) {
        NSNumber *n=WUNativeUnsigned(msg,k); if(!n) return nil; out[k]=n;
    }
    return [out copy];
}
static void StartObservers(void) {
    static dispatch_once_t once; dispatch_once(&once,^{
        actions=[NSMutableSet set];
        for(NSString *name in @[WUChanged,UIApplicationWillResignActiveNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ WUNativeCancelActions(); }];
    });
}
@implementation WUNativeAction {
    BOOL _consumed, _finished, _executing;
}
- (BOOL)consumed { return _consumed; }
- (BOOL)isValid {
    @try { return !_finished && self.owner.viewIfLoaded.window &&
        (!self.owner.navigationController || self.owner.navigationController.visibleViewController==self.owner) &&
        UIApplication.sharedApplication.applicationState==UIApplicationStateActive &&
        WUNativeEnabled(self.key) && self.valid && self.valid(); }
    @catch(NSException *e) { return NO; }
}
- (BOOL)present {
    if(!NSThread.isMainThread || self.owner.presentedViewController || !self.alert || ![self isValid]) { [self cancel]; return NO; }
    StartObservers(); [actions addObject:self];
    if(!poll) {
        poll=[NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *t){ WUNativeRefreshActions(); }];
        [NSRunLoop.mainRunLoop addTimer:poll forMode:NSRunLoopCommonModes];
    }
    @try { [self.owner presentViewController:self.alert animated:YES completion:nil]; }
    @catch(NSException *e) { [self cancel]; return NO; }
    return YES;
}
- (void)finish {
    _consumed=YES; _finished=YES;
    // Dismiss exactly our alert, never an unrelated controller replacing it.
    if(self.owner.presentedViewController==self.alert) [self.alert dismissViewControllerAnimated:NO completion:nil];
    [actions removeObject:self];
    if(!actions.count) { [poll invalidate]; poll=nil; }
    self.alert=nil; self.owner=nil; self.valid=nil; self.commit=nil;
}
- (void)cancel { if(_finished || _executing) return; self.outcome=@"cancelled"; [self finish]; }
- (void)choose:(NSUInteger)choice {
    if(_consumed) return;
    UIViewController *owner=self.owner;
    if(![self isValid] || (owner.presentedViewController && owner.presentedViewController!=self.alert)) { [self cancel]; return; }
    // Keep the operation pending while UIKit dismisses; consume before any callback.
    _consumed=YES;
    void (^execute)(void)=^{
        if(self->_finished) return;
        if(![self isValid] || owner.presentedViewController) { [self cancel]; return; }
        BOOL (^stillCurrent)(void)=self.valid;
        self->_executing=YES;
        @try { if(self.commit) self.commit(choice); self.outcome=@"submitted"; }
        @catch(NSException *e) { self.outcome=[e.name isEqual:@"WUNativePreparationFailed"]?@"not-submitted":@"unknown"; }
        self->_executing=NO; [self finish];
        if([self.outcome isEqual:@"unknown"] && owner.viewIfLoaded.window && !owner.presentedViewController && UIApplication.sharedApplication.applicationState==UIApplicationStateActive) {
            UIAlertController *notice=[UIAlertController alertControllerWithTitle:@"操作结果未知" message:@"原动作抛出异常，可能已提交。请在宿主核对；不会自动重试。" preferredStyle:UIAlertControllerStyleAlert];
            WUNativeAction *info=[WUNativeAction new]; info.owner=owner; info.key=self.key; info.account=self.account; info.session=self.session; info.valid=stillCurrent;
            __weak WUNativeAction *weakInfo=info;
            [notice addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ [weakInfo cancel]; }]];
            info.alert=notice; [info present];
        }
    };
    // Original UI actions run after our own modal closes, never beneath a blocking alert.
    // UIKit may already have dismissed its action sheet before invoking the handler.
    if(owner.presentedViewController==self.alert) [self.alert dismissViewControllerAnimated:NO completion:execute];
    else execute();
}
@end
WUNativeAction *WUNativePendingAction(NSString *key,NSString *account,NSString *session) {
    for(WUNativeAction *a in actions) if([a.key isEqual:key] && [a.account isEqual:account] && [a.session isEqual:session]) return a;
    return nil;
}
void WUNativeRefreshActions(void) {
    for(WUNativeAction *a in actions.allObjects) if(![a isValid] || (!a.consumed && a.owner.presentedViewController!=a.alert)) [a cancel];
}
BOOL WUNativeOwnsController(UIViewController *controller) {
    if(!controller) return NO;
    for(WUNativeAction *a in actions) if(a.alert==controller) return YES;
    return NO;
}
void WUNativeCancelActions(void) { for(WUNativeAction *a in actions.allObjects) [a cancel]; }
