#import "FLPreferences.h"
static id FLGet(CFStringRef key) {
    return CFBridgingRelease(CFPreferencesCopyValue(key, FL_DOMAIN,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
}
static double FLNumber(id value, double fallback) {
    return [value isKindOfClass:NSNumber.class] ? FLUnit([value doubleValue], fallback) : fallback;
}
FLConfig FLReadConfig(void) {
    CFPreferencesSynchronize(FL_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    id enabled = FLGet(CFSTR("Enabled"));
    id allApps = FLGet(CFSTR("AllApps"));
    // Default off until the user explicitly enables the unverified device build.
    FLConfig c = { [enabled isKindOfClass:NSNumber.class] && [enabled boolValue],
        [allApps isKindOfClass:NSNumber.class] && [allApps boolValue],
        FLNumber(FLGet(CFSTR("Red")), 0.30), FLNumber(FLGet(CFSTR("Green")), 0.72),
        FLNumber(FLGet(CFSTR("Blue")), 1.0), FLNumber(FLGet(CFSTR("Intensity")), 0.65) };
    return c;
}
BOOL FLWriteConfig(FLConfig c) {
    NSDictionary *values = @{ @"Enabled": @(!!c.enabled), @"AllApps": @(!!c.allApps), @"Red": @(FLUnit(c.red, 0.30)),
        @"Green": @(FLUnit(c.green, 0.72)), @"Blue": @(FLUnit(c.blue, 1)),
        @"Intensity": @(FLUnit(c.intensity, 0.65)) };
    CFPreferencesSetMultiple((__bridge CFDictionaryRef)values, NULL, FL_DOMAIN,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL ok = CFPreferencesSynchronize(FL_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (ok) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        FL_CHANGED, NULL, NULL, true);
    return ok;
}
BOOL FLClearPreferences(void) {
    CFPreferencesSynchronize(FL_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFArrayRef keys = CFPreferencesCopyKeyList(FL_DOMAIN,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys) {
        CFPreferencesSetMultiple(NULL, keys, FL_DOMAIN,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFRelease(keys);
    }
    return CFPreferencesSynchronize(FL_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
BOOL FLHasBadge(id badge) {
    if ([badge isKindOfClass:NSNumber.class]) {
        double n = [badge doubleValue];
        return isfinite(n) && n > 0;
    }
    if (![badge isKindOfClass:NSString.class]) return NO;
    NSString *s = [badge stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!s.length) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:s];
    double n;
    if ([scanner scanDouble:&n] && scanner.isAtEnd) return isfinite(n) && n > 0;
    return YES; // Non-numeric badges such as ! are visible badges too.
}
