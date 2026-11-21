// Main-thread only. UIKit target internals are private; all failures mean unknown.
//
// v0.4 changes:
//   1. The probe no longer infers the stored action from pointer equality alone.
//      It reports the stored selector's *name* (guard: sel_isMapped first, so an
//      unmapped value is never dereferenced) together with the raw / stripped /
//      authenticated comparisons and both pointer values. That answers "what did
//      the tweak actually register" on device instead of assuming that a
//      non-matching raw comparison means pointer authentication.
//   2. Binding no longer depends on the SEL comparison. The target class
//      (DIClockTapTarget) is defined by DateInfo.dylib, so a class match already
//      proves the recognizer belongs to the tweak; the SEL result only labels the
//      action. This is what makes one collection able to show whether taps are
//      delivered at all.
//   3. Each binding records hit-test evidence at the hot zone centre: what view
//      would receive the tap, and whether that view is inside the tweak's own
//      gesture host. A tap that never reaches the recognizer's view is a
//      different failure than a tap that reaches it and does nothing.
// Read-only: no hooks, no method replacement, no touch or event interception.
#import <objc/runtime.h>
#import <dlfcn.h>
#import <string.h>
#if __has_feature(ptrauth_calls) && __has_include(<ptrauth.h>)
#import <ptrauth.h>
#define DI_PTRAUTH_CALLS 1
#else
#define DI_PTRAUTH_CALLS 0
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
static NSUInteger diSelectorRawMatches, diSelectorStrippedMatches, diSelectorSignedMatches;
static NSUInteger diSelectorNameMatches;
static NSUInteger diClassOnlyBindings, diOtherTargetClasses;
static NSUInteger diClassImageMatches, diClassImageFailures, diMethodMissing;
static NSUInteger diImpImageMatches, diImpImageFailures, diSignatureMatches, diSignatureFailures;
static NSUInteger diClassAvailableScans, diClassMissingScans;
static NSUInteger diHitTestSamples, diHitTestInsideTweakView, diNoWindowSamples;
static BOOL diFinished;

@implementation DITapCounter
- (void)di_observedTap:(UIGestureRecognizer *)recognizer {
    @try {
        NSMutableDictionary *entry = [diBindings objectForKey:recognizer];
        if (!entry) return;
        diFired++;
        entry[@"recognizer_callback_count"] = @([entry[@"recognizer_callback_count"] unsignedIntegerValue] + 1);
        entry[@"last_callback_state"] = @(recognizer.state);
        entry[@"last_callback_utc"] = [NSDate date].description;
    } @catch (__unused NSException *e) { diExceptions++; }
}
@end

static NSString *diString(const char *c) { return c ? [NSString stringWithUTF8String:c] : @"unknown"; }
static NSString *diClassName(id object) {
    if (!object) return @"nil";
    Class c = object_getClass(object);
    const char *n = c ? class_getName(c) : NULL;
    return diString(n);
}
static NSDictionary *diRect(CGRect r) {
    return @{ @"x": @(r.origin.x), @"y": @(r.origin.y), @"w": @(r.size.width), @"h": @(r.size.height) };
}
static NSString *diPointer(void *value) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)(uintptr_t)value];
}
static BOOL diDateInfoImage(const char *path) {
    if (!path) return NO;
    const char *base = strrchr(path, '/');
    return strcmp(base ? base + 1 : path, "DateInfo.dylib") == 0;
}
static Ivar diObjectIvar(Class c, const char *name) {
    if (!c) return NULL;
    Ivar v = class_getInstanceVariable(c, name);
    const char *t = v ? ivar_getTypeEncoding(v) : NULL;
    return t && t[0] == '@' ? v : NULL;
}
static NSArray *diIvarInventory(Class c) {
    unsigned int count = 0;
    Ivar *list = c ? class_copyIvarList(c, &count) : NULL;
    NSMutableArray *out = [NSMutableArray array];
    for (unsigned int i = 0; list && i < count && i < 12; i++) {
        const char *n = ivar_getName(list[i]);
        const char *t = ivar_getTypeEncoding(list[i]);
        [out addObject:[NSString stringWithFormat:@"%s:%s", n ? n : "?", t ? t : "?"]];
    }
    if (list) free(list);
    return out;
}
static NSArray *diSuperviewChain(UIView *view, NSUInteger limit) {
    NSMutableArray *out = [NSMutableArray array];
    for (UIView *cur = view; cur && out.count < limit; cur = cur.superview) [out addObject:diClassName(cur)];
    return out;
}
static BOOL diViewIsInSubtree(UIView *candidate, UIView *root) {
    for (UIView *cur = candidate; cur; cur = cur.superview) if (cur == root) return YES;
    return NO;
}
static NSDictionary *diViewSummary(UIView *view) {
    return @{ @"class": diClassName(view),
              @"frame_in_window": diRect([view convertRect:view.bounds toView:nil]),
              @"user_interaction_enabled": @(view.userInteractionEnabled),
              @"alpha": @(view.alpha), @"hidden": @(view.hidden),
              @"gesture_recognizers": @(view.gestureRecognizers.count) };
}
static NSArray *diSubviewInventory(UIView *view, NSUInteger limit) {
    NSMutableArray *out = [NSMutableArray array];
    for (UIView *child in view.subviews) {
        if (out.count >= limit) break;
        [out addObject:diViewSummary(child)];
    }
    return out;
}
static NSArray *diWindowInventory(void) {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableOrderedSet *windows = [NSMutableOrderedSet orderedSet];
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) [windows addObject:w];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in app.windows) [windows addObject:w];
#pragma clang diagnostic pop
    for (UIWindow *w in windows) {
        if (out.count >= 16) break;
        [out addObject:@{ @"class": diClassName(w), @"level": @(w.windowLevel),
                          @"hidden": @(w.hidden), @"alpha": @(w.alpha),
                          @"frame": diRect(w.frame), @"is_key_window": @(w.isKeyWindow),
                          @"root_children": @(w.subviews.count),
                          @"root_children_classes": diSubviewInventory(w, 6) }];
    }
    return out;
}
// Sampling only: never sends events, never draws, never changes hit-testing.
static void diSampleHitTest(UIView *view, NSMutableDictionary *metadata) {
    UIWindow *window = view.window;
    if (!window) { diNoWindowSamples++; metadata[@"hit_test"] = @"no_window"; return; }
    CGRect inWindow = [view convertRect:view.bounds toView:nil];
    CGPoint centre = CGPointMake(CGRectGetMidX(inWindow), CGRectGetMidY(inWindow));
    metadata[@"window_level"] = @(window.windowLevel);
    metadata[@"window_class"] = diClassName(window);
    @try {
        UIView *hit = [window hitTest:centre withEvent:nil];
        diHitTestSamples++;
        metadata[@"hit_test_point_in_window"] = @{ @"x": @(centre.x), @"y": @(centre.y) };
        metadata[@"hit_test_view_class"] = diClassName(hit);
        metadata[@"hit_test_superview_chain"] = diSuperviewChain(hit, 6);
        metadata[@"hit_test_is_gesture_host_view"] = @(hit == view);
        metadata[@"hit_test_inside_gesture_host_subtree"] = @(diViewIsInSubtree(hit, view));
        if (diViewIsInSubtree(hit, view)) diHitTestInsideTweakView++;
    } @catch (__unused NSException *e) {
        diExceptions++;
        metadata[@"hit_test"] = @"exception";
    }
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
        if (!cls || strcmp(class_getName(cls), "DIClockTapTarget") != 0) { diOtherTargetClasses++; continue; }
        diClassMatches++;
        metadata[@"pair_class"] = diClassName(pair);
        metadata[@"pair_ivars"] = diIvarInventory(object_getClass(pair));
        metadata[@"target_class"] = @"DIClockTapTarget";
        Ivar actionIvar = class_getInstanceVariable(object_getClass(pair), "_action");
        const char *encoding = actionIvar ? ivar_getTypeEncoding(actionIvar) : NULL;
        metadata[@"action_ivar_encoding"] = diString(encoding);
        if (!actionIvar || !encoding || strcmp(encoding, ":") != 0) {
            diActionIvarMissing++;
            metadata[@"action_relation"] = @"ivar_missing_or_wrong_type";
            continue;
        }
        // The SEL slot address matters for the authenticated form: the expected
        // value depends on the address it is stored at, not on the value alone.
        const char *slot = (const char *)(__bridge const void *)pair + ivar_getOffset(actionIvar);
        SEL stored = NULL;
        memcpy(&stored, slot, sizeof(stored));
        SEL expected = @selector(handleTap:);
        metadata[@"expected_selector"] = @"handleTap:";
        metadata[@"stored_selector_hex"] = diPointer((void *)stored);
        metadata[@"expected_selector_hex"] = diPointer((void *)expected);
        BOOL rawMatch = stored == expected;
        BOOL strippedMatch = NO, signedMatch = NO;
        void *raw = (void *)stored;
        void *stripped = raw;
#if DI_PTRAUTH_CALLS
        stripped = ptrauth_strip(raw, ptrauth_key_asdb);
        strippedMatch = stripped == (void *)expected;
        void *authenticated = ptrauth_sign_unauthenticated((void *)expected, ptrauth_key_asdb,
                                                           ptrauth_blend_discriminator((void *)slot, 0x57C2));
        signedMatch = raw == authenticated;
        metadata[@"authenticated_expected_hex"] = diPointer(authenticated);
        metadata[@"stripped_selector_hex"] = diPointer(stripped);
#else
        strippedMatch = rawMatch;
#endif
        if (rawMatch) diSelectorRawMatches++;
        if (strippedMatch) diSelectorStrippedMatches++;
        if (signedMatch) diSelectorSignedMatches++;
        metadata[@"selector_match_raw"] = @(rawMatch);
        metadata[@"selector_match_stripped"] = @(strippedMatch);
        metadata[@"selector_match_authenticated"] = @(signedMatch);
        // Evidence instead of inference: name the stored selector, but only after
        // sel_isMapped confirms the value is a real registered selector, so an
        // unmapped or re-signed pointer is never dereferenced. The raw value is
        // tried first; the stripped form only when the raw value is not a mapped
        // selector, because stripping an already-plain pointer changes it.
        NSString *storedName = @"unmapped";
        SEL named = sel_isMapped((SEL)raw) ? (SEL)raw : (sel_isMapped((SEL)stripped) ? (SEL)stripped : NULL);
        if (named) storedName = diString(sel_getName(named));
        metadata[@"stored_selector_name"] = storedName;
        BOOL nameMatch = [storedName isEqualToString:@"handleTap:"];
        metadata[@"selector_name_matches"] = @(nameMatch);
        if (nameMatch) diSelectorNameMatches++;
        if (rawMatch || strippedMatch || signedMatch || nameMatch) {
            diSelectorMatches++;
            metadata[@"action_relation"] = rawMatch ? @"raw" : (strippedMatch ? @"stripped" : (signedMatch ? @"authenticated" : @"name"));
        } else {
            // The class still identifies the tweak's own target, so the rest of the
            // inspection continues and the binding is labelled class-only.
            metadata[@"action_relation"] = @"unknown";
        }
        metadata[@"action_name"] = storedName;
        const char *image = class_getImageName(cls);
        metadata[@"target_class_image"] = diString(image);
        BOOL classImageIsDateInfo = diDateInfoImage(image);
        metadata[@"target_class_image_is_dateinfo"] = @(classImageIsDateInfo);
        if (classImageIsDateInfo) diClassImageMatches++;
        else diClassImageFailures++;
        Method m = class_getInstanceMethod(cls, expected);
        if (!m) {
            diMethodMissing++;
            metadata[@"action_method"] = @"missing";
        } else {
            Dl_info info = {0};
            void *imp = (void *)method_getImplementation(m);
#if DI_PTRAUTH_CALLS
            imp = ptrauth_strip(imp, ptrauth_key_function_pointer);
#endif
            BOOL impInDateInfo = dladdr(imp, &info) && diDateInfoImage(info.dli_fname);
            metadata[@"action_method"] = @"handleTap:";
            metadata[@"action_imp_image_is_dateinfo"] = @(impInDateInfo);
            metadata[@"action_imp_hex"] = diPointer(imp);
            if (impInDateInfo) diImpImageMatches++;
            else diImpImageFailures++;
            unsigned int n = method_getNumberOfArguments(m);
            char *ret = method_copyReturnType(m);
            char *arg = n > 2 ? method_copyArgumentType(m, 2) : NULL;
            BOOL valid = n == 3 && ret && strcmp(ret, "v") == 0 && arg && arg[0] == '@';
            free(ret); free(arg);
            metadata[@"signature_matches"] = @(valid);
            if (valid) diSignatureMatches++;
            else diSignatureFailures++;
        }
        return YES;
    }
    return NO;
}
static void diFillRecognizerContext(UIGestureRecognizer *g, NSMutableDictionary *metadata) {
    metadata[@"recognizer_class"] = diClassName(g);
    metadata[@"recognizer_enabled"] = @(g.isEnabled);
    metadata[@"recognizer_state_at_bind"] = @(g.state);
    metadata[@"cancels_touches_in_view"] = @(g.cancelsTouchesInView);
    metadata[@"delays_touches_ended"] = @(g.delaysTouchesEnded);
    if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
        UITapGestureRecognizer *tap = (UITapGestureRecognizer *)g;
        metadata[@"number_of_taps_required"] = @(tap.numberOfTapsRequired);
        metadata[@"number_of_touches_required"] = @(tap.numberOfTouchesRequired);
    }
    UIView *host = g.view;
    if (!host) { metadata[@"gesture_host_view"] = @"nil"; return; }
    metadata[@"gesture_host_view"] = diClassName(host);
    metadata[@"gesture_host_frame_in_window"] = diRect([host convertRect:host.bounds toView:nil]);
    metadata[@"gesture_host_chain"] = diSuperviewChain(host, 6);
    metadata[@"gesture_host_user_interaction_enabled"] = @(host.userInteractionEnabled);
    metadata[@"gesture_host_alpha"] = @(host.alpha);
    metadata[@"gesture_host_hidden"] = @(host.hidden);
    diSampleHitTest(host, metadata);
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
            record[@"host_view_class"] = diClassName(view);
            if (!diIsOriginalBinding(g, record)) continue;
            diMatched++;
            diFillRecognizerContext(g, record);
            record[@"recognizer_callback_count"] = @0;
            BOOL classOnly = [record[@"action_relation"] isEqualToString:@"unknown"];
            if (classOnly) diClassOnlyBindings++;
            record[@"bound_by"] = classOnly ? @"target_class_only" : @"target_class_and_action";
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
        @"other_target_classes_seen": @(diOtherTargetClasses),
        @"class_matched_action_ivar_missing_or_wrong_type": @(diActionIvarMissing), @"selector_matches": @(diSelectorMatches),
        @"selector_match_raw": @(diSelectorRawMatches), @"selector_match_stripped": @(diSelectorStrippedMatches),
        @"selector_match_authenticated": @(diSelectorSignedMatches), @"selector_match_by_name": @(diSelectorNameMatches),
        @"bindings_by_target_class_only": @(diClassOnlyBindings),
        @"target_class_image_matches": @(diClassImageMatches), @"target_class_image_unknown_or_mismatch": @(diClassImageFailures),
        @"action_method_missing": @(diMethodMissing), @"action_imp_image_matches": @(diImpImageMatches),
        @"action_imp_image_unknown_or_mismatch": @(diImpImageFailures), @"signature_matches": @(diSignatureMatches),
        @"signature_unknown_or_mismatch": @(diSignatureFailures),
        @"hit_test_samples": @(diHitTestSamples), @"hit_test_landing_inside_gesture_host": @(diHitTestInsideTweakView),
        @"hit_test_samples_without_window": @(diNoWindowSamples),
        @"matched_dateinfo_bindings": @(diMatched), @"probe_target_registrations": @(diRegistrations),
        @"remove_target_attempts": @(diRemovalAttempts), @"remove_target_successes": @(diRemovalSuccesses),
        @"scan_passes": @(diScanCalls), @"views_visited": @(diViewsVisited),
        @"scan_truncations": @(diScanTruncations), @"capacity_skips": @(diCapacitySkips),
        @"complete": @(diFinished), @"recognizer_callback_total": @(diFired), @"diagnostic_exceptions": @(diExceptions),
        @"bindings": diBindingRecords ?: @[], @"original_action_execution_count": @"not_observed",
        @"present_path_execution_count": @"not_observed",
        @"interpretation": @"Counts are scan observations and can repeat. Zero matches means unknown, not no tap or no matching gesture. A callback only shows recognizer action delivery, not original action execution or presentation. Extra target can alter timing or target iteration order. Binding by target class alone is labelled; it identifies the tweak's own target, not the selector value. hit_test_landing_inside_gesture_host is sampled at the gesture host centre with no live touch."
    };
}
