#import "TestHost.h"
#import "WUNativeBoot.h"
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
static NSUInteger safeCalls;
@interface MMSafeModeMgr : NSObject - (BOOL)shouldEnterSafeMode; @end
@implementation MMSafeModeMgr - (BOOL)shouldEnterSafeMode { safeCalls++; return YES; } @end
static uint32_t Pending(int fd) {
    int f=openat(fd,"native-startup.guard",O_RDONLY|O_NOFOLLOW); assert(f>=0); uint32_t pending=99;
    assert(pread(f,&pending,sizeof(pending),3*sizeof(uint32_t))==(ssize_t)sizeof(pending)); close(f); return pending;
}
int main(int argc,const char **argv) { @autoreleasepool {
    TestInit(); NSString *mode=argc>1?@(argv[1]):@"fresh";
    char path[]="/tmp/wu-guard-life.XXXXXX"; assert(mkdtemp(path)); int fd=open(path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); assert(fd>=0);
    TestScene *scene=[TestScene new]; MMSafeModeMgr *safe=[MMSafeModeMgr new];
    if([mode isEqual:@"late"]) {
        WUInstallNativeInteractions(); assert(WUNativeHasRegisteredHooks());
        TestConfig(@{@"safeMode":@YES,@"patConfirm":@YES}); assert(!WUNativeStartGuard(fd));
        WUInstallNative(); assert(!WUNativeAvailable(@"safeMode") && !WUNativeEnabled(@"patConfirm"));
        assert([safe shouldEnterSafeMode] && !WUNativeSafeModeArmed());
    } else if([mode isEqual:@"blocked"]) {
        WUNativeBootState s; assert(WUNativeBootBeginAt(fd,&s)); assert(WUNativeBootBeginAt(fd,&s));
        TestConfig(@{@"safeMode":@YES}); assert(!WUNativeStartGuard(fd));
        WUInstallNative(); WUInstallNativeInteractions(); WUInstallNativeGames();
        assert(!WUNativeAvailable(@"patConfirm") && !WUNativeGameAvailable() && !WUNativeAvailable(@"safeMode"));
        assert([safe shouldEnterSafeMode] && safeCalls==1); TestDrainAsync();
        UIAlertController *recovery=(id)scene.chat.presentedViewController; assert(recovery && recovery.actions.count==2);
        testWriteOK=NO; assert(!WUNativeResetGuard() && !WUNativeGuardAllowsHooks()); testWriteOK=YES;
        [recovery.actions[1] fire]; assert(!testMaster && ![testOptions[@"safeMode"] boolValue]);
        assert(!WUNativeGuardAllowsHooks() && !WUNativeSafeModeArmed() && Pending(fd)==0);
        WUNativeGuardLifecycle(YES); TestRunTimers(); assert(!WUNativeGuardAllowsHooks());
    } else {
        BOOL saved=[mode isEqual:@"saved"];
        TestConfig(@{@"safeMode":@(saved)}); assert(WUNativeStartGuard(fd));
        assert(Pending(fd)==1); WUInstallNative(); assert(WUNativeAvailable(@"safeMode"));
        assert([safe shouldEnterSafeMode]==!saved);
        assert(WUNativeSave(@"safeMode",YES)); assert([safe shouldEnterSafeMode]==!saved); // first enabling never arms this process
        TestDrainAsync(); WUNativeGuardLifecycle(NO); TestRunTimers(); assert(Pending(fd)==1);
        WUNativeGuardLifecycle(YES); TestRunTimers(); assert(Pending(fd)==0 && WUNativeGuardReady());
        assert(WUNativeSave(@"safeMode",NO) && [safe shouldEnterSafeMode]);
        assert(WUNativeResetGuard() && !testMaster && !WUNativeSafeModeArmed());
        WUNativeBootState next; assert(WUNativeBootBeginAt(fd,&next) && next.failures==0);
    }
    close(fd); NSString *dir=@(path); [NSFileManager.defaultManager removeItemAtPath:dir error:NULL];
    printf("PASS production guard/lifecycle/recovery settings path: %s (synthetic only)\n",mode.UTF8String);
} return 0; }
