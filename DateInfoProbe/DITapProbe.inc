// Main-thread only. UIKit target internals are private; all failures mean unknown.
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
static NSUInteger diCandidates, diMatched, diExceptions;
static NSUInteger diFired, diRegistrations, diRemovalAttempts, diRemovalSuccesses;
static NSUInteger diScanCalls, diViewsVisited, diScanTruncations, diCapacitySkips;
static NSUInteger diTargetsIvarMissing, diTargetsNotArray, diPairs, diTargetIvarMissing;
static NSUInteger diActionIvarMissing, diTargetNil, diClassMatches, diSelectorMatches;
static NSUInteger diClassImageMatches, diClassImageFailures, diMethodMissing;
static NSUInteger diImpImageMatches, diImpImageFailures, diSignatureMatches, diSignatureFailures;
static NSUInteger diClassAvailableScans, diClassMissingScans;
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
// Stage counts are observations across scans, not unique recognizers or targets.
// Never invoke the IMP: stripping its signature is only for dladdr inspection.
static BOOL diIsOriginalBinding(UIGestureRecognizer *g, NSMutableDictionary *metadata) {
    Ivar targetsIvar = diObjectIvar(object_getClass(g), "_targets");
    if (!targetsIvar) { diTargetsIvarMissing++; return NO; }
    id targets = object_getIvar(g, targetsIvar);
    if (![targets isKindOfClass:[NSArray class]]) { diTargetsNotArray++; return NO; }
    for (id pair in (NSArray *)targets) {
        diPairs++;
        Ivar targetIvar = diObjectIvar(object_getClass(pair), "_target");
        if (!targetIvar) { diTargetIvarMissing++; continue; }
        id target = object_getIvar(pair, targetIvar);
        if (!target) { diTargetNil++; continue; }
        Class cls = object_getClass(target);
        if (!cls || strcmp(class_getName(cls), "DIClockTapTarget") != 0) continue;
        diClassMatches++;
        Ivar actionIvar = class_getInstanceVariable(object_getClass(pair), "_action");
        const char *encoding = actionIvar ? ivar_getTypeEncoding(actionIvar) : NULL;
        if (!encoding || strcmp(encoding, ":") != 0) { diActionIvarMissing++; continue; }
        SEL action = NULL;
        memcpy(&action, (const char *)(__bridge const void *)pair + ivar_getOffset(actionIvar), sizeof(action));
        if (action != @selector(handleTap:)) continue;
        diSelectorMatches++;
        if (!diDateInfoImage(class_getImageName(cls))) { diClassImageFailures++; continue; }
        diClassImageMatches++;
        Method m = class_getInstanceMethod(cls, action);
        if (!m) { diMethodMissing++; continue; }
        Dl_info info = {0};
        void *imp = (void *)method_getImplementation(m);
#if __has_feature(ptrauth_calls)
        imp = ptrauth_strip(imp, ptrauth_key_function_pointer);
#endif
        if (!dladdr(imp, &info) || !diDateInfoImage(info.dli_fname)) { diImpImageFailures++; continue; }
        diImpImageMatches++;
        unsigned int n = method_getNumberOfArguments(m);
        char *ret = method_copyReturnType(m);
        char *arg = n > 2 ? method_copyArgumentType(m, 2) : NULL;
        BOOL valid = n == 3 && ret && strcmp(ret, "v") == 0 && arg && arg[0] == '@';
        free(ret); free(arg);
        if (!valid) { diSignatureFailures++; continue; }
        diSignatureMatches++;
        metadata[@"target_class"] = @"DIClockTapTarget";
        metadata[@"action"] = @"handleTap:";
        metadata[@"target_class_image_is_dateinfo"] = @YES;
        metadata[@"action_imp_image_is_dateinfo"] = @YES;
        metadata[@"signature_matches"] = @YES;
        return YES;
    }
    return NO;
}

static void DITapProbeBegin(void) {
    diCounter = [DITapCounter new];
    diBindings = [NSMapTable weakToStrongObjectsMapTable];
    diBindingRecords = [NSMutableArray array];
}
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
        @"matching_status": diMatched ? @"matched" : @"unknown",
        @"candidate_tap_recognizers_inspected": @(diCandidates),
        @"target_class_available_scans": @(diClassAvailableScans), @"target_class_missing_scans": @(diClassMissingScans),
        @"targets_ivar_missing_or_not_object": @(diTargetsIvarMissing), @"targets_not_array_or_nil": @(diTargetsNotArray),
        @"target_action_pairs_inspected": @(diPairs), @"pair_target_ivar_missing_or_not_object": @(diTargetIvarMissing),
        @"pair_target_nil": @(diTargetNil), @"target_class_matches": @(diClassMatches),
        @"class_matched_action_ivar_missing_or_wrong_type": @(diActionIvarMissing), @"selector_matches": @(diSelectorMatches),
        @"target_class_image_matches": @(diClassImageMatches), @"target_class_image_unknown_or_mismatch": @(diClassImageFailures),
        @"action_method_missing": @(diMethodMissing), @"action_imp_image_matches": @(diImpImageMatches),
        @"action_imp_image_unknown_or_mismatch": @(diImpImageFailures), @"signature_matches": @(diSignatureMatches),
        @"signature_unknown_or_mismatch": @(diSignatureFailures),
        @"matched_dateinfo_bindings": @(diMatched), @"probe_target_registrations": @(diRegistrations),
        @"remove_target_attempts": @(diRemovalAttempts), @"remove_target_successes": @(diRemovalSuccesses),
        @"scan_passes": @(diScanCalls), @"views_visited": @(diViewsVisited),
        @"scan_truncations": @(diScanTruncations), @"capacity_skips": @(diCapacitySkips),
        @"complete": @(diFinished), @"recognizer_callback_total": @(diFired), @"diagnostic_exceptions": @(diExceptions),
        @"bindings": diBindingRecords ?: @[], @"original_action_execution_count": @"not_observed",
        @"present_path_execution_count": @"not_observed",
        @"interpretation": @"Counts are scan observations and can repeat. Zero matches means unknown, not no tap or no matching gesture. A callback only shows recognizer action delivery, not original action execution or presentation. Extra target can alter timing or target iteration order."
    };
}
