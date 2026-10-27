#import <Foundation/Foundation.h>
#import "Shared/FLPreferences.h"
#include <pwd.h>
#include <grp.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

int main(void) {
    // Resolve the platform account; never clear root's preferences by accident.
    struct passwd *mobile = getpwnam("mobile");
    if (!mobile) { fputs("Firefly Lite: mobile account not found\n", stderr); return 1; }
    uid_t uid = mobile->pw_uid;
    gid_t gid = mobile->pw_gid;
    if (geteuid() == 0) {
        if (initgroups("mobile", gid) || setgid(gid) || setuid(uid)) {
            fputs("Firefly Lite: cannot switch to mobile\n", stderr); return 1;
        }
    }
    if (getuid() != uid || geteuid() != uid) {
        fputs("Firefly Lite: refusing to clear another user's domain\n", stderr); return 1;
    }
    setenv("HOME", mobile->pw_dir, 1);
    setenv("CFFIXED_USER_HOME", mobile->pw_dir, 1);
    @autoreleasepool {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            FL_STOP, NULL, NULL, true);
        // Best effort only: Darwin delivery is not an acknowledgement barrier.
        usleep(300000);
        if (!FLClearPreferences()) {
            fputs("Firefly Lite: CFPreferences clear failed\n", stderr); return 1;
        }
        CFArrayRef remaining = CFPreferencesCopyKeyList(FL_DOMAIN,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        BOOL empty = !remaining || CFArrayGetCount(remaining) == 0;
        if (remaining) CFRelease(remaining);
        if (!empty) fputs("Firefly Lite: preference keys remain\n", stderr);
        return empty ? 0 : 1;
    }
}
