#import "Shared/FLColor.h"
#import "Shared/FLSamplePolicy.h"

@interface FLIconColorState : NSObject
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, strong) id contents;
@property(nonatomic, weak) UIView *imageView;
@property(nonatomic, weak) id icon;
@property(nonatomic) CGRect bounds;
@property(nonatomic) FLRGB rgb;
@property(nonatomic) BOOL valid, localCapture, dirty, refreshPending;
@property(nonatomic) NSUInteger retries;
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
// UIKit/CA access stays on main; the worker receives only a 24x24 immutable bitmap.
static UIImage *IconThumbnail(UIView *imageView, UIImage *image, BOOL *localCapture) {
    NSCAssert(NSThread.isMainThread, @"Capture icon on main");
    CGRect bounds = imageView.bounds;
    if (CGRectIsEmpty(bounds) || !isfinite(bounds.size.width) || !isfinite(bounds.size.height)
        || !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y)) return nil;
    CGImageRef cg = image.CGImage;
    *localCapture = !cg;
    id contents = imageView.layer.contents;
    if (!cg && contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID())
        cg = (__bridge CGImageRef)contents;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(24, 24), NO, 1);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        if (cg) {
            [[UIImage imageWithCGImage:cg] drawInRect:CGRectMake(0, 0, 24, 24)];
        } else {
            CGContextScaleCTM(ctx, 24 / bounds.size.width, 24 / bounds.size.height);
            CGContextTranslateCTM(ctx, -bounds.origin.x, -bounds.origin.y);
            // Only _iconImageView's subtree: the sibling halo is never captured.
            [imageView.layer renderInContext:ctx];
        }
    }
    UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return thumbnail;
}
static void QueueColorRefresh(SBIconView *view, FLIconColorState *state) {
    if (state.refreshPending) return;
    state.refreshPending = YES;
    __weak SBIconView *weakView = view;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SBIconView *owner = weakView;
        if (!owner || stopped || !config.followIconColor || objc_getAssociatedObject(owner, &colorKey) != state) return;
        state.refreshPending = NO;
        state.dirty = YES;
        Update(owner);
    });
}
static FLRGB IconColor(SBIconView *view, UIView *imageView, id icon, FLRGB manual) {
    if (!config.followIconColor) {
        objc_setAssociatedObject(view, &colorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return manual;
    }
    UIImage *image = DisplayedImage(imageView);
    id contents = imageView.layer.contents;
    FLIconColorState *state = objc_getAssociatedObject(view, &colorKey);
    BOOL same = state && state.image == image && state.icon == icon && state.imageView == imageView
        && state.contents == contents && CGRectEqualToRect(state.bounds, imageView.bounds);
    if (FLNeedsIconSample(state != nil, same, state.dirty)) {
        NSUInteger retries = same ? state.retries : 0;
        state = [FLIconColorState new];
        state.image = image; state.icon = icon; state.imageView = imageView;
        state.contents = contents; state.bounds = imageView.bounds; state.retries = retries;
        objc_setAssociatedObject(view, &colorKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BOOL localCapture = NO;
        UIImage *thumbnail = IconThumbnail(imageView, image, &localCapture);
        state.localCapture = localCapture;
        CGImageRef cg = thumbnail.CGImage;
        if (cg) CGImageRetain(cg);
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
                if (cg) {
                    CGContextDrawImage(context, CGRectMake(0, 0, 24, 24), cg);
                    valid = FLRepresentativeColor(pixels, 576, &rgb);
                }
                CGContextRelease(context);
            }
            if (cg) CGImageRelease(cg);
            dispatch_async(dispatch_get_main_queue(), ^{
                SBIconView *owner = weakView;
                if (!owner || !FLAcceptIconSample(objc_getAssociatedObject(owner, &colorKey) == state,
                    [owner icon] == state.icon, !stopped && config.followIconColor)) return;
                state.rgb = rgb; state.valid = valid;
                if (!valid && state.retries == 0) {
                    state.retries = 1;
                    QueueColorRefresh(owner, state);
                }
                Update(owner);
            });
        });
    }
    return FLChooseColor(config.followIconColor, state.valid, state.rgb, manual);
}
// Optional image hooks remain signature-gated; public layer fallback needs no private getter.
static void (*originalImageUpdate)(id, SEL, bool);
static void (*originalImageLoaded)(id, SEL, id);
static void RefreshImage(id imageView) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (stopped || !config.followIconColor) return;
        for (SBIconView *view in views.allObjects) {
            if ([view _iconImageView] != imageView) continue;
            FLIconColorState *state = objc_getAssociatedObject(view, &colorKey);
            if (state && FLRefreshIconSample(state.valid, state.localCapture)) QueueColorRefresh(view, state);
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
