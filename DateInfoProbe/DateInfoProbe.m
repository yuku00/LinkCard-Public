#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <syslog.h>

static NSMutableArray *samples;
static NSMutableDictionary *document;
static NSDictionary *tapReport;
static NSUInteger writeAttempts, writeSuccesses;
static BOOL canWrite = YES;
#include "DITapProbe.inc"
static NSString * const targetClass = @"_UIStatusBarForegroundView";
static NSDictionary *rect(CGRect r) {
    if (CGRectIsNull(r) || CGRectIsInfinite(r) || !isfinite(r.origin.x) || !isfinite(r.origin.y) || !isfinite(r.size.width) || !isfinite(r.size.height)) return @{};
    return @{ @"x":@(r.origin.x), @"y":@(r.origin.y), @"width":@(r.size.width), @"height":@(r.size.height) };
}
static NSDictionary *geometry(UIView *v, UIWindow *w) {
    return @{ @"bounds":rect(v.bounds), @"frame_in_parent":rect(v.frame), @"bounds_in_window":w ? rect([v convertRect:v.bounds toView:w]) : @{}, @"hidden":@(v.hidden), @"alpha":@(v.alpha), @"userInteractionEnabled":@(v.userInteractionEnabled) };
}
static NSDictionary *prefs(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.zhuifeng.dateinfo"));
    if (!value) return @{ @"is_default":@YES, @"value":@YES };
    id obj = CFBridgingRelease(value);
    if ([obj isKindOfClass:[NSNumber class]]) return @{ @"is_default":@NO, @"value":@([obj boolValue]) };
    return @{ @"is_default":@NO, @"value":@"non_numeric" };
}
static BOOL imageLoaded(void) {
    uint32_t n = _dyld_image_count();
    for (uint32_t i=0; i<n; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strcmp(strrchr(name, '/') ? strrchr(name, '/')+1 : name, "DateInfo.dylib") == 0) return YES;
    }
    return NO;
}
static void descendants(UIView *v, UIWindow *w, NSMutableArray *transparent, NSMutableArray *bindings, NSUInteger *tapCount, NSUInteger *budget) {
    if (*budget == 0) return;
    (*budget)--;
    for (UIView *child in v.subviews) {
        if (*budget == 0) break;
        NSUInteger taps=0;
        for (UIGestureRecognizer *g in child.gestureRecognizers) if ([g isKindOfClass:[UITapGestureRecognizer class]]) taps++;
        *tapCount += taps;
        if (taps) {
            NSMutableDictionary *binding=[geometry(child,w) mutableCopy];
            binding[@"tap_count_bound_to_this_view"]=@(taps);
            [bindings addObject:binding];
        }
        UIColor *c=child.backgroundColor;
        BOOL transparentColor = !c || CGColorGetAlpha(c.CGColor) < 0.01;
        if (transparentColor || child.alpha < 0.01) {
            NSMutableDictionary *entry=[geometry(child,w) mutableCopy];
            entry[@"tap_count_bound_to_this_view"]=@(taps);
            [transparent addObject:entry];
        }
        descendants(child,w,transparent,bindings,tapCount,budget);
    }
}
static void walk(UIView *v, UIWindow *w, Class cls, NSMutableArray *found, NSUInteger *budget, BOOL *truncated) {
    if (*budget == 0) { *truncated=YES; return; }
    (*budget)--;
    if (cls && [v isKindOfClass:cls]) {
        NSMutableDictionary *item=[geometry(v,w) mutableCopy];
        NSMutableArray *ancestors=[NSMutableArray array];
        UIView *p=v.superview; NSUInteger depth=0;
        while (p && depth++ < 32) { [ancestors addObject:geometry(p,w)]; p=p.superview; }
        item[@"anonymous_ancestors"]=ancestors;
        item[@"ancestors_truncated"]=@(p != nil);
        NSMutableArray *transparent=[NSMutableArray array], *bindings=[NSMutableArray array]; NSUInteger taps=0, childBudget=2000;
        for (UIGestureRecognizer *g in v.gestureRecognizers) if ([g isKindOfClass:[UITapGestureRecognizer class]]) taps++;
        item[@"tap_count_bound_to_foreground"]=@(taps);
        descendants(v,w,transparent,bindings,&taps,&childBudget);
        item[@"tap_bindings_descendants"]=bindings;
        item[@"tap_count_foreground_and_descendants"]=@(taps);
        item[@"transparent_descendants"]=transparent;
        item[@"transparent_descendant_count"]=@(transparent.count);
        item[@"descendants_truncated"]=@(childBudget == 0);
        [found addObject:item];
    }
    for (UIView *child in v.subviews) { if (*budget == 0) { *truncated=YES; break; } walk(child,w,cls,found,budget,truncated); }
}
static void flushDocument(void) {
    if (!canWrite) return;
    @try {
        writeAttempts++;
        document[@"schema"] = @1;
        document[@"mechanism"] = @"automatic main-thread SpringBoard window-tree snapshots at approximately 15 and 35 seconds after injection";
        document[@"samples"] = samples;
        if (tapReport) document[@"tap_probe_v0_2"] = tapReport;
        document[@"probe_io"] = @{ @"write_attempts_including_this": @(writeAttempts), @"successful_writes_before_this_flush": @(writeSuccesses) };
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingPrettyPrinted error:&error];
        if (data && [data writeToFile:@"/var/mobile/Library/Logs/DateInfoProbe.json" options:NSDataWritingAtomic error:&error]) writeSuccesses++;
        else syslog(LOG_ERR,"DateInfoProbe: JSON write failed: %s", error.localizedDescription.UTF8String ?: "unknown error");
    } @catch (__unused NSException *e) { syslog(LOG_ERR,"DateInfoProbe: flush exception (details omitted)"); }
}
static void sample(void) {
    @try {
        Class cls=NSClassFromString(targetClass);
        NSMutableArray *found=[NSMutableArray array];
        NSUInteger budget=30000; BOOL truncated=NO;
        NSMutableOrderedSet *windows=[NSMutableOrderedSet orderedSet];
        UIApplication *app=UIApplication.sharedApplication;
        for (UIScene *scene in app.connectedScenes) if ([scene isKindOfClass:[UIWindowScene class]]) for (UIWindow *w in ((UIWindowScene *)scene).windows) [windows addObject:w];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in app.windows) [windows addObject:w];
#pragma clang diagnostic pop
        for (UIWindow *w in windows) walk(w,w,cls,found,&budget,&truncated);
        NSDateFormatter *fmt=[NSDateFormatter new]; fmt.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]; fmt.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0]; fmt.dateFormat=@"yyyy-MM-dd'T'HH:mm:ss'Z'";
        NSDictionary *record=@{ @"timestamp_utc":[fmt stringFromDate:NSDate.date], @"bundle_id":NSBundle.mainBundle.bundleIdentifier ?: @"unknown", @"dateinfo_image_loaded":@(imageLoaded()), @"foreground_class_exists":@(cls != Nil), @"foreground_instance_count":@(found.count), @"foreground_instances":found, @"window_count":@(windows.count), @"tree_truncated":@(truncated), @"preferences":@{ @"Enabled":prefs(@"Enabled"), @"AvoidActivity":prefs(@"AvoidActivity") } };
        if (samples.count < 1000) [samples addObject:record];
        else document[@"sample_capacity_reached"] = @YES;
        flushDocument();
    } @catch (NSException *e) { syslog(LOG_ERR,"DateInfoProbe: diagnostic exception (details omitted)"); }
}
static void scanTree(UIView *view, Class cls, BOOL inside, NSUInteger *budget) {
    if (!*budget) { diScanTruncations++; return; }
    --*budget; diViewsVisited++;
    BOOL selected = inside || (cls && [view isKindOfClass:cls]);
    if (selected) DITapProbeScanView(view);
    for (UIView *child in view.subviews) {
        if (!*budget) { diScanTruncations++; break; }
        scanTree(child, cls, selected, budget);
    }
}
static void scanTapBindings(void) {
    @try {
        diScanCalls++;
        Class cls = NSClassFromString(targetClass);
        NSMutableOrderedSet *windows = [NSMutableOrderedSet orderedSet];
        UIApplication *app = UIApplication.sharedApplication;
        for (UIScene *scene in app.connectedScenes) if ([scene isKindOfClass:[UIWindowScene class]]) for (UIWindow *w in ((UIWindowScene *)scene).windows) [windows addObject:w];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in app.windows) [windows addObject:w];
#pragma clang diagnostic pop
        NSUInteger budget = 30000;
        for (UIWindow *w in windows) {
            if (!budget) { diScanTruncations++; break; }
            scanTree(w, cls, NO, &budget);
        }
    } @catch (__unused NSException *e) { diExceptions++; }
}
static void loadDocument(void) {
    NSString *path = @"/var/mobile/Library/Logs/DateInfoProbe.json";
    document = [NSMutableDictionary dictionary]; samples = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path]) return;
    NSError *err = nil;
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:&err];
    if (!attrs || [attrs fileSize] > 5 * 1024 * 1024 || ![attrs[NSFileType] isEqualToString:NSFileTypeRegular]) { canWrite = NO; return; }
    NSData *data = [NSData dataWithContentsOfFile:path];
    id old = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&err] : nil;
    if (![old isKindOfClass:[NSDictionary class]] || ![old[@"schema"] isEqual:@1] || ![old[@"samples"] isKindOfClass:[NSArray class]]) { canWrite = NO; return; }
    document = [old mutableCopy]; samples = [old[@"samples"] mutableCopy];
}
__attribute__((constructor)) static void start(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            @try { loadDocument(); DITapProbeBegin(); }
            @catch (__unused NSException *e) { canWrite = NO; return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{ sample(); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,35*NSEC_PER_SEC),dispatch_get_main_queue(),^{ sample(); });
            for (int seconds = 15; seconds <= 95; seconds += 5)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)seconds*NSEC_PER_SEC),dispatch_get_main_queue(),^{ scanTapBindings(); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,105*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                @try { DITapProbeEnd(); tapReport = DITapProbeReport(); flushDocument(); }
                @catch (__unused NSException *e) { syslog(LOG_ERR,"DateInfoProbe: finish exception (details omitted)"); }
            });
        });
    }
}
