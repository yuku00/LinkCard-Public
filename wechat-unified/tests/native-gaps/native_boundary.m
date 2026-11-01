#import "TestHost.h"
static IMP originalSlot,base,firstPrevious,secondPrevious,loaderVoid,loaderBool;
static unsigned hostCalls,ourCalls,loads,depth;
static BOOL nested,throwLoad,disableCompat,disableMaster,enableDisable;
static int mode;
@interface BoundaryTarget : NSObject - (int)value; @end
@implementation BoundaryTarget - (int)value { hostCalls++; return 1; } @end
static int Ours(id x,SEL s) {
    assert(++depth<8); int value=((int(*)(id,SEL))originalSlot)(x,s); depth--;
    if(testMaster) { ourCalls++; return value+100; } return value;
}
static int FirstPatch(id x,SEL s) { return 20+((int(*)(id,SEL))firstPrevious)(x,s); }
static int SecondPatch(id x,SEL s) { return 30+((int(*)(id,SEL))secondPrevious)(x,s); }
static int Foreign(id x,SEL s) { return 70; }
static int CachedOurs(id x,SEL s) { return 5+Ours(x,s); } // looks like host code but would cycle if rebased
@interface MicroMessengerAppDelegate : NSObject - (void)loadUpdateAndExcute; @end
@interface WCUpdateMgr : NSObject - (BOOL)loadMainUpdateBundle; @end
static void Load(void) {
    loads++; Method method=class_getInstanceMethod(BoundaryTarget.class,@selector(value));
    if(mode==1) { firstPrevious=method_getImplementation(method); method_setImplementation(method,(IMP)FirstPatch); }
    if(mode==2) { secondPrevious=method_getImplementation(method); method_setImplementation(method,(IMP)SecondPatch); }
    if(mode==3) method_setImplementation(method,(IMP)CachedOurs);
    if(mode==4) method_setImplementation(method,(IMP)Ours);
    if(disableCompat) { disableCompat=NO; assert(WUNativeSave(@"hotCompat",NO)); }
    if(disableMaster) { disableMaster=NO; testMaster=NO; [NSNotificationCenter.defaultCenter postNotificationName:WUChanged object:nil]; }
    if(enableDisable) { enableDisable=NO; assert(WUNativeSave(@"hotDisable",YES)); }
    if(nested) { nested=NO; mode=2; assert(![[WCUpdateMgr new] loadMainUpdateBundle]); }
    if(throwLoad) @throw [NSException exceptionWithName:@"loader" reason:nil userInfo:nil];
}
@implementation MicroMessengerAppDelegate - (void)loadUpdateAndExcute { Load(); } @end
@implementation WCUpdateMgr - (BOOL)loadMainUpdateBundle { Load(); return NO; } @end
BOOL WUNativeTestBoundary(id receiver,SEL selector,IMP loader) {
    return (object_getClass(receiver)==MicroMessengerAppDelegate.class && selector==@selector(loadUpdateAndExcute) && loader==loaderVoid) ||
           (object_getClass(receiver)==WCUpdateMgr.class && selector==@selector(loadMainUpdateBundle) && loader==loaderBool);
}
BOOL WUNativeTestHost(Class cls,SEL selector,IMP previous,IMP candidate) {
    if(cls!=BoundaryTarget.class || selector!=@selector(value)) return NO;
    BOOL oldKnown=previous==base || previous==(IMP)FirstPatch || previous==(IMP)SecondPatch;
    BOOL newKnown=candidate==base || candidate==(IMP)FirstPatch || candidate==(IMP)SecondPatch;
    return oldKnown && newKnown;
}
static void Reset(void) {
    testMaster=YES; TestConfig(@{@"hotCompat":@YES}); originalSlot=base;
    method_setImplementation(class_getInstanceMethod(BoundaryTarget.class,@selector(value)),(IMP)Ours);
    firstPrevious=NULL; secondPrevious=NULL; hostCalls=ourCalls=loads=depth=0;
    nested=throwLoad=disableCompat=disableMaster=enableDisable=NO; mode=1;
}
int main(void) { @autoreleasepool {
    TestInit(); UIApplication.sharedApplication.applicationState=UIApplicationStateInactive;
    loaderVoid=method_getImplementation(class_getInstanceMethod(MicroMessengerAppDelegate.class,@selector(loadUpdateAndExcute)));
    loaderBool=method_getImplementation(class_getInstanceMethod(WCUpdateMgr.class,@selector(loadMainUpdateBundle)));
    WUInstallNative(); assert(WUHook(@"BoundaryTarget",@"value",NO,"i",@[],(IMP)Ours,&originalSlot)); base=originalSlot;
    MicroMessengerAppDelegate *app=[MicroMessengerAppDelegate new]; BoundaryTarget *target=[BoundaryTarget new]; WCUpdateMgr *update=[WCUpdateMgr new];
    Reset(); [app loadUpdateAndExcute];
    assert(firstPrevious==base && originalSlot==(IMP)FirstPatch); assert([target value]==121 && hostCalls==1 && ourCalls==1);
    assert(method_getImplementation(class_getInstanceMethod(BoundaryTarget.class,@selector(value)))==(IMP)Ours);
    mode=2; assert(![update loadMainUpdateBundle]); assert(secondPrevious==(IMP)FirstPatch && originalSlot==(IMP)SecondPatch && [target value]==151);
    Reset(); nested=YES; [app loadUpdateAndExcute]; assert(loads==2 && firstPrevious==base && secondPrevious==(IMP)FirstPatch && [target value]==151);
    Reset(); throwLoad=YES; @try { [app loadUpdateAndExcute]; assert(0); } @catch(NSException *e) { assert([e.name isEqual:@"loader"]); }
    assert(originalSlot==(IMP)FirstPatch && [target value]==121); throwLoad=NO; mode=2; [app loadUpdateAndExcute]; assert([target value]==151);
    Reset(); disableCompat=YES; [app loadUpdateAndExcute]; assert(![testOptions[@"hotCompat"] boolValue] && originalSlot==(IMP)FirstPatch && [target value]==121);
    Reset(); disableMaster=YES; [app loadUpdateAndExcute]; assert(originalSlot==(IMP)FirstPatch && [target value]==21 && !ourCalls);
    Reset(); enableDisable=YES; nested=YES; [app loadUpdateAndExcute]; assert(loads==2 && [target value]==151); [app loadUpdateAndExcute]; assert(loads==2);
    // Third-party already owns method: neither suspend nor steal it after loading.
    Reset(); mode=0; method_setImplementation(class_getInstanceMethod(BoundaryTarget.class,@selector(value)),(IMP)Foreign);
    [app loadUpdateAndExcute]; assert([target value]==70 && originalSlot==base);
    Reset(); originalSlot=(IMP)CachedOurs; mode=0; // untrusted OLD chain must not be suspended
    [app loadUpdateAndExcute]; assert(originalSlot==(IMP)CachedOurs); // deliberately do not invoke the already-corrupt chain
    Reset(); mode=3; [app loadUpdateAndExcute]; assert(originalSlot==base && [target value]==106);
    // A pointer not equal to ours is insufficient: CachedOurs is same-image, same-ABI and still calls ours.
    assert(method_getImplementation(class_getInstanceMethod(BoundaryTarget.class,@selector(value)))==(IMP)CachedOurs);
    Reset(); mode=4; [app loadUpdateAndExcute]; assert(originalSlot==base && [target value]==101);
    Reset(); TestConfig(@{}); [app loadUpdateAndExcute]; assert(firstPrevious==(IMP)Ours && originalSlot==base && [target value]==121);
    Reset();
    // dispatch_sync(global) may execute inline on the caller's main thread.
    // Use a real asynchronously scheduled worker and assert the thread condition.
    dispatch_semaphore_t finished=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        assert(!NSThread.isMainThread);
        [app loadUpdateAndExcute];
        dispatch_semaphore_signal(finished);
    });
    assert(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,5ull*NSEC_PER_SEC))==0);
    assert(firstPrevious==(IMP)Ours && originalSlot==base && [target value]==121);
    Reset(); UIApplication.sharedApplication.applicationState=UIApplicationStateActive;
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil]; TestDrainAsync();
    [app loadUpdateAndExcute]; assert(firstPrevious==(IMP)Ours && originalSlot==base && [target value]==121);
    Reset(); UIApplication.sharedApplication.applicationState=UIApplicationStateInactive;
    [app loadUpdateAndExcute]; assert(firstPrevious==(IMP)Ours && originalSlot==base && [target value]==121); // Startup cannot reopen after activation.
    puts("PASS production suspend-before/load/rebase-before-resume: actual new patch calls old host, no recursion; nested/BOOL/throw/config/off/foreign/untrusted/startup-only cases");
} return 0; }
