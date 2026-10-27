#import "Shared/FLColor.h"

@interface FLIconColorState : NSObject
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, weak) id icon;
@property(nonatomic) FLRGB rgb;
@property(nonatomic) BOOL valid;
@end
@implementation FLIconColorState
@end
static char colorKey;
static dispatch_queue_t colorQueue;
static void Update(SBIconView *view);

static UIImage *DisplayedImage(UIView *view) {
    NSCAssert(NSThread.isMainThread, @"Read UIKit images only on main");
    if ([view isKindOfClass:UIImageView.class]) return ((UIImageView *)view).image;
    Class cls = NSClassFromString(@"SBIconImageView");
    SEL selector = NSSelectorFromString(@"displayedImage");
    if (!cls || ![view isKindOfClass:cls] || !Signature(view.class, selector, "@", 2)) return nil;
    id image = ((id (*)(id, SEL))[view methodForSelector:selector])(view, selector);
    return [image isKindOfClass:UIImage.class] ? image : nil;
}
static FLRGB IconColor(SBIconView *view, UIView *imageView, id icon, FLRGB manual) {
    if (!config.followIconColor) {
        objc_setAssociatedObject(view, &colorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return manual;
    }
    UIImage *image = DisplayedImage(imageView);
    FLIconColorState *state = objc_getAssociatedObject(view, &colorKey);
    if (!state || state.image != image || state.icon != icon) {
        state = [FLIconColorState new];
        state.image = image; state.icon = icon;
        objc_setAssociatedObject(view, &colorKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGImageRef cg = image.CGImage;
        // shortcut: non-CGImage and unusually large images fall back; expand only with device evidence.
        if (cg && CGImageGetWidth(cg) <= 1024 && CGImageGetHeight(cg) <= 1024) {
            CGImageRetain(cg);
            __weak SBIconView *weakView = view;
            dispatch_async(colorQueue, ^{
                uint8_t pixels[24 * 24 * 4] = {};
                CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
                CGContextRef context = CGBitmapContextCreate(pixels, 24, 24, 8, 24 * 4, space,
                    kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
                CGColorSpaceRelease(space);
                FLRGB rgb = {};
                BOOL valid = NO;
                if (context) {
                    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
                    CGContextDrawImage(context, CGRectMake(0, 0, 24, 24), cg);
                    valid = FLRepresentativeColor(pixels, 576, &rgb);
                    CGContextRelease(context);
                }
                CGImageRelease(cg);
                dispatch_async(dispatch_get_main_queue(), ^{
                    SBIconView *owner = weakView;
                    if (!owner || stopped || objc_getAssociatedObject(owner, &colorKey) != state) return;
                    state.rgb = rgb; state.valid = valid;
                    Update(owner);
                });
            });
        }
    }
    return FLChooseColor(config.followIconColor, state.valid, state.rgb, manual);
}
// Image callbacks are optional and independently signature-gated; never gate the old halo.
static void (*originalImageUpdate)(id, SEL, bool);
static void (*originalImageLoaded)(id, SEL, id);
static void RefreshImage(id imageView) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (stopped || !config.followIconColor) return;
        for (SBIconView *view in views.allObjects) {
            if ([view _iconImageView] != imageView) continue;
            // UIImage is immutable: unchanged identity reuses success AND failure cache.
            Update(view);
        }
    });
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
