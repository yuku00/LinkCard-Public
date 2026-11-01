#import "WU.h"
#import "WUDictation.h"
#import "WUNative.h"
#import "GroupLogic.h"
#import "PluginHubLogic.h"
#import "ThemeCatalog.h"
#import "RepeatOptions.h"
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
NSString *const WUChanged = @"org.wechatunified.changed";
static NSDictionary *snapshot;
static NSMutableDictionary<NSString *, NSString *> *hooks;
static int configDir = -1;
static NSDictionary *ReadConfig(NSString *name) {
    int fd = openat(configDir, name.UTF8String, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return nil;
    struct stat st; if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size > 65536) { close(fd); return nil; }
    NSMutableData *d = [NSMutableData dataWithLength:(NSUInteger)st.st_size];
    size_t n = 0; while (n < d.length) { ssize_t r = read(fd, (char *)d.mutableBytes+n, d.length-n); if (r <= 0) break; n += r; } close(fd);
    if (n != d.length) return nil;
    id x = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    if (![x isKindOfClass:NSDictionary.class] || ![x[@"schema"] isEqual:@1]) return nil;
    for (NSString *k in @[@"hideDictationIcon",@"dictationPreventMistouch",@"voiceProgress", @"voiceRealDuration", @"voiceCarry", @"voiceCountdown", @"voiceWaveform", @"voiceAlways", @"voicePulse", @"voiceSeek", @"enabled", @"ads", @"momentsAds", @"miniSplashAds", @"keywords", @"inputBorder", @"inputPulse", @"hideHomeSearch", @"fileSurface", @"emoticonSurface", @"noticeBorder", @"separators", @"convenientMoments", @"chatSearch", @"callbackConfirm", @"antiRevoke", @"multiRevoke", @"enhancedLinks", @"repeatEmoticon", @"mergeGroup", @"mergePrivate", @"mergeBottom", @"redReminder", @"themes", @"sunMoon", @"searchSurface", @"referSurface", @"plusSurface", @"toastSurface",@"timeSurface",@"swipeSurface"])
        if (x[k] && ![x[k] isKindOfClass:NSNumber.class]) return nil;
    if (x[@"words"] && (![x[@"words"] isKindOfClass:NSString.class] || [x[@"words"] length] > 2048)) return nil;
    for(NSString *k in @[@"themePack",@"bubblePack"]) if(x[k] && (![x[k] isKindOfClass:NSString.class] || ([x[k] length] && ![[NSUUID alloc] initWithUUIDString:x[k]]))) return nil;
    if(x[@"repeatOptions"] && !WUValidRepeatOptions(x[@"repeatOptions"])) return nil;
    if(x[@"accounts"] && !WUValidAccountOptions(x[@"accounts"])) return nil;
    if(x[@"native"] && !WUNativeValidOptions(x[@"native"])) return nil;
    if(x[@"pluginHub"] && !WUHubValidOptions(x[@"pluginHub"])) return nil;
    if(x[@"themeOptions"] && !WUValidThemeOptions(x[@"themeOptions"])) return nil;
    if(x[@"surfaceStyles"] && !WUValidSurfaceStyles(x[@"surfaceStyles"])) return nil;
    return x;
}
static BOOL WriteConfig(NSData *d, NSString *name) {
    NSString *tmp = [@"pending-" stringByAppendingString:NSUUID.UUID.UUIDString];
    int fd = openat(configDir, tmp.UTF8String, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600);
    if (fd < 0) return NO;
    size_t n=0; while(n<d.length) { ssize_t w=write(fd, (const char *)d.bytes+n, d.length-n); if(w<=0) break; n+=w; }
    BOOL ok = n==d.length && fsync(fd)==0; if(close(fd)!=0) ok=NO;
    if(ok) ok=renameat(configDir,tmp.UTF8String,configDir,name.UTF8String)==0;
    if(!ok) unlinkat(configDir,tmp.UTF8String,0);
    // The committed file is never overwritten non-atomically. Directory fsync is best effort on iOS.
    if(ok) fsync(configDir);
    return ok;
}
id WUValue(NSString *key) { @synchronized(NSProcessInfo.processInfo) { return snapshot[key]; } }
BOOL WUEnabled(NSString *key) { return [WUValue(@"enabled") boolValue] && [WUValue(key) boolValue]; }
BOOL WUSave(NSString *key, id value) {
    NSCAssert(NSThread.isMainThread, @"UI configuration is main-thread owned");
    if(![@[@"hideDictationIcon",@"dictationPreventMistouch",@"voiceProgress",@"voiceRealDuration",@"voiceCarry",@"voiceCountdown",@"voiceWaveform",@"voiceAlways",@"voicePulse",@"voiceSeek",@"enabled",@"ads",@"momentsAds",@"miniSplashAds",@"keywords",@"words",@"inputBorder",@"inputPulse",@"hideHomeSearch",@"fileSurface",@"emoticonSurface",@"noticeBorder",@"separators",@"convenientMoments",@"chatSearch",@"callbackConfirm",@"antiRevoke",@"multiRevoke",@"enhancedLinks", @"repeatEmoticon",@"mergeGroup",@"mergePrivate",@"mergeBottom",@"redReminder",@"themes",@"sunMoon",@"themePack",@"bubblePack",@"searchSurface",@"referSurface",@"plusSurface",@"toastSurface",@"timeSurface",@"swipeSurface",@"accounts",@"pluginHub",@"themeOptions",@"surfaceStyles",@"native",@"repeatOptions"] containsObject:key]) return NO;
    BOOL pack=[@[@"themePack",@"bubblePack"] containsObject:key];
    if(pack) { if(![value isKindOfClass:NSString.class] || ([value length] && ![[NSUUID alloc] initWithUUIDString:value])) return NO; }
    else if([key isEqual:@"repeatOptions"]) { if(!WUValidRepeatOptions(value)) return NO; }
    else if([key isEqual:@"accounts"]) { if(!WUValidAccountOptions(value)) return NO; }
    else if([key isEqual:@"native"]) { if(!WUNativeValidOptions(value)) return NO; }
    else if([key isEqual:@"pluginHub"]) { if(!WUHubValidOptions(value)) return NO; }
    else if([key isEqual:@"themeOptions"]) { if(!WUValidThemeOptions(value)) return NO; }
    else if([key isEqual:@"surfaceStyles"]) { if(!WUValidSurfaceStyles(value)) return NO; }
    else if([key isEqual:@"words"] ? (![value isKindOfClass:NSString.class] || [value length]>2048) : ![value isKindOfClass:NSNumber.class]) return NO;
    if(configDir<0) return NO;
    NSMutableDictionary *next=[snapshot mutableCopy]; next[key]=value;
    NSData *data=[NSJSONSerialization dataWithJSONObject:next options:0 error:NULL];
    NSData *old=[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];
    if(!data || data.length>65536 || !old || !WriteConfig(old,@"backup.json") || !WriteConfig(data,@"config.json")) return NO;
    @synchronized(NSProcessInfo.processInfo) { snapshot=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]; }
    [NSNotificationCenter.defaultCenter postNotificationName:WUChanged object:nil]; return YES;
}
static const char *Unqualified(const char *t) { while(*t && strchr("rnNoORV",*t)) t++; return t; }
BOOL WUMatches(Method m, const char *result, NSArray<NSString *> *args) {
    if(!m || method_getNumberOfArguments(m)!=args.count+2) return NO;
    char *r=method_copyReturnType(m); BOOL ok=strcmp(Unqualified(r),result)==0; free(r);
    for(unsigned i=0; ok && i<args.count; i++) { char *a=method_copyArgumentType(m,i+2); ok=strcmp(Unqualified(a),args[i].UTF8String)==0; free(a); }
    return ok;
}
BOOL WUHook(NSString *name, NSString *selector, BOOL meta, const char *ret, NSArray<NSString *> *args, IMP replacement, IMP *original) {
    if(!WUNativeGuardAllowsHooks()) return NO;
    NSString *key=[NSString stringWithFormat:@"%@%@ %@",meta?@"+":@"-",name,selector];
    if([hooks[key] isEqual:@"installed"]) return YES;
    Class c=NSClassFromString(name); if(meta && c) c=object_getClass(c);
    SEL s=NSSelectorFromString(selector); Method m=c?class_getInstanceMethod(c,s):NULL;
    if(!WUMatches(m,ret,args)) { hooks[key]=@"missing/signature mismatch"; return NO; }
    *original=method_getImplementation(m);
    // Add an owned override when inherited; never replace a superclass method by accident.
    if(!class_addMethod(c,s,replacement,method_getTypeEncoding(m))) method_setImplementation(class_getInstanceMethod(c,s),replacement);
    WUNativeRecordHook(c,s,replacement,original);
    hooks[key]=@"installed"; return YES;
}
NSArray *WUHookStatus(void) {
    NSMutableArray *out=[NSMutableArray array];
    for(NSString *k in [[hooks allKeys] sortedArrayUsingSelector:@selector(compare:)]) [out addObject:[NSString stringWithFormat:@"%@ — %@",k,hooks[k]]];
    return out;
}
static void Install(void) { if(!WUNativeGuardAllowsHooks()) return; WUInstallNative(); WUInstallNativeInteractions(); WUInstallNativeGames(); WUInstallDictation(); WUInstallVoice(); WUInstallAds(); WUInstallTimeline(); WUInstallMomentsCache(); WUInstallAppearance(); WUInstallSurfaces(); WUInstallThemes(); WUInstallMessages(); WUInstallGroups(); WUInstallHomeGroups(); WUInstallPluginHub(); WUInstallSettings(); }
__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.tencent.xin"]) return;
        hooks=[NSMutableDictionary dictionary];
        NSString *base=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;
        NSString *dir=[base stringByAppendingPathComponent:@"WeChatUnified"];
        [NSFileManager.defaultManager createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:NULL];
        mkdir(dir.fileSystemRepresentation,0700);
        configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
        snapshot=ReadConfig(@"config.json") ?: ReadConfig(@"backup.json") ?: @{@"schema":@1,@"enabled":@NO,@"words":@""};
        // Persist the startup guard before registering any host override. UI stays on main.
        if(WUNativeStartGuard(configDir)) WUInstallNative();
        dispatch_async(dispatch_get_main_queue(), ^{
            Install();
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ Install(); }];
        });
    }
}
