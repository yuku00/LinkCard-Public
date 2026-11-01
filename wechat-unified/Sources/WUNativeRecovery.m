#import "WUNative.h"
#import "WUNativeBoot.h"
#include <unistd.h>
#include <stdatomic.h>
static int directory=-1;
static WUNativeBootState state;
static _Atomic(BOOL) started, allowed, durable, armed, resetPending, late;
static NSUInteger foregroundEpoch;
static UIViewController *Root(void) {
    for(UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if(s.activationState==UISceneActivationStateForegroundActive && [s isKindOfClass:UIWindowScene.class])
            for(UIWindow *w in ((UIWindowScene *)s).windows) if(w.isKeyWindow) return w.rootViewController;
    return nil;
}
static BOOL Recovery(void) {
    if(allowed || resetPending) return YES;
    UIViewController *v=Root();
    for(unsigned i=0;v.presentedViewController && i<32;i++) v=v.presentedViewController;
    if(!v.viewIfLoaded.window) return NO;
    if([v isKindOfClass:UIAlertController.class]) return YES;
    NSString *reason=late?@"启动守卫接线晚于Hook安装：拒绝抑制微信安全模式。已装Hook不能在当前进程安全卸载，请关闭整合并修正初始化顺序。":@"本插件连续两次未完成稳定启动，或守卫记录损坏/写入失败。本次不安装整合Hook，微信原安全模式保持生效。可独立复位并关闭整合；下次启动才重新评估。";
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"整合启动保护" message:reason preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert=a;
    [a addAction:[UIAlertAction actionWithTitle:@"继续使用微信" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"关闭整合并复位" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        if(!WUNativeResetGuard()) {
            UIAlertController *error=[UIAlertController alertControllerWithTitle:@"复位失败" message:@"配置或守卫文件未成功保存。保持恢复状态，不安装Hook。请检查本插件目录写入权限后再次尝试。" preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
            [weakAlert dismissViewControllerAnimated:NO completion:^{ [v presentViewController:error animated:YES completion:nil]; }];
        } else [weakAlert dismissViewControllerAnimated:NO completion:nil];
    }]];
    [v presentViewController:a animated:YES completion:nil];
    return YES;
}
static void TryRecovery(NSUInteger epoch, unsigned remaining) {
    if(epoch!=foregroundEpoch || allowed || resetPending || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
    if(Recovery() || !remaining) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ TryRecovery(epoch,remaining-1); });
}
void WUNativeGuardLifecycle(BOOL active) {
    NSUInteger epoch=++foregroundEpoch;
    if(!active || !started) return;
    if(!allowed) { TryRecovery(epoch,5); return; }
    if(!state.pending) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(epoch!=foregroundEpoch || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || !allowed) return;
        durable=WUNativeBootStableAt(directory,&state);
        // A failed stable commit immediately restores the host's safety decision.
        if(!durable) armed=NO;
    });
}
BOOL WUNativeStartGuard(int fd) {
    if(started) return allowed;
    started=YES; directory=dup(fd);
    late=WUNativeHasRegisteredHooks();
    allowed=WUNativeBootBeginAt(directory,&state) && !late; durable=allowed;
    id options=WUValue(@"native");
    // Saved during this process? It cannot suppress host recovery until NEXT guarded boot.
    armed=allowed && WUNativeValidOptions(options) && [options[@"safeMode"] boolValue] && WUEnabled(@"enabled");
    dispatch_async(dispatch_get_main_queue(),^{
        for(NSString *name in @[UIApplicationWillResignActiveNotification,UIApplicationDidBecomeActiveNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ WUNativeGuardLifecycle([n.name isEqual:UIApplicationDidBecomeActiveNotification]); }];
        WUNativeGuardLifecycle(UIApplication.sharedApplication.applicationState==UIApplicationStateActive);
    });
    return allowed;
}
BOOL WUNativeGuardAllowsHooks(void) { return !started || allowed; }
BOOL WUNativeGuardReady(void) { return started && allowed && durable && !resetPending; }
BOOL WUNativeSafeModeArmed(void) { return WUNativeGuardReady() && armed; }
NSString *WUNativeGuardStatus(void) {
    if(!started) return @"未接入启动前守卫：禁止安全模式不可启用。";
    if(resetPending) return @"已关闭整合并复位；本次仍不恢复Hook，下次启动重新评估。";
    if(late) return @"启动守卫晚于Hook安装，禁止安全模式未开放；须修正接线顺序。";
    if(!allowed) return @"启动保护已隔离整合Hook；微信原安全模式保留。";
    if(!durable) return @"守卫落盘失败，已停止抑制微信安全模式。";
    return armed?@"本次受独立启动守卫保护；稳定前台30秒后完成标记。":@"守卫已接入；首次开启禁止安全模式仅在下次启动生效。";
}
BOOL WUNativeResetGuard(void) {
    if(!NSThread.isMainThread || !started) return NO;
    // Preferences must be durably OFF before clearing the failure latch.
    if(!WUSave(@"enabled",@NO)) return NO;
    armed=NO;
    if(!WUNativeSave(@"safeMode",NO)) return NO;
    if(!WUNativeBootResetAt(directory,&state)) return NO;
    resetPending=YES; foregroundEpoch++; return YES;
}
