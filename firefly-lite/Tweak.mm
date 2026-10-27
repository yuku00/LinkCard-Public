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
static void (*originalIconImageChanged)(SBIconView *, SEL, id);

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
#import "Shared/FLIconColor.h"
@interface FLHaloLayer : CALayer
@property(nonatomic) FLRGB rgb;
@property(nonatomic) double intensity;
@property(nonatomic) BOOL styled;
@end
@implementation FLHaloLayer
@end
static void ClearColor(SBIconView *view) {
    FLIconColorState *state = objc_getAssociatedObject(view, &colorKey);
    if (state.imageView && objc_getAssociatedObject(state.imageView, &imageOwnerKey) == state)
        objc_setAssociatedObject(state.imageView, &imageOwnerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &colorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void Remove(SBIconView *view) {
    ClearColor(view);
    CALayer *layer = objc_getAssociatedObject(view, &layerKey);
    [layer removeFromSuperlayer];
    objc_setAssociatedObject(view, &layerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void Update(SBIconView *view) {
    NSCAssert(NSThread.isMainThread, @"UI must be updated on main thread");
    if (stopped) { Remove(view); return; }
    if (!config.enabled) { Remove(view); return; }
    if (!config.followIconColor) ClearColor(view);
    if (!view.window) {
        CALayer *halo = objc_getAssociatedObject(view, &layerKey);
        halo.hidden = YES; // Keep same-icon cache and the single halo while offscreen.
        return;
    }
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
    if (image == view || ![image isDescendantOfView:view]) { Remove(view); return; }
    CGRect frame = [image convertRect:image.bounds toView:view];
    if (CGRectIsEmpty(frame) || CGRectIsInfinite(frame) || CGRectIsNull(frame)
        || !isfinite(frame.origin.x) || !isfinite(frame.origin.y)
        || !isfinite(frame.size.width) || !isfinite(frame.size.height)) { Remove(view); return; }
    FLHaloLayer *layer = objc_getAssociatedObject(view, &layerKey);
    if (!layer) {
        layer = [FLHaloLayer layer];
        layer.name = @"dev.fireflylite.badgeglow.halo";
        objc_setAssociatedObject(view, &layerKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view.layer insertSublayer:layer atIndex:0];
    }
    FLRGB rgb = IconColor(view, image, icon, (FLRGB){config.red, config.green, config.blue});
    BOOL pathChanged = FLNeedsHaloPath(layer.shadowPath != NULL, CGSizeEqualToSize(layer.bounds.size, frame.size));
    BOOL styleChanged = !layer.styled || layer.intensity != config.intensity
        || layer.rgb.red != rgb.red || layer.rgb.green != rgb.green || layer.rgb.blue != rgb.blue;
    if (!pathChanged && !styleChanged && CGRectEqualToRect(layer.frame, frame) && !layer.hidden) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (layer.hidden) layer.hidden = NO;
    if (!CGRectEqualToRect(layer.frame, frame)) layer.frame = frame;
    if (pathChanged) {
        layer.cornerRadius = MIN(frame.size.width, frame.size.height) * 0.22;
        layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:layer.bounds
            cornerRadius:layer.cornerRadius].CGPath;
    }
    if (styleChanged) {
        UIColor *color = [UIColor colorWithRed:rgb.red green:rgb.green blue:rgb.blue alpha:1];
        layer.backgroundColor = [color colorWithAlphaComponent:0.03].CGColor;
        layer.shadowColor = color.CGColor;
        layer.shadowOpacity = (float)config.intensity;
        layer.shadowRadius = 2 + 14 * config.intensity;
        layer.shadowOffset = CGSizeZero;
        layer.rgb = rgb; layer.intensity = config.intensity; layer.styled = YES;
    }
    [CATransaction commit];
}
static void Schedule(SBIconView *view) {
    if (NSThread.isMainThread) Update(view);
    else dispatch_async(dispatch_get_main_queue(), ^{ Update(view); });
}
static void Layout(SBIconView *self, SEL cmd) { originalLayout(self, cmd); Schedule(self); }
static void Window(SBIconView *self, SEL cmd) {
    originalWindow(self, cmd);
    if (NSThread.isMainThread) { Update(self); if (self.window) RefreshOwner(self); }
    else dispatch_async(dispatch_get_main_queue(), ^{ Update(self); if (self.window) RefreshOwner(self); });
}
static void SetIcon(SBIconView *self, SEL cmd, id icon) {
    if ([self icon] != icon) ClearColor(self);
    originalSetIcon(self, cmd, icon); Schedule(self);
}
static void Accessories(SBIconView *self, SEL cmd, id icon) {
    originalAccessories(self, cmd, icon); Schedule(self);
}
static void IconImageChanged(SBIconView *self, SEL cmd, id icon) {
    originalIconImageChanged(self, cmd, icon);
    if (NSThread.isMainThread) RefreshOwner(self);
    else dispatch_async(dispatch_get_main_queue(), ^{ RefreshOwner(self); });
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
        InstallImageHooks();
        config = FLReadConfig();
        CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(center, &observerKey, Notify, FL_CHANGED, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, &observerKey, Notify, FL_STOP, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        SEL imageChanged = NSSelectorFromString(@"iconImageDidUpdate:");
        if (Signature(cls, imageChanged, "v", 3, "@"))
            MSHookMessageEx(cls, imageChanged, (IMP)IconImageChanged, (IMP *)&originalIconImageChanged);
        MSHookMessageEx(cls, @selector(layoutSubviews), (IMP)Layout, (IMP *)&originalLayout);
        MSHookMessageEx(cls, @selector(didMoveToWindow), (IMP)Window, (IMP *)&originalWindow);
        MSHookMessageEx(cls, NSSelectorFromString(@"setIcon:"), (IMP)SetIcon, (IMP *)&originalSetIcon);
        MSHookMessageEx(cls, NSSelectorFromString(@"iconAccessoriesDidUpdate:"), (IMP)Accessories, (IMP *)&originalAccessories);
    });
}
