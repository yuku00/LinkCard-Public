#import "Shared/FLColor.h"
#import "Shared/FLSamplePolicy.h"

@interface FLIconColorState : NSObject
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, strong) id contents;
@property(nonatomic, weak) UIView *imageView;
@property(nonatomic, weak) SBIconView *owner;
@property(nonatomic, weak) id icon;
@property(nonatomic) FLRGB rgb;
@property(nonatomic) BOOL valid, refreshPending, sampled;
@end
@implementation FLIconColorState
@end
static char colorKey, imageOwnerKey;
static dispatch_queue_t colorQueue;
static void Update(SBIconView *view);
static void ClearColor(SBIconView *view);

static UIImage *DisplayedImage(UIView *view) {
    NSCAssert(NSThread.isMainThread, @"Read UIKit images only on main");
    // contentsImage is the original tweak's accessor; verify the runtime ABI first.
    for (NSString *name in @[@"contentsImage", @"displayedImage"]) {
        SEL selector = NSSelectorFromString(name);
        if (!Signature(view.class, selector, "@", 2)) continue;
        id image = ((id (*)(id, SEL))[view methodForSelector:selector])(view, selector);
        if ([image isKindOfClass:UIImage.class] && ((UIImage *)image).CGImage) return image;
    }
    UIImage *image = [view isKindOfClass:UIImageView.class] ? ((UIImageView *)view).image : nil;
    return [image isKindOfClass:UIImage.class] && image.CGImage ? image : nil;
}
static void QueueColorRefresh(SBIconView *view, FLIconColorState *state) {
    if (state.refreshPending || stopped || !config.enabled || !config.followIconColor) return;
    state.refreshPending = YES;
    __weak SBIconView *weakView = view;
    dispatch_async(dispatch_get_main_queue(), ^{
        state.refreshPending = NO;
        SBIconView *owner = weakView;
        if (!owner || !owner.window || stopped || !config.enabled || !config.followIconColor
            || objc_getAssociatedObject(owner, &colorKey) != state || [owner icon] != state.icon) return;
        UIView *imageView = state.imageView;
        if (!imageView) return;
        UIImage *image = DisplayedImage(imageView);
        CGImageRef cg = image.CGImage;
        id contents = imageView.layer.contents;
        if (!cg && contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID())
            cg = (__bridge CGImageRef)contents;
        // Compare the selected immutable CGImage, not changing UIImage wrappers/bounds.
        id source = (__bridge id)cg;
        BOOL same = state.contents == source;
        if (!FLNeedsIconSample(state.sampled, same, NO)) return;
        state.image = image; state.contents = source; state.sampled = YES; state.valid = NO;
        if (!cg || !CGImageGetWidth(cg) || !CGImageGetHeight(cg)) { Update(owner); return; }
        CGImageRetain(cg);
        dispatch_async(colorQueue, ^{
            uint8_t pixels[24 * 24 * 4] = {};
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef context = CGBitmapContextCreate(pixels, 24, 24, 8, 24 * 4, space,
                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
            CGColorSpaceRelease(space);
            FLRGB rgb = {};
            BOOL valid = NO;
            if (context) {
                CGContextDrawImage(context, CGRectMake(0, 0, 24, 24), cg);
                valid = FLRepresentativeColor(pixels, 576, &rgb);
                CGContextRelease(context);
            }
            CGImageRelease(cg);
            dispatch_async(dispatch_get_main_queue(), ^{
                SBIconView *target = weakView;
                if (!target || state.contents != source || !FLAcceptIconSample(
                    objc_getAssociatedObject(target, &colorKey) == state,
                    [target icon] == state.icon, !stopped && config.enabled && config.followIconColor)) return;
                state.rgb = rgb; state.valid = valid;
                Update(target);
            });
        });
    });
}
static FLRGB IconColor(SBIconView *view, UIView *imageView, id icon, FLRGB manual) {
    if (!config.followIconColor) return manual;
    FLIconColorState *state = objc_getAssociatedObject(view, &colorKey);
    if (!state || state.icon != icon || state.imageView != imageView) {
        ClearColor(view);
        state = [FLIconColorState new];
        state.owner = view; state.icon = icon; state.imageView = imageView;
        objc_setAssociatedObject(view, &colorKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(imageView, &imageOwnerKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        QueueColorRefresh(view, state);
    }
    return FLChooseColor(config.followIconColor, state.valid, state.rgb, manual);
}
// Optional image hooks remain signature-gated; public layer fallback needs no private getter.
static void (*originalImageUpdate)(id, SEL, bool);
static void (*originalImageLoaded)(id, SEL, id);
static void RefreshOwner(SBIconView *view) {
    if (stopped || !config.enabled || !config.followIconColor) return;
    Update(view);
    FLIconColorState *state = objc_getAssociatedObject(view, &colorKey);
    if (state) QueueColorRefresh(view, state);
}
static void RefreshImage(id imageView) {
    void (^refresh)(void) = ^{
        FLIconColorState *state = objc_getAssociatedObject(imageView, &imageOwnerKey);
        SBIconView *owner = state.owner;
        if (owner && objc_getAssociatedObject(owner, &colorKey) == state) RefreshOwner(owner);
    };
    if (NSThread.isMainThread) refresh();
    else dispatch_async(dispatch_get_main_queue(), refresh);
}
static void ImageUpdate(id self, SEL cmd, bool animated) {
    originalImageUpdate(self, cmd, animated); RefreshImage(self);
}
static void ImageLoaded(id self, SEL cmd, id icon) {
    originalImageLoaded(self, cmd, icon); RefreshImage(self);
}
static void InstallImageHooks(void) {
    colorQueue = dispatch_queue_create("dev.fireflylite.badgeglow.color", DISPATCH_QUEUE_SERIAL);
    Class cls = NSClassFromString(@"SBIconImageView");
    SEL update = NSSelectorFromString(@"updateImageAnimated:");
    SEL loaded = NSSelectorFromString(@"didEndAsynchronousImageLoadForIcon:");
    if (Signature(cls, update, "v", 3, "B"))
        MSHookMessageEx(cls, update, (IMP)ImageUpdate, (IMP *)&originalImageUpdate);
    if (Signature(cls, loaded, "v", 3, "@"))
        MSHookMessageEx(cls, loaded, (IMP)ImageLoaded, (IMP *)&originalImageLoaded);
}
