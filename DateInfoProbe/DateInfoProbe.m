#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <syslog.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <time.h>
#import <errno.h>
#import <mach/mach_time.h>
#include "DITapProbe.inc"

// Private target inspection and all UIKit access run only on the main thread.
static const char *const triggerPath = "/var/mobile/Library/Logs/DateInfoProbe-v03.start";
static const char *const outputPath = "/var/mobile/Library/Logs/DateInfoProbe-v03.json";
static int outFD = -1;
static time_t injectionSecond;
static NSTimeInterval startedAt;
static BOOL running, scanning;
static NSMutableArray *records;
static NSString *runID, *injectionUTC, *triggerUTC, *startUTC;
static NSMutableArray *queue;
static NSUInteger queueIndex, foregroundCount, windowCount;
static BOOL truncated;
static NSDictionary *before;

static NSString *utc(void) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    return [f stringFromDate:NSDate.date];
}
static NSTimeInterval monotonic(void) { return NSProcessInfo.processInfo.systemUptime; }
static BOOL validTrigger(void) {
    int fd = open(triggerPath, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) return NO;
    struct stat st;
    BOOL ok = fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_size == 0 && st.st_uid == 501 && st.st_mtime > injectionSecond && st.st_mtime <= time(NULL);
    close(fd);
    return ok;
}
static void finish(void) {
    if (!running) return;
    running = NO;
    @try {
        DITapProbeEnd();
        NSDictionary *report = @{ @"schema": @3, @"run_id":runID, @"status":@"completed", @"injection_utc":injectionUTC, @"trigger_utc":triggerUTC, @"sampling_start_utc":startUTC, @"sampling_end_utc":utc(), @"trigger":@"mobile-owned empty file after injection; 20-second return-to-home delay", @"scan_interval_seconds":@5, @"duration_seconds":@(monotonic()-startedAt), @"incomplete_scan_at_end":@(scanning), @"scans":records, @"tap_probe":DITapProbeReport() };
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
        if (data) {
            const uint8_t *p = data.bytes; size_t left = data.length;
            while (left) { ssize_t n = write(outFD, p, left); if (n < 0 && errno == EINTR) continue; if (n <= 0) break; p += n; left -= (size_t)n; }
            if (left || fsync(outFD)) syslog(LOG_ERR, "DateInfoProbe v03: output write failed");
        } else syslog(LOG_ERR, "DateInfoProbe v03: JSON serialization failed");
    } @catch (__unused NSException *e) { syslog(LOG_ERR, "DateInfoProbe v03: finish exception"); }
    if (outFD >= 0) { close(outFD); outFD = -1; }
    queue = nil;
}
static NSDictionary *stageCounts(void) {
    return @{ @"candidates":@(diCandidates), @"pairs":@(diPairs), @"targets_ivar_missing":@(diTargetsIvarMissing), @"targets_not_array":@(diTargetsNotArray), @"target_ivar_missing":@(diTargetIvarMissing), @"target_nil":@(diTargetNil), @"class_matches":@(diClassMatches), @"action_ivar_missing":@(diActionIvarMissing), @"selector_matches":@(diSelectorMatches), @"class_image_mismatch":@(diClassImageFailures), @"method_missing":@(diMethodMissing), @"imp_image_mismatch":@(diImpImageFailures), @"signature_mismatch":@(diSignatureFailures), @"signature_matches":@(diSignatureMatches), @"capacity_skips":@(diCapacitySkips), @"exceptions":@(diExceptions) };
}
static void scanBatch(void);
static void beginScan(void) {
    if (!running || scanning || monotonic()-startedAt >= 90) return;
    scanning = YES; queueIndex = foregroundCount = 0; truncated = NO;
    queue = [NSMutableArray array]; before = stageCounts(); diScanCalls++;
    if (NSClassFromString(@"DIClockTapTarget")) diClassAvailableScans++; else diClassMissingScans++;
    NSMutableOrderedSet *windows = [NSMutableOrderedSet orderedSet];
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)scene).windows) [windows addObject:w];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in app.windows) [windows addObject:w];
#pragma clang diagnostic pop
    windowCount = windows.count;
    for (UIWindow *w in windows) { if (queue.count >= 10000) { truncated = YES; break; } [queue addObject:@[w, @NO]]; }
    scanBatch();
}
static void scanBatch(void) {
    if (!running || !scanning) return;
    if (monotonic()-startedAt >= 90) { finish(); return; }
    @try {
        Class cls = NSClassFromString(@"_UIStatusBarForegroundView");
        NSUInteger stop = MIN(queueIndex + 100, queue.count);
        while (queueIndex < stop) {
            NSArray *item = queue[queueIndex++]; UIView *v = item[0];
            BOOL isForeground = cls && [v isKindOfClass:cls];
            if (isForeground) foregroundCount++;
            BOOL inside = [item[1] boolValue] || isForeground;
            diViewsVisited++;
            if (inside) DITapProbeScanView(v);
            for (UIView *child in v.subviews) {
                if (queue.count >= 10000) { truncated = YES; break; }
                [queue addObject:@[child, @(inside)]];
            }
        }
        if (queueIndex < queue.count) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ scanBatch(); });
            return;
        }
        if (truncated) diScanTruncations++;
        NSDictionary *after = stageCounts(); NSMutableDictionary *delta = [NSMutableDictionary dictionary];
        for (NSString *key in after) delta[key] = @([after[key] unsignedIntegerValue] - [before[key] unsignedIntegerValue]);
        if (records.count < 20) [records addObject:@{ @"timestamp_utc":utc(), @"window_count":@(windowCount), @"foreground_class_exists":@(cls != Nil), @"foreground_instance_count":@(foregroundCount), @"target_class_available":@(NSClassFromString(@"DIClockTapTarget") != Nil), @"views_visited":@(queueIndex), @"truncated":@(truncated), @"stage_observations":delta }];
    } @catch (__unused NSException *e) { diExceptions++; }
    scanning = NO; queue = nil;
}
static void tick(void) {
    if (!running) return;
    if (monotonic()-startedAt >= 90) { finish(); return; }
    beginScan();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ tick(); });
}
static void beginSampling(void) {
    @try { DITapProbeBegin(); records = [NSMutableArray array]; startUTC = utc(); startedAt = monotonic(); running = YES; tick(); }
    @catch (__unused NSException *e) { if (outFD >= 0) close(outFD); outFD = -1; syslog(LOG_ERR, "DateInfoProbe v03: initialization failed"); }
}
static void pollTrigger(NSTimeInterval deadline) {
    if (monotonic() >= deadline) return;
    if (validTrigger()) {
        triggerUTC = utc();
        outFD = open(outputPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        if (outFD < 0) { syslog(LOG_ERR, "DateInfoProbe v03: output exists or cannot be created; aborting"); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ beginSampling(); });
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ pollTrigger(deadline); });
}
__attribute__((constructor)) static void start(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        injectionSecond = time(NULL); injectionUTC = utc(); runID = NSUUID.UUID.UUIDString;
        dispatch_async(dispatch_get_main_queue(), ^{ pollTrigger(monotonic()+600); });
    }
}
