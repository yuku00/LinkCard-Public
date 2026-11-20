// Included into DateInfoProbe.m. Main-thread use only; no method swizzling.
// UIGestureRecognizer has no public target enumeration API. This optional probe
// uses checked UIKit implementation details and fails closed when they differ.
#import <objc/runtime.h>
#import <dlfcn.h>
#import <string.h>
#if __has_include(<ptrauth.h>)
#import <ptrauth.h>
#endif

@interface DITapCounter : NSObject
- (void)di_observedTap:(UIGestureRecognizer *)recognizer;
@end

static DITapCounter *diCounter;
static NSMapTable<UIGestureRecognizer *, NSMutableDictionary *> *diBindings;
static NSMutableArray<NSMutableDictionary *> *diBindingRecords;
static NSUInteger diCandidates, diIntrospectionFailures, diMatched, diExceptions;
static NSUInteger diFired, diRegistrations, diRemovalAttempts, diRemovalSuccesses;
static NSUInteger diScanCalls, diViewsVisited, diScanTruncations, diCapacitySkips;
static BOOL diFinished;

@implementation DITapCounter
- (void)di_observedTap:(UIGestureRecognizer *)recognizer {
    @try {
        NSMutableDictionary *entry = [diBindings objectForKey:recognizer];
        if (!entry) return;
        diFired++;
        entry[@"recognizer_callback_count"] = @([entry[@"recognizer_callback_count"] unsignedIntegerValue] + 1);
    } @catch (__unused NSException *e) { diExceptions++; }
}
@end

static BOOL diDateInfoImage(const char *path) {
    if (!path) return NO;
    const char *base = strrchr(path, '/');
    return strcmp(base ? base + 1 : path, "DateInfo.dylib") == 0;
}
static Ivar diObjectIvar(Class c, const char *name) {
    Ivar v = class_getInstanceVariable(c, name);
    const char *t = v ? ivar_getTypeEncoding(v) : NULL;
    return t && t[0] == '@' ? v : NULL;
}
// Returns YES only when the existing recognizer contains the precise target and
// action, and both the target class and its implementation originate in DateInfo.
static BOOL diIsOriginalBinding(UIGestureRecognizer *g, NSMutableDictionary *metadata) {
    Ivar targetsIvar = diObjectIvar(object_getClass(g), "_targets");
    if (!targetsIvar) { diIntrospectionFailures++; return NO; }
    id targets = object_getIvar(g, targetsIvar);
    if (![targets isKindOfClass:[NSArray class]]) { diIntrospectionFailures++; return NO; }
    BOOL unknown = NO;
    for (id pair in (NSArray *)targets) {
        Ivar targetIvar = diObjectIvar(object_getClass(pair), "_target");
        Ivar actionIvar = class_getInstanceVariable(object_getClass(pair), "_action");
        const char *encoding = actionIvar ? ivar_getTypeEncoding(actionIvar) : NULL;
        if (!targetIvar || !encoding || strcmp(encoding, ":") != 0) { unknown = YES; continue; }
        id target = object_getIvar(pair, targetIvar);
        SEL action = NULL;
        memcpy(&action, (const char *)(__bridge const void *)pair + ivar_getOffset(actionIvar), sizeof(action));
        if (!target || action != @selector(handleTap:)) continue;
        Class cls = object_getClass(target);
        if (strcmp(class_getName(cls), "DIClockTapTarget") != 0 || !diDateInfoImage(class_getImageName(cls))) continue;
        Method m = class_getInstanceMethod(cls, action);
        if (!m) continue;
        Dl_info info = {0};
        void *imp = (void *)method_getImplementation(m);
#if __has_feature(ptrauth_calls)
        imp = ptrauth_strip(imp, ptrauth_key_function_pointer);
#endif
        if (!dladdr(imp, &info) || !diDateInfoImage(info.dli_fname)) continue;
        unsigned int n = method_getNumberOfArguments(m);
        char *ret = method_copyReturnType(m);
        char *arg = n > 2 ? method_copyArgumentType(m, 2) : NULL;
        metadata[@"target_class"] = @"DIClockTapTarget";
        metadata[@"action"] = @"handleTap:";
        metadata[@"action_method_exists"] = @YES;
        metadata[@"action_return_type"] = ret ? [NSString stringWithUTF8String:ret] : @"unknown";
        metadata[@"action_explicit_argument_count"] = @(n >= 2 ? n - 2 : 0);
        metadata[@"action_argument_0_type"] = arg ? [NSString stringWithUTF8String:arg] : @"absent";
        metadata[@"target_class_image_is_dateinfo"] = @YES;
        metadata[@"action_imp_image_is_dateinfo"] = @YES;
        free(ret); free(arg);
        if (unknown) diIntrospectionFailures++;
        return YES;
    }
    if (unknown) diIntrospectionFailures++;
    return NO;
}

static void DITapProbeBegin(void) {
    diCounter = [DITapCounter new];
    diBindings = [NSMapTable weakToStrongObjectsMapTable];
    diBindingRecords = [NSMutableArray array];
}
// Call once per view during the bounded foreground-tree traversal, on main.
static void DITapProbeScanView(UIView *view) {
    if (diFinished) return;
    @try {
        for (UIGestureRecognizer *g in view.gestureRecognizers) {
            if (![g isKindOfClass:[UITapGestureRecognizer class]] || [diBindings objectForKey:g]) continue;
            if (diCandidates >= 4096 || diRegistrations >= 128) { diCapacitySkips++; continue; }
            diCandidates++;
            NSMutableDictionary *record = [NSMutableDictionary dictionary];
            if (!diIsOriginalBinding(g, record)) continue;
            diMatched++;
            record[@"recognizer_callback_count"] = @0;
            [diBindings setObject:record forKey:g];
            [diBindingRecords addObject:record];
            @try { [g addTarget:diCounter action:@selector(di_observedTap:)]; }
            @catch (NSException *e) {
                @try { [g removeTarget:diCounter action:@selector(di_observedTap:)]; }
                @catch (__unused NSException *removeError) { diExceptions++; }
                [diBindings removeObjectForKey:g];
                [diBindingRecords removeLastObject];
                @throw e;
            }
            diRegistrations++;
        }
    } @catch (__unused NSException *e) { diExceptions++; }
}
// End before serializing the report, even if the window tree changed.
static void DITapProbeEnd(void) {
    diFinished = YES;
    for (UIGestureRecognizer *g in diBindings.keyEnumerator) {
        diRemovalAttempts++;
        @try { [g removeTarget:diCounter action:@selector(di_observedTap:)]; diRemovalSuccesses++; }
        @catch (__unused NSException *e) { diExceptions++; }
    }
}
static NSDictionary *DITapProbeReport(void) {
    return @{
        @"candidate_tap_recognizers_inspected": @(diCandidates),
        @"matching_status": diMatched ? @"matched" : ((diIntrospectionFailures || diExceptions || diScanTruncations || diCapacitySkips || !diCandidates) ? @"unknown" : @"no_match_observed"),
        @"private_target_layout_unreadable_count": @(diIntrospectionFailures),
        @"matched_dateinfo_bindings": @(diMatched),
        @"probe_target_registrations": @(diRegistrations),
        @"remove_target_attempts": @(diRemovalAttempts),
        @"remove_target_successes": @(diRemovalSuccesses),
        @"scan_passes": @(diScanCalls), @"views_visited": @(diViewsVisited),
        @"scan_truncations": @(diScanTruncations), @"capacity_skips": @(diCapacitySkips),
        @"complete": @(diFinished),
        @"unknown_layout_interpretation": @"Unreadable target layout means unknown, never a definite no-match; counts may include repeated scans.",
        @"recognizer_callback_total": @(diFired),
        @"diagnostic_exceptions": @(diExceptions),
        @"bindings": diBindingRecords ?: @[],
        @"original_action_execution_count": @"not_observed",
        @"present_path_execution_count": @"not_observed",
        @"method": @"existing UITapGestureRecognizer target/action inspected via private UIKit ivars; class and action implementation must both belong to DateInfo.dylib; added target only, no swizzle",
        @"limitation": @"A callback counts recognizer action delivery, not the original action or presentation. Private layout may be unavailable; absence of a match is not proof of absence. An extra target can affect timing or target-list iteration ordering."
    };
}
