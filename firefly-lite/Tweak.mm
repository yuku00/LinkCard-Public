#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "Shared/FLPreferences.h"

// See docs/API-EVIDENCE.md: no private ivars, offsets or invented selectors.
@interface SBIconView : UIView
- (id)icon;
- (id)_iconImageView;
- (bool)isFolderIcon;
@end
@interface NSObject (FLBadgeDeclaration)
- (id)badgeNumberOrString;
@end

static NSHashTable<SBIconView *> *views;
static FLConfig config;
static BOOL stopped;
static char layerKey, observerKey;
static void (*originalLayout)(SBIconView *, SEL);
static void (*originalWindow)(SBIconView *, SEL);
static void (*originalSetIcon)(SBIconView *, SEL, id);
static void (*originalAccessories)(SBIconView *, SEL, id);

static BOOL Signature(Class cls, SEL sel, const char *ret, unsigned args, const char *arg = NULL) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m || method_getNumberOfArguments(m) != args) return NO;
    char type[128] = {};
    method_getReturnType(m, type, sizeof(type));
    if (type[0] != ret[0]) return NO;
    if (arg) {
        method_getArgumentType(m, 2, type, sizeof(type));
        if (type[0] != arg[0]) return NO;
    }
    return YES;
}
static void Remove(SBIconView *view) {
    CALayer *layer = objc_getAssociatedObject(view, &layerKey);
    [layer removeFromSuperlayer];
    objc_setAssociatedObject(view, &layerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void Update(SBIconView *view) {
    NSCAssert(NSThread.isMainThread, @"UI must be updated on main thread");
    if (stopped) { Remove(view); return; }
    if (!view.window) { Remove(view); [views removeObject:view]; return; }
    [views addObject:view];
    id icon = [view icon];
    BOOL badge = icon && Signature([icon class], @selector(badgeNumberOrString), "@", 2)
        && FLHasBadge([icon badgeNumberOrString]);
    if (!FLShouldGlow(config.enabled, config.allApps, badge, [view isFolderIcon], YES, config.intensity)) {
        Remove(view); return;
    }
    id candidate = [view _iconImageView];
    if (![candidate isKindOfClass:UIView.class]) { Remove(view); return; }
    UIView *image = candidate;
    if (![image isDescendantOfView:view]) { Remove(view); return; }
    CGRect frame = [image convertRect:image.bounds toView:view];
    if (CGRectIsEmpty(frame) || CGRectIsInfinite(frame) || CGRectIsNull(frame)
        || !isfinite(frame.origin.x) || !isfinite(frame.origin.y)
        || !isfinite(frame.size.width) || !isfinite(frame.size.height)) { Remove(view); return; }
    CALayer *layer = objc_getAssociatedObject(view, &layerKey);
    if (!layer) {
        layer = [CALayer layer];
        layer.name = @"dev.fireflylite.badgeglow.halo";
        objc_setAssociatedObject(view, &layerKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view.layer insertSublayer:layer atIndex:0];
    }
    UIColor *color = [UIColor colorWithRed:config.red green:config.green blue:config.blue alpha:1];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.frame = frame;
    layer.cornerRadius = MIN(frame.size.width, frame.size.height) * 0.22;
    layer.backgroundColor = [color colorWithAlphaComponent:0.03].CGColor;
    layer.shadowColor = color.CGColor;
    layer.shadowOpacity = (float)config.intensity;
    layer.shadowRadius = 2 + 14 * config.intensity;
    layer.shadowOffset = CGSizeZero;
    layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:layer.bounds
        cornerRadius:layer.cornerRadius].CGPath;
    [CATransaction commit];
}
static void Schedule(SBIconView *view) {
    if (NSThread.isMainThread) Update(view);
    else dispatch_async(dispatch_get_main_queue(), ^{ Update(view); });
}
static void Layout(SBIconView *self, SEL cmd) { originalLayout(self, cmd); Schedule(self); }
static void Window(SBIconView *self, SEL cmd) { originalWindow(self, cmd); Schedule(self); }
static void SetIcon(SBIconView *self, SEL cmd, id icon) {
    originalSetIcon(self, cmd, icon); Schedule(self);
}
static void Accessories(SBIconView *self, SEL cmd, id icon) {
    originalAccessories(self, cmd, icon); Schedule(self);
}
static void Notify(CFNotificationCenterRef center, void *observer, CFStringRef name,
                   const void *object, CFDictionaryRef info) {
    BOOL stop = CFEqual(name, FL_STOP);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (stop) {
            stopped = YES;
            for (SBIconView *view in views.allObjects) Remove(view);
            [views removeAllObjects];
            CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), &observerKey);
        } else if (!stopped) {
            config = FLReadConfig();
            for (SBIconView *view in views.allObjects) Update(view);
        }
    });
}
__attribute__((constructor)) static void Initialize(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = NSClassFromString(@"SBIconView");
        if (!cls || !Signature(cls, @selector(icon), "@", 2)
            || !Signature(cls, @selector(_iconImageView), "@", 2)
            || !Signature(cls, @selector(isFolderIcon), "B", 2)
            || !Signature(cls, @selector(layoutSubviews), "v", 2)
            || !Signature(cls, @selector(didMoveToWindow), "v", 2)
            || !Signature(cls, NSSelectorFromString(@"setIcon:"), "v", 3, "@")
            || !Signature(cls, NSSelectorFromString(@"iconAccessoriesDidUpdate:"), "v", 3, "@")) return;
        views = [NSHashTable weakObjectsHashTable];
        config = FLReadConfig();
        CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(center, &observerKey, Notify, FL_CHANGED, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, &observerKey, Notify, FL_STOP, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        MSHookMessageEx(cls, @selector(layoutSubviews), (IMP)Layout, (IMP *)&originalLayout);
        MSHookMessageEx(cls, @selector(didMoveToWindow), (IMP)Window, (IMP *)&originalWindow);
        MSHookMessageEx(cls, NSSelectorFromString(@"setIcon:"), (IMP)SetIcon, (IMP *)&originalSetIcon);
        MSHookMessageEx(cls, NSSelectorFromString(@"iconAccessoriesDidUpdate:"), (IMP)Accessories, (IMP *)&originalAccessories);
    });
}
