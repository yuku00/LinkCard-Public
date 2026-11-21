//
//  DateInfoTapFix.x - companion fix for the DateInfo (快捷时间胶囊) tweak.
//
//  Problem
//  -------
//  The DateInfo tweak puts a transparent tap target over the status-bar clock
//  hotspot and attaches a UITapGestureRecognizer whose target is a
//  DIClockTapTarget instance. On the affected device the target exists, the
//  hotspot geometry is right and the target reports itself enabled, yet tapping
//  the clock never opens the bubble.
//
//  What this does
//  --------------
//  It does not modify the DateInfo binary and it does not hook DateInfo. After
//  the status bar lays out it looks for the DateInfo gesture target; when that
//  target is present (which proves the tweak is loaded and enabled) it puts a
//  transparent tap area of its own on the status bar window, over the same
//  rectangle the tweak intends. A tap there calls the tweak's own -handleTap:
//  with the tweak's own recognizer, so the bubble shown is the DateInfo bubble.
//
//  If no window becomes visible shortly after that call, a small self-drawn
//  bubble is shown instead, so the tap is never a dead end.
//
//  Safety: no logging to disk, no network, no preference writes, no background
//  work. Every UIKit call is wrapped so a failure leaves the status bar alone.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define DI_TAPFIX_LOG(fmt, ...) NSLog((@"[DateInfoTapFix] " fmt), ##__VA_ARGS__)

static NSString *const kDIHotspotActionName = @"handleTap:";
static const NSInteger kDIStateEnded = 3;
static const CGFloat kDIFallbackDelay = 0.45;
static const NSTimeInterval kDIFallbackHideDelay = 4.0;

#pragma mark - Runtime helpers

static Class DITargetClass(void) {
    static Class cached = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cached = NSClassFromString(@"DIClockTapTarget");
    });
    return cached;
}

static BOOL DIObjectIsOriginalTarget(id object) {
    Class targetClass = DITargetClass();
    if (!object || !targetClass) {
        return NO;
    }
    if (object_getClass(object) == targetClass) {
        return YES;
    }
    const char *name = class_getName(object_getClass(object));
    return name && strcmp(name, "DIClockTapTarget") == 0;
}

static id DIReadObjectIvar(id object, const char *ivarName) {
    if (!object || !ivarName) {
        return nil;
    }
    Ivar ivar = class_getInstanceVariable(object_getClass(object), ivarName);
    if (!ivar) {
        return nil;
    }
    @try {
        return object_getIvar(object, ivar);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

// Reads a ":" typed ivar without trusting it: on arm64e the stored value may be
// signed, so it is reported only when the pointer is a mapped selector.
static SEL DIReadActionIvar(id object) {
    if (!object) {
        return NULL;
    }
    Ivar ivar = class_getInstanceVariable(object_getClass(object), "_action");
    if (!ivar) {
        return NULL;
    }
    SEL stored = NULL;
    const char *slot = (const char *)(__bridge const void *)object + ivar_getOffset(ivar);
    @try {
        memcpy(&stored, slot, sizeof(stored));
    } @catch (__unused NSException *exception) {
        return NULL;
    }
    if (stored && sel_isMapped(stored)) {
        return stored;
    }
    return NULL;
}

static BOOL DIFindTargetOnRecognizer(UIGestureRecognizer *recognizer, id *outTarget, SEL *outAction) {
    if (!recognizer) {
        return NO;
    }
    id targets = DIReadObjectIvar(recognizer, "_targets");
    if (![targets isKindOfClass:[NSArray class]]) {
        return NO;
    }
    for (id pair in (NSArray *)targets) {
        id candidate = DIReadObjectIvar(pair, "_target");
        if (!DIObjectIsOriginalTarget(candidate)) {
            continue;
        }
        if (outTarget) {
            *outTarget = candidate;
        }
        if (outAction) {
            *outAction = DIReadActionIvar(pair);
        }
        return YES;
    }
    return NO;
}

static UIView *DIFindHostView(UIView *root, UIGestureRecognizer **outRecognizer, id *outTarget) {
    if (!root) {
        return nil;
    }
    for (UIGestureRecognizer *recognizer in root.gestureRecognizers) {
        id target = nil;
        SEL action = NULL;
        if (DIFindTargetOnRecognizer(recognizer, &target, &action)) {
            if (outRecognizer) {
                *outRecognizer = recognizer;
            }
            if (outTarget) {
                *outTarget = target;
            }
            return root;
        }
    }
    for (UIView *subview in root.subviews) {
        UIView *found = DIFindHostView(subview, outRecognizer, outTarget);
        if (found) {
            return found;
        }
    }
    return nil;
}

#pragma mark - Visible window snapshot

// Windows of the connected scenes, newest API first with a fallback for older
// systems. Deprecation warnings are silenced locally instead of globally.
static NSArray<UIWindow *> *DIAllWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    @try {
        UIApplication *application = [UIApplication sharedApplication];
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in application.connectedScenes) {
                if (![scene isKindOfClass:[UIWindowScene class]]) {
                    continue;
                }
                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    [windows addObject:window];
                }
            }
        }
        if (windows.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [windows addObjectsFromArray:application.windows];
#pragma clang diagnostic pop
        }
    } @catch (__unused NSException *exception) {
    }
    return windows;
}

static UIWindow *DIKeyWindow(void) {
    UIWindow *key = nil;
    @try {
        for (UIWindow *window in DIAllWindows()) {
            if (window.isKeyWindow) {
                key = window;
                break;
            }
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (!key) {
            key = [UIApplication sharedApplication].keyWindow;
        }
#pragma clang diagnostic pop
    } @catch (__unused NSException *exception) {
        key = nil;
    }
    return key;
}

static NSArray<NSString *> *DIWindowSnapshot(void) {
    NSMutableArray<NSString *> *snapshot = [NSMutableArray array];
    for (UIWindow *window in DIAllWindows()) {
        [snapshot addObject:[NSString stringWithFormat:@"%p:%d", (__bridge void *)window, window.hidden ? 1 : 0]];
    }
    return snapshot;
}

static BOOL DIWindowAppeared(NSArray<NSString *> *before) {
    NSSet<NSString *> *known = [NSSet setWithArray:before ?: @[]];
    for (NSString *entry in DIWindowSnapshot()) {
        if (![known containsObject:entry]) {
            NSRange separator = [entry rangeOfString:@":" options:NSBackwardsSearch];
            if (separator.location != NSNotFound &&
                [[entry substringFromIndex:separator.location + 1] isEqualToString:@"0"]) {
                return YES;
            }
        }
    }
    return NO;
}

#pragma mark - Calling the tweak's own action

// The tweak's -handleTap: acts only while the recognizer it receives reports the
// ended state, so the recognizer is moved to ended for the call and put back
// afterwards. Both steps go through KVC and performSelector so no private
// message is called blindly.
static BOOL DICallOriginalAction(id target, UIGestureRecognizer *recognizer) {
    if (!target || !recognizer) {
        return NO;
    }
    SEL action = NSSelectorFromString(kDIHotspotActionName);
    if (![target respondsToSelector:action]) {
        DI_TAPFIX_LOG(@"target does not respond to %@", kDIHotspotActionName);
        return NO;
    }

    NSNumber *savedState = nil;
    @try {
        savedState = [recognizer valueForKey:@"state"];
    } @catch (__unused NSException *exception) {
        savedState = nil;
    }

    BOOL stateChanged = NO;
    @try {
        [recognizer setValue:@(kDIStateEnded) forKey:@"state"];
        stateChanged = YES;
    } @catch (NSException *exception) {
        DI_TAPFIX_LOG(@"could not move recognizer to ended: %@", exception);
        stateChanged = NO;
    }

    BOOL called = NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    @try {
        [target performSelector:action withObject:recognizer];
        called = YES;
    } @catch (NSException *exception) {
        DI_TAPFIX_LOG(@"original action raised: %@", exception);
        called = NO;
    }
#pragma clang diagnostic pop

    if (stateChanged) {
        @try {
            [recognizer setValue:savedState ?: @(0) forKey:@"state"];
        } @catch (__unused NSException *exception) {
        }
    }
    return called;
}

#pragma mark - Fallback bubble

@interface DIFallbackBubble : UIView
+ (void)toggleInWindow:(UIWindow *)window;
+ (void)dismissFromWindow:(UIWindow *)window;
@end

@implementation DIFallbackBubble

+ (NSString *)bubbleText {
    NSDate *now = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.locale = [NSLocale currentLocale];
    dateFormatter.dateFormat = @"M月d日 EEEE";
    NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];
    timeFormatter.locale = [NSLocale currentLocale];
    timeFormatter.dateFormat = @"HH:mm";
    return [NSString stringWithFormat:@"%@\n%@", [dateFormatter stringFromDate:now], [timeFormatter stringFromDate:now]];
}

+ (void)toggleInWindow:(UIWindow *)window {
    if (!window) {
        return;
    }
    for (UIView *subview in [window.subviews copy]) {
        if ([subview isKindOfClass:[DIFallbackBubble class]]) {
            [subview removeFromSuperview];
            return;
        }
    }

    CGFloat width = 150.0;
    CGFloat height = 76.0;
    CGRect frame = CGRectMake((window.bounds.size.width - width) / 2.0, 8.0, width, height);
    DIFallbackBubble *bubble = [[DIFallbackBubble alloc] initWithFrame:frame];
    bubble.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.94];
    bubble.layer.cornerRadius = 16.0;
    bubble.layer.cornerCurve = kCACornerCurveContinuous;
    bubble.userInteractionEnabled = YES;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(bubble.bounds, 10.0, 8.0)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.numberOfLines = 2;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    label.text = [self bubbleText];
    [bubble addSubview:label];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBubbleTap:)];
    [bubble addGestureRecognizer:tap];

    [window addSubview:bubble];
    [self performSelector:@selector(dismissFromWindow:) withObject:window afterDelay:kDIFallbackHideDelay];
}

+ (void)handleBubbleTap:(UITapGestureRecognizer *)recognizer {
    UIWindow *window = recognizer.view.window;
    if (window) {
        [self dismissFromWindow:window];
    }
}

+ (void)dismissFromWindow:(UIWindow *)window {
    if (!window) {
        return;
    }
    for (UIView *subview in [window.subviews copy]) {
        if ([subview isKindOfClass:[DIFallbackBubble class]]) {
            [subview removeFromSuperview];
        }
    }
}

@end

#pragma mark - Transparent tap area on the status bar window

@interface DITapFixController : NSObject
@property (nonatomic, strong) UIView *tapArea;
@property (nonatomic, weak) UIGestureRecognizer *originalRecognizer;
@property (nonatomic, weak) id originalTarget;
+ (instancetype)shared;
- (void)updateFromForegroundView:(UIView *)foregroundView;
- (void)removeTapArea;
- (void)handleTapAreaGesture:(UITapGestureRecognizer *)recognizer;
@end

@implementation DITapFixController

+ (instancetype)shared {
    static DITapFixController *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[DITapFixController alloc] init];
    });
    return shared;
}

// The rectangle the tweak targets: centred on the clock, 74 x 38 points, two
// points below the top of the status bar foreground view.
- (CGRect)hotspotInForegroundView:(UIView *)foregroundView {
    CGRect bounds = foregroundView.bounds;
    if (bounds.size.width < 200.0) {
        return CGRectZero;
    }
    CGFloat topInset = 0.0;
    @try {
        topInset = foregroundView.safeAreaInsets.top;
    } @catch (__unused NSException *exception) {
        topInset = 0.0;
    }
    CGFloat factor = (topInset >= 40.0) ? 0.1633 : 0.107;
    CGFloat centerX = bounds.size.width * factor;
    return CGRectMake(centerX - 37.0, 2.0, 74.0, 38.0);
}

- (void)updateFromForegroundView:(UIView *)foregroundView {
    if (!foregroundView) {
        return;
    }
    UIGestureRecognizer *recognizer = nil;
    id target = nil;
    UIView *host = DIFindHostView(foregroundView, &recognizer, &target);
    if (!host || !recognizer || !target) {
        [self removeTapArea];
        return;
    }
    self.originalRecognizer = recognizer;
    self.originalTarget = target;

    UIWindow *window = host.window ?: foregroundView.window;
    if (!window) {
        return;
    }
    CGRect hotspot = [self hotspotInForegroundView:foregroundView];
    if (CGRectIsEmpty(hotspot)) {
        return;
    }
    CGRect inWindow = [foregroundView convertRect:hotspot toView:window];

    if (!self.tapArea) {
        UIView *area = [[UIView alloc] initWithFrame:inWindow];
        area.backgroundColor = [UIColor clearColor];
        area.opaque = NO;
        area.alpha = 1.0;
        area.userInteractionEnabled = YES;
        area.autoresizingMask = UIViewAutoresizingNone;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapAreaGesture:)];
        tap.numberOfTapsRequired = 1;
        tap.numberOfTouchesRequired = 1;
        tap.cancelsTouchesInView = NO;
        tap.delaysTouchesEnded = NO;
        [area addGestureRecognizer:tap];
        self.tapArea = area;
    }
    self.tapArea.frame = inWindow;
    if (self.tapArea.superview != window) {
        [self.tapArea removeFromSuperview];
        [window addSubview:self.tapArea];
    } else {
        [window bringSubviewToFront:self.tapArea];
    }
}

- (void)removeTapArea {
    if (self.tapArea) {
        [self.tapArea removeFromSuperview];
        self.tapArea = nil;
    }
}

- (void)handleTapAreaGesture:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) {
        return;
    }
    UIWindow *window = self.tapArea.window;
    UIGestureRecognizer *resolvedRecognizer = nil;
    id resolvedTarget = nil;
    UIView *host = DIFindHostView(window, &resolvedRecognizer, &resolvedTarget);
    if (!host || !resolvedRecognizer || !resolvedTarget) {
        resolvedRecognizer = self.originalRecognizer;
        resolvedTarget = self.originalTarget;
    }
    if (!resolvedTarget || !resolvedRecognizer) {
        DI_TAPFIX_LOG(@"no DateInfo tap target to forward to");
        return;
    }

    NSArray<NSString *> *before = DIWindowSnapshot();
    DICallOriginalAction(resolvedTarget, resolvedRecognizer);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDIFallbackDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (DIWindowAppeared(before)) {
            return;
        }
        UIWindow *anchor = window ?: DIKeyWindow();
        [DIFallbackBubble toggleInWindow:anchor];
    });
}

@end

#pragma mark - Hook

// Declared so the compiler knows the hooked class is a view; the real class is
// provided by UIKit at runtime.
@interface _UIStatusBarForegroundView : UIView
@end

%hook _UIStatusBarForegroundView

- (void)layoutSubviews {
    %orig;
    @try {
        [[DITapFixController shared] updateFromForegroundView:self];
    } @catch (NSException *exception) {
        DI_TAPFIX_LOG(@"layoutSubviews update raised: %@", exception);
    }
}

%end