#import "RuntimePermissions.h"
#import <Security/Security.h>
#import <dlfcn.h>
#import <unistd.h>
#import <errno.h>

NSString *WCMRuntimeJSON(void) {
    // SecTask is not declared by all iOS public SDKs. Resolve the real C APIs,
    // with their actual CF ownership/signatures; never message a private class.
    typedef CFTypeRef (*CreateTask)(CFAllocatorRef);
    typedef CFTypeRef (*CopyEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *);
    void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY | RTLD_LOCAL);
    CreateTask create = security ? (CreateTask)dlsym(security, "SecTaskCreateFromSelf") : NULL;
    CopyEntitlement copy = security ? (CopyEntitlement)dlsym(security, "SecTaskCopyValueForEntitlement") : NULL;
    NSDictionary *expected = @{
        @"platform-application": @YES,
        @"application-identifier": @"org.example.WebClipManager",
        @"com.apple.private.security.container-required": @NO,
        @"com.apple.private.security.no-container": @YES,
        @"com.apple.security.app-sandbox": @NO,
        @"com.apple.private.security.no-sandbox": @YES,
        @"com.apple.private.security.storage.AppDataContainers": @YES,
        @"com.apple.private.security.storage.Notes": @YES,
        @"com.apple.private.security.storage.Safari": @YES
    };
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSMutableDictionary *matches = [NSMutableDictionary dictionary];
    CFTypeRef task = create && copy ? create(kCFAllocatorDefault) : NULL;
    for (NSString *key in expected) {
        CFErrorRef error = NULL;
        CFTypeRef value = task ? copy(task, (__bridge CFStringRef)key, &error) : NULL;
        NSString *label = @"unknown";
        NSString *match = @"unknown";
        if (value) {
            if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
                label = CFBooleanGetValue((CFBooleanRef)value) ? @"boolean:true" : @"boolean:false";
                if ([expected[key] isKindOfClass:[NSNumber class]]) match = [(__bridge id)value isEqual:expected[key]] ? @"match" : @"mismatch";
                else match = @"mismatch";
            } else if (CFGetTypeID(value) == CFStringGetTypeID()) {
                // Never expose an arbitrary signing identity or third-party string.
                BOOL own = CFEqual(value, CFSTR("org.example.WebClipManager"));
                label = own ? @"string:org.example.WebClipManager" : @"string:redacted";
                match = own && [expected[key] isKindOfClass:[NSString class]] ? @"match" : @"mismatch";
            } else { label = @"unexpected-type"; match = @"mismatch"; }
            CFRelease(value);
        } else if (task && !error) { label = @"absent"; match = @"mismatch"; }
        values[key] = label; matches[key] = match;
        if (error) CFRelease(error);
    }
    if (task) CFRelease(task);
    if (security) dlclose(security);

    typedef int (*SandboxCheck)(pid_t, const char *, int, ...);
    void *sandbox = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_LAZY | RTLD_LOCAL);
    SandboxCheck check = (SandboxCheck)dlsym(RTLD_DEFAULT, "sandbox_check");
    if (!check && sandbox) check = (SandboxCheck)dlsym(sandbox, "sandbox_check");
    NSMutableDictionary *checks = [NSMutableDictionary dictionary];
    // SANDBOX_FILTER_PATH=1, SANDBOX_CHECK_NO_REPORT=0x10000000.
    // Results are operation-specific, NOT a global "unsandboxed" verdict.
    for (NSString *path in @[@"/private/var", @"/private/var/mobile/Library/WebClips", @"/private/var/mobile/Containers/Shared/AppGroup"]) {
        for (NSString *operation in @[@"file-read-data", @"file-read-metadata"]) {
            NSString *key = [NSString stringWithFormat:@"%@ %@", operation, path];
            errno = 0;
            int result = check ? check(getpid(), operation.UTF8String, 1 | 0x10000000, path.UTF8String) : -1;
            checks[key] = @{@"result": @(result), @"errno": @(check ? errno : 0)};
        }
    }
    NSDictionary *report = @{@"entitlementAPI": task ? @"available" : @"unknown",
        @"entitlements": values, @"expectedComparison": matches,
        @"sandboxAPI": check ? @"available" : @"unknown", @"sandboxChecks": checks};
    if (sandbox) dlclose(sandbox);
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}
