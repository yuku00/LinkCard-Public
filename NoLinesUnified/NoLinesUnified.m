#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <string.h>

static BOOL calendar, clockApp, photos, weather, sileo;
static BOOL Thin(CGRect r, CGFloat h, CGFloat w) {
    return r.size.height > 0 && r.size.height <= h && r.size.width > w;
}
static void Hide(UIView *v) { v.hidden = YES; v.alpha = 0; }
static BOOL PlainLine(UIView *v, CGRect r) {
    return [v isMemberOfClass:UIView.class] && Thin(r, 1, 100);
}
static BOOL HasMethod(Class c, SEL s) { return c && class_getInstanceMethod(c, s); }
// Each registration owns its original IMP; inherited methods are handled by Substrate.
static void After(const char *name, const char *method, void (^action)(id)) {
    Class c = objc_getClass(name); SEL s = sel_registerName(method);
    if (!HasMethod(c, s)) return;
    __block void (*original)(id, SEL);
    IMP replacement = imp_implementationWithBlock(^(id obj) {
        original(obj, s); action(obj);
    });
    MSHookMessageEx(c, s, replacement, (IMP *)&original);
}
static void BoolSetter(const char *name, const char *method, BOOL value) {
    Class c = objc_getClass(name); SEL s = sel_registerName(method);
    if (!HasMethod(c, s)) return;
    __block void (*original)(id, SEL, BOOL);
    IMP replacement = imp_implementationWithBlock(^(id obj, BOOL ignored) {
        original(obj, s, value);
    });
    MSHookMessageEx(c, s, replacement, (IMP *)&original);
}
static void ZeroFloat(const char *name, const char *method) {
    Class c = objc_getClass(name); SEL s = sel_registerName(method);
    if (!HasMethod(c, s)) return;
    __block void (*original)(id, SEL, CGFloat);
    IMP replacement = imp_implementationWithBlock(^(id obj, CGFloat ignored) {
        original(obj, s, 0);
    });
    MSHookMessageEx(c, s, replacement, (IMP *)&original);
}
static void ZeroStyle(const char *name) {
    Class c = objc_getClass(name); SEL s = @selector(setSeparatorStyle:);
    if (!HasMethod(c, s)) return;
    __block void (*original)(id, SEL, NSInteger);
    IMP replacement = imp_implementationWithBlock(^(id obj, NSInteger ignored) {
        original(obj, s, 0);
    });
    MSHookMessageEx(c, s, replacement, (IMP *)&original);
}
static void ClearColor(const char *name, const char *method) {
    Class c = objc_getClass(name); SEL s = sel_registerName(method);
    if (!HasMethod(c, s)) return;
    __block void (*original)(id, SEL, UIColor *);
    IMP replacement = imp_implementationWithBlock(^(id obj, UIColor *ignored) {
        original(obj, s, UIColor.clearColor);
    });
    MSHookMessageEx(c, s, replacement, (IMP *)&original);
}
static void Replace(const char *name, const char *method, id block) {
    Class c = objc_getClass(name); SEL s = sel_registerName(method);
    if (HasMethod(c, s)) MSHookMessageEx(c, s, imp_implementationWithBlock(block), NULL);
}
static void ForceHidden(const char *name, const char *lifecycle) {
    BoolSetter(name, "setHidden:", YES);
    ZeroFloat(name, "setAlpha:");
    After(name, lifecycle, ^(UIView *v) { Hide(v); });
}
static void InstallPlainSetters(void) {
    Class c = UIView.class;
    SEL frame = @selector(setFrame:), bounds = @selector(setBounds:);
    __block void (*of)(id, SEL, CGRect), (*ob)(id, SEL, CGRect);
    MSHookMessageEx(c, frame, imp_implementationWithBlock(^(UIView *v, CGRect r) {
        of(v, frame, r); if (PlainLine(v, r)) v.layer.opacity = 0;
    }), (IMP *)&of);
    MSHookMessageEx(c, bounds, imp_implementationWithBlock(^(UIView *v, CGRect r) {
        ob(v, bounds, r); if (PlainLine(v, r)) v.layer.opacity = 0;
    }), (IMP *)&ob);
    SEL color = @selector(setBackgroundColor:), alpha = @selector(setAlpha:), hidden = @selector(setHidden:);
    __block void (*oc)(id, SEL, UIColor *), (*oa)(id, SEL, CGFloat), (*oh)(id, SEL, BOOL);
    MSHookMessageEx(c, color, imp_implementationWithBlock(^(UIView *v, UIColor *x) {
        oc(v, color, PlainLine(v, v.frame) ? UIColor.clearColor : x);
    }), (IMP *)&oc);
    MSHookMessageEx(c, alpha, imp_implementationWithBlock(^(UIView *v, CGFloat x) {
        oa(v, alpha, PlainLine(v, v.frame) ? 0 : x);
    }), (IMP *)&oa);
    MSHookMessageEx(c, hidden, imp_implementationWithBlock(^(UIView *v, BOOL x) {
        oh(v, hidden, PlainLine(v, v.frame) ? YES : x);
    }), (IMP *)&oh);
    if (calendar) After("UIView", "didMoveToWindow", ^(UIView *v) {
        if (PlainLine(v, v.frame)) { v.layer.opacity = 0; v.backgroundColor = UIColor.clearColor; }
    });
}
__attribute__((constructor)) static void Init(void) {
    @autoreleasepool {
        NSString *b = NSBundle.mainBundle.bundleIdentifier;
        if (!b) return;
        BOOL spring = [b isEqualToString:@"com.apple.springboard"];
        BOOL settings = [b isEqualToString:@"com.apple.Preferences"];
        BOOL notes = [b isEqualToString:@"com.apple.mobilenotes"];
        BOOL reminders = [b isEqualToString:@"com.apple.reminders"];
        BOOL files = [b isEqualToString:@"com.apple.DocumentsApp"];
        BOOL phone = [b isEqualToString:@"com.apple.mobilephone"];
        BOOL messages = [b isEqualToString:@"com.apple.MobileSMS"];
        calendar = [b isEqualToString:@"com.apple.mobilecal"];
        clockApp = [b isEqualToString:@"com.apple.mobiletimer"];
        photos = [b isEqualToString:@"com.apple.mobileslideshow"];
        weather = [b isEqualToString:@"com.apple.weather"];
        sileo = [b isEqualToString:@"org.coolstar.SileoStore"];
        Class list = objc_getClass("_UICollectionViewListSeparatorView");
        SEL apply = @selector(applyLayoutAttributes:);
        if (HasMethod(list, apply)) {
            __block void (*original)(id, SEL, id);
            MSHookMessageEx(list, apply, imp_implementationWithBlock(^(UIView *v, id a) {
                original(v, apply, a); Hide(v);
            }), (IMP *)&original);
        }
        After("_UICollectionViewListSeparatorView", "didMoveToSuperview", ^(UIView *v) { Hide(v); });
        ClearColor("_UITableViewCellSeparatorView", "setBackgroundColor:");
        ZeroFloat("_UITableViewCellSeparatorView", "setAlpha:");
        BoolSetter("_UITableViewCellSeparatorView", "setHidden:", YES);
        After("UICollectionReusableView", "layoutSubviews", ^(UIView *v) {
            if (Thin(v.bounds, 1, -1)) Hide(v);
        });
        Replace("_UIAlertControllerInterfaceActionGroupView", "_shouldShowSeparatorAboveActionsSequenceView", ^BOOL(id obj) { return NO; });
        Replace("_UIInterfaceActionSeparatableSequenceView", "_addSeparatorToStackAndMutableArray:preferSectionStyle:", ^(id obj, id array, BOOL section) {});
        ZeroFloat("_UIInterfaceActionBlankSeparatorView", "setConstantAxisDimension:");
        if (spring || settings) {
            ZeroFloat("UICalloutBarButton", "setDividerOffset:");
            Replace("UITableViewCell", "_updateSeparatorContent", ^(id obj) {});
            ZeroStyle("_UICollectionViewListLayoutSectionConfiguration");
            // Original PurifyLine suppresses ALL filters. Limit it to line-sized views.
            Class c = objc_getClass("_UIVisualEffectContentView");
            SEL s = sel_registerName("applyRequestedFilterEffects");
            if (HasMethod(c, s)) {
                __block void (*original)(id, SEL);
                MSHookMessageEx(c, s, imp_implementationWithBlock(^(UIView *v) {
                    if (Thin(v.bounds, 1.5, -1)) Hide(v); else original(v, s);
                }), (IMP *)&original);
            }
        }
        if (notes || reminders || files || phone) {
            BoolSetter("UIScrollView", "setShowsVerticalScrollIndicator:", NO);
            BoolSetter("UIScrollView", "setShowsHorizontalScrollIndicator:", NO);
            After("UIScrollView", "layoutSubviews", ^(UIScrollView *v) {
                v.showsVerticalScrollIndicator = NO; v.showsHorizontalScrollIndicator = NO;
            });
        }
        if (notes || reminders || calendar || messages || photos || files || phone) {
            void (^effect)(UIView *) = ^(UIView *v) {
                if (Thin(v.bounds, 1.5, -1)) { Hide(v); v.layer.opacity = 0; }
            };
            After("_UIVisualEffectContentView", "layoutSubviews", effect);
            After("UIVisualEffectView", "layoutSubviews", effect);
        }
        if (notes || weather || files) {
            ForceHidden("_UIContextMenuReusableSeparatorView", "layoutSubviews");
            // Hide only: unlike the original, do not collapse frame height to zero.
        }
        if (calendar || messages) ForceHidden("_UIBarBackgroundShadowContentImageView", "didMoveToWindow");
        if (calendar || clockApp) InstallPlainSetters();
        if (calendar) {
            ClearColor("RowSeparatorView", "setBackgroundColor:");
            ZeroFloat("RowSeparatorView", "setAlpha:");
            BoolSetter("RowSeparatorView", "setHidden:", YES);
        }
        if (clockApp) {
            ZeroStyle("UITableView"); ClearColor("UITableView", "setSeparatorColor:");
            After("UITableView", "didMoveToWindow", ^(UITableView *v) {
                v.separatorStyle = UITableViewCellSeparatorStyleNone; v.separatorColor = UIColor.clearColor;
            });
            After("_UITableViewCellSeparatorView", "didMoveToWindow", ^(UIView *v) {
                v.backgroundColor = UIColor.clearColor; Hide(v);
            });
        }
        // One UIView layout hook, not four independent hooks on the same selector.
        if (weather || photos || sileo) After("UIView", "layoutSubviews", ^(UIView *v) {
            const char *name = object_getClassName(v);
            BOOL match = weather && strstr(name, "UIGraphicsView") && Thin(v.bounds, 0.5, -1);
            match |= photos && [v isMemberOfClass:UIView.class] && Thin(v.bounds, 1.5, 100);
            match |= sileo && (strstr(name, "SileoSeparatorView") ||
                     ([v isMemberOfClass:UIView.class] && Thin(v.bounds, 1, -1)));
            if (match) { Hide(v); if (photos) { v.layer.opacity = 0; v.backgroundColor = UIColor.clearColor; } }
        });
        if (sileo) After("_UIInterfaceActionVibrantSeparatorView", "layoutSubviews", ^(UIView *v) { Hide(v); });
        if (phone) After("CNContactListHeaderView", "layoutSubviews", ^(UIView *v) {
            // Original masks the top 5pt strip. Keep only this visual rule, not tab removal.
            if (v.bounds.size.height <= 5) return;
            CAShapeLayer *mask = [v.layer.mask isKindOfClass:CAShapeLayer.class] ? (id)v.layer.mask : nil;
            if (v.layer.mask && !mask) return; // Do not replace an unrelated existing mask.
            if (!mask) { mask = [CAShapeLayer layer]; v.layer.mask = mask; }
            mask.path = [UIBezierPath bezierPathWithRect:CGRectMake(0, 5, v.bounds.size.width, v.bounds.size.height - 5)].CGPath;
        });
    }
}
