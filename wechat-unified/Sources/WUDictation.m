#import "WU.h"
#import "WUDictation.h"
#import "WUDictationLogic.h"

NSString *const WUDictationHideKey = @"hideDictationIcon";
NSString *const WUDictationGuardKey = @"dictationPreventMistouch";
static IMP iconOriginal, hitOriginal, beganOriginal, movedOriginal, endedOriginal, cancelOriginal;
static IMP hiddenOriginal;
static Class maskedClass;
static BOOL ready, observedIcon;
static NSUInteger contextEpoch;
static NSHashTable<UIView *> *inputs, *icons;
static char inputKey, iconKey;

@interface WUDIconState : NSObject { @public WUDMask mask; }
@property(nonatomic, weak) UIView *owner;
@property(nonatomic) BOOL usesHidden;
@property(nonatomic) CGFloat desiredAlpha;
@end
@implementation WUDIconState @end
@interface WUDInputState : NSObject { @public WUDTap tap; }
@property(nonatomic, weak) UIView *icon;
@property(nonatomic) BOOL beganSeen, forwardingEnd;
@property(nonatomic) NSUInteger epoch, revision, bindingGeneration;
@property(nonatomic, copy) NSString *bindingAccount, *bindingSession;
@property(nonatomic, weak) UIView *targetIcon;
@property(nonatomic, weak) UITouch *touch;
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) UIViewController *chat;
@property(nonatomic, copy) NSString *session, *account;
@end
@implementation WUDInputState @end

static UIViewController *Chat(UIView *v) {
    Class c = NSClassFromString(@"BaseMsgContentViewController");
    for (UIResponder *r = v; r; r = r.nextResponder)
        if (c && [r isKindOfClass:c] && [r isKindOfClass:UIViewController.class]) return (id)r;
    return nil;
}
static WUDInputState *State(UIView *v) {
    WUDInputState *s = objc_getAssociatedObject(v, &inputKey);
    if (!s) {
        s = [WUDInputState new];
        objc_setAssociatedObject(v, &inputKey, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [inputs addObject:v];
    }
    return s;
}
static void Clear(WUDInputState *s) {
    if (!s) return;
    ++s.revision;
    WUDTapCancel(&s->tap); s.beganSeen = NO;
    s.touch = nil; s.targetIcon = nil; s.window = nil; s.chat = nil;
    s.session = nil; s.account = nil;
}
static BOOL Owned(UIView *icon, WUDIconState *s) {
    UIView *v = s.owner;
    return v && icon != v && v.window && icon.window == v.window &&
           [icon isDescendantOfView:v] && Chat(v) &&
           UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}
static void Restore(UIView *icon) {
    WUDIconState *s = objc_getAssociatedObject(icon, &iconKey);
    if (!s) return;
    objc_setAssociatedObject(icon, &iconKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (s.usesHidden) {
        BOOL hidden = WUDMaskApply(&s->mask, false, icon.hidden);
        if (hiddenOriginal) ((void(*)(id,SEL,BOOL))hiddenOriginal)(icon, @selector(setHidden:), hidden);
    } else if (icon.alpha == 0) {
        icon.alpha = s.desiredAlpha;
    }
    [icons removeObject:icon];
}
static void Hidden(UIView *v, SEL cmd, BOOL requested) {
    WUDIconState *s = objc_getAssociatedObject(v, &iconKey);
    if (NSThread.isMainThread && s && s.usesHidden) {
        // Record the host write BEFORE dropping ownership/configuration: never restore stale intent.
        s->mask.desiredHidden = requested;
        if (ready && Owned(v,s) && WUEnabled(WUDictationHideKey)) {
            s->mask.active = true; requested = YES;
        } else {
            s->mask.active = false;
            objc_setAssociatedObject(v, &iconKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [icons removeObject:v];
        }
    }
    if (hiddenOriginal) ((void(*)(id,SEL,BOOL))hiddenOriginal)(v, cmd, requested);
}
static BOOL Hook(NSString *name, NSString *selector, const char *ret, NSArray *args, IMP replacement, IMP *original) {
    Method m = class_getInstanceMethod(NSClassFromString(name), NSSelectorFromString(selector));
    if (!WUMatches(m,ret,args)) return NO;
    if (*original) return method_getImplementation(m) == replacement;
    if (method_getImplementation(m) == replacement) return NO;
    // WUHook may return YES for an occupied key without setting our original.
    return WUHook(name,selector,NO,ret,args,replacement,original) && *original && *original != replacement;
}
static BOOL EnsureHiddenHook(UIView *icon) {
    Class c = object_getClass(icon);
    if (maskedClass) return c == maskedClass;
    if (c == UIView.class || c == UIImageView.class) return NO;
    const char *image = class_getImageName(c);
    NSString *path = image ? [NSString stringWithUTF8String:image] : nil;
    NSString *bundlePrefix = [NSBundle.mainBundle.bundlePath stringByAppendingString:@"/"];
    if (![path hasPrefix:bundlePrefix]) return NO;
    if (!Hook(NSStringFromClass(c), @"setHidden:", "v", @[@(@encode(BOOL))], (IMP)Hidden, &hiddenOriginal)) return NO;
    maskedClass = c;
    return YES;
}
static UIView *Bind(UIView *v, id candidate) {
    WUDInputState *s = State(v);
    UIViewController *chat = Chat(v);
    UIView *icon = [candidate isKindOfClass:UIView.class] ? candidate : nil;
    if (!chat || !v.window || icon == v || icon.window != v.window || ![icon isDescendantOfView:v] ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) icon = nil;
    NSString *account = WUCurrentAccount(), *session = WUChatSession(chat);
    NSUInteger generation = WUContextGeneration();
    BOOL rebound = s.bindingGeneration != generation || ![s.bindingAccount isEqualToString:account ?: @""] ||
                   ![s.bindingSession isEqualToString:session ?: @""];
    if (s.icon != icon || rebound) {
        WUDIconState *old = objc_getAssociatedObject(s.icon, &iconKey);
        if (old.owner == v) Restore(s.icon);
        Clear(s); s.icon = icon;
        s.bindingAccount = account ?: @""; s.bindingSession = session ?: @""; s.bindingGeneration = generation;
    }
    if (!icon) return nil;
    observedIcon = YES;
    WUDIconState *is = objc_getAssociatedObject(icon, &iconKey);
    if (is && is.owner != v) { Restore(icon); is = nil; }
    if (!WUEnabled(WUDictationHideKey)) { Restore(icon); return icon; }
    if (!is) {
        is = [WUDIconState new]; is.owner = v;
        is.usesHidden = EnsureHiddenHook(icon);
        is.desiredAlpha = icon.alpha;
        objc_setAssociatedObject(icon, &iconKey, is, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [icons addObject:icon];
    }
    if (is.usesHidden) {
        BOOL hidden = WUDMaskApply(&is->mask, true, icon.hidden);
        if (icon.hidden != hidden && hiddenOriginal)
            ((void(*)(id,SEL,BOOL))hiddenOriginal)(icon, @selector(setHidden:), hidden);
    } else {
        // shortcut: instance-only alpha snapshot; same-value host alpha=0 writes are unobservable.
        // hidden is never written in this fallback, so the latest host hidden intent survives exactly.
        if (icon.alpha != 0) is.desiredAlpha = icon.alpha;
        icon.alpha = 0;
    }
    return icon;
}
static id Icon(id v, SEL cmd) {
    id result = iconOriginal ? ((id(*)(id,SEL))iconOriginal)(v, cmd) : nil;
    if (ready && NSThread.isMainThread && [v isKindOfClass:UIView.class]) Bind(v, result);
    return result;
}
void WURefreshDictation(UIView *v) {
    Class c = NSClassFromString(@"MMGrowTextView");
    if (!ready || !NSThread.isMainThread || !c || ![v isKindOfClass:c]) return;
    for (UIView *icon in icons.allObjects) {
        WUDIconState *is = objc_getAssociatedObject(icon, &iconKey);
        if (!Owned(icon,is) || !WUEnabled(WUDictationHideKey)) Restore(icon);
    }
    Bind(v, ((id(*)(id,SEL))iconOriginal)(v, NSSelectorFromString(@"dictationIcon")));
}
static BOOL Inside(UIView *v, UIView *icon, CGPoint point) {
    if (!icon || !v.window || icon.window != v.window || ![icon isDescendantOfView:v]) return NO;
    for (UIView *p = icon; p; p = p.superview) {
        if (p.hidden || p.alpha <= 0.01 || !p.userInteractionEnabled) return NO;
    }
    CGRect rect = [icon convertRect:icon.bounds toView:v];
    return isfinite(point.x) && isfinite(point.y) && !CGRectIsEmpty(rect) &&
           !CGRectIsInfinite(rect) && CGRectContainsPoint(rect, point);
}
static BOOL Current(UIView *v, WUDInputState *s, uint64_t generation) {
    UIViewController *c = s.chat;
    return c && s.epoch == contextEpoch && c == Chat(v) && v.window && v.window == s.window && v.window.isKeyWindow &&
           !c.isBeingDismissed && !c.presentedViewController &&
           !c.navigationController.presentedViewController &&
           (!c.navigationController || c.navigationController.topViewController == c) &&
           UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
           [s.account isEqualToString:WUCurrentAccount()] &&
           [s.session isEqualToString:WUChatSession(c)] && generation == WUContextGeneration();
}
static UIView *Hit(UIView *v, SEL cmd, CGPoint point, UIEvent *event) {
    UIView *result = hitOriginal ? ((UIView *(*)(id,SEL,CGPoint,UIEvent *))hitOriginal)(v,cmd,point,event) : nil;
    if (!ready || !NSThread.isMainThread) return result;
    WUDInputState *s = State(v);
    if (s.forwardingEnd || !WUEnabled(WUDictationGuardKey)) { Clear(s); return result; }
    UIView *icon = Bind(v, ((id(*)(id,SEL))iconOriginal)(v, NSSelectorFromString(@"dictationIcon")));
    UITouch *t = event.allTouches.count == 1 ? event.allTouches.anyObject : nil;
    BOOL childHit = icon && result && (result == icon || [result isDescendantOfView:icon]);
    if (!WUDShouldRoute(true, v.isFirstResponder, Inside(v,icon,point), childHit,
                        t && t.phase == UITouchPhaseBegan)) { Clear(s); return result; }
    if (s->tap.pending) {
        if (s.touch == t && s.targetIcon == icon && !s.beganSeen && Current(v,s,s->tap.generation)) return v;
        Clear(s); return result;
    }
    Clear(s); s.epoch = contextEpoch;
    s.touch = t; s.targetIcon = icon; s.window = v.window; s.chat = Chat(v);
    s.account = [WUCurrentAccount() copy]; s.session = [WUChatSession(s.chat) copy];
    uint64_t generation = WUContextGeneration();
    WUDTapBegin(&s->tap, s.account.length && s.session.length, t.timestamp, generation);
    if (!s->tap.pending || !Current(v,s,generation)) { Clear(s); return result; }
    return v;
}
static void Began(UIView *v, SEL cmd, NSSet<UITouch *> *touches, UIEvent *event) {
    if (ready && NSThread.isMainThread) {
        WUDInputState *s = State(v);
        BOOL valid = !s.forwardingEnd && !s.beganSeen && s->tap.pending && touches.count == 1 &&
                     event.allTouches.count == 1 && touches.anyObject == s.touch && s.touch.view == v;
        if (!valid) Clear(s); else s.beganSeen = YES;
    }
    if (beganOriginal) ((void(*)(id,SEL,id,id))beganOriginal)(v,cmd,touches,event);
}
static void Moved(UIView *v, SEL cmd, NSSet<UITouch *> *touches, UIEvent *event) {
    if (ready && NSThread.isMainThread) {
        WUDInputState *s = State(v);
        UITouch *t = touches.count == 1 ? touches.anyObject : nil;
        if (s.forwardingEnd || !s.beganSeen || !t || t != s.touch || event.allTouches.count != 1 ||
            !Current(v,s,s->tap.generation) || !Inside(v,s.targetIcon,[t locationInView:v])) Clear(s);
    }
    if (movedOriginal) ((void(*)(id,SEL,id,id))movedOriginal)(v,cmd,touches,event);
}
static void Ended(UIView *v, SEL cmd, NSSet<UITouch *> *touches, UIEvent *event) {
    WUDInputState *s = ready && NSThread.isMainThread ? State(v) : nil;
    WUDInputState *next = nil;
    BOOL focus = NO;
    uint64_t generation = s ? s->tap.generation : 0;
    UITouch *t = touches.count == 1 ? touches.anyObject : nil;
    if (s && s->tap.pending && !s.forwardingEnd) {
        BOOL same = s.beganSeen && t && t.phase == UITouchPhaseEnded && t == s.touch &&
                    event.allTouches.count == 1 && Current(v,s,generation) && s.targetIcon == s.icon &&
                    s.targetIcon == ((id(*)(id,SEL))iconOriginal)(v,NSSelectorFromString(@"dictationIcon"));
        focus = WUDTapEnd(&s->tap, WUEnabled(WUDictationGuardKey), v.isFirstResponder,
                           same, t && Inside(v,s.targetIcon,[t locationInView:v]),
                           t ? t.timestamp : NAN, WUContextGeneration());
        // Reentrant native callbacks must not reuse the consumed touch or start a new routed one.
        next = [WUDInputState new]; next.icon = s.icon; next.forwardingEnd = YES;
        next.bindingAccount = s.bindingAccount; next.bindingSession = s.bindingSession;
        next.bindingGeneration = s.bindingGeneration;
        objc_setAssociatedObject(v,&inputKey,next,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else { Clear(s); s = nil; }
    if (endedOriginal) ((void(*)(id,SEL,id,id))endedOriginal)(v,cmd,touches,event);
    next.forwardingEnd = NO;
    if (focus && next.revision == 0 && objc_getAssociatedObject(v,&inputKey) == next &&
        WUEnabled(WUDictationGuardKey) && !v.isFirstResponder && Current(v,s,generation) &&
        s.targetIcon == ((id(*)(id,SEL))iconOriginal)(v,NSSelectorFromString(@"dictationIcon")) &&
        Inside(v,s.targetIcon,[t locationInView:v])) [v becomeFirstResponder];
    Clear(s);
}
static void Cancelled(UIView *v, SEL cmd, NSSet *touches, UIEvent *event) {
    if (NSThread.isMainThread) Clear(objc_getAssociatedObject(v,&inputKey));
    if (cancelOriginal) ((void(*)(id,SEL,id,id))cancelOriginal)(v,cmd,touches,event);
}
BOOL WUDictationAvailable(NSString *key) {
    return ([key isEqualToString:WUDictationHideKey] || [key isEqualToString:WUDictationGuardKey]) && ready && observedIcon;
}
void WUInstallDictation(void) {
    if (!NSThread.isMainThread || ready) return;
    Class c = NSClassFromString(@"MMGrowTextView");
    NSArray *pointArgs = @[@(@encode(CGPoint)), @"@"];
    NSArray *touchArgs = @[@"@", @"@"];
    if (!c || ![c isSubclassOfClass:UIView.class] ||
        !WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"dictationIcon")), "@", @[]) ||
        !WUMatches(class_getInstanceMethod(c,@selector(hitTest:withEvent:)), "@", pointArgs)) return;
    for (NSString *name in @[@"touchesBegan:withEvent:",@"touchesMoved:withEvent:",@"touchesEnded:withEvent:",@"touchesCancelled:withEvent:"])
        if (!WUMatches(class_getInstanceMethod(c,NSSelectorFromString(name)), "v", touchArgs)) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inputs = NSHashTable.weakObjectsHashTable; icons = NSHashTable.weakObjectsHashTable;
        for (NSString *name in @[WUChanged,UIApplicationWillResignActiveNotification,UIApplicationDidBecomeActiveNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
                ++contextEpoch;
                for (UIView *icon in icons.allObjects) Restore(icon);
                for (UIView *v in inputs.allObjects) {
                    Clear(objc_getAssociatedObject(v,&inputKey));
                    if (![n.name isEqualToString:UIApplicationWillResignActiveNotification]) WURefreshDictation(v);
                    [v setNeedsLayout];
                }
            }];
    });
    BOOL ok = Hook(@"MMGrowTextView",@"dictationIcon","@",@[],(IMP)Icon,&iconOriginal);
    ok &= Hook(@"MMGrowTextView",@"hitTest:withEvent:","@",pointArgs,(IMP)Hit,&hitOriginal);
    ok &= Hook(@"MMGrowTextView",@"touchesBegan:withEvent:","v",touchArgs,(IMP)Began,&beganOriginal);
    ok &= Hook(@"MMGrowTextView",@"touchesMoved:withEvent:","v",touchArgs,(IMP)Moved,&movedOriginal);
    ok &= Hook(@"MMGrowTextView",@"touchesEnded:withEvent:","v",touchArgs,(IMP)Ended,&endedOriginal);
    ok &= Hook(@"MMGrowTextView",@"touchesCancelled:withEvent:","v",touchArgs,(IMP)Cancelled,&cancelOriginal);
    ready = ok && iconOriginal && hitOriginal && beganOriginal && movedOriginal && endedOriginal && cancelOriginal;
}
