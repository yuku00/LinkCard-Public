#import "VoiceDisplay.h"
#import "VoiceLogic.h"
#import "VoicePath.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <sys/stat.h>
extern BOOL WUMatches(Method,const char *,NSArray *);
extern BOOL WUHook(NSString *,NSString *,BOOL,const char *,NSArray *,IMP,IMP *);
static IMP durationOriginal, textOriginal;
static Class modelClass, messageClass;
static char displayKey;
/* Only synchronous original cell layout can enter this main-thread scope. */
static WUVoiceDisplay *layoutOwner;
@interface WUVoiceDisplay ()
@property(nonatomic,weak) id model, message;
@property(nonatomic) double milliseconds;
@property(nonatomic) WUVoiceDisplayIdentity lease;
@property(nonatomic) BOOL layoutObserved, layoutConsumedDuration;
- (BOOL)valid;
@end
static unsigned Duration(id message, SEL cmd) {
    unsigned host=((unsigned(*)(id,SEL))durationOriginal)(message,cmd);
    if(!NSThread.isMainThread) return host;
    WUVoiceDisplay *d=layoutOwner;
    if(!d || message!=d.message || ![d valid]) return host;
    d.layoutConsumedDuration=YES;
    return WUVoiceDisplayProject(host,d.milliseconds,d.lease,d.identity(),YES,YES,YES,YES);
}
static id TimeText(id model, SEL cmd) {
    if(!NSThread.isMainThread) return ((id(*)(id,SEL))textOriginal)(model,cmd);
    WUVoiceDisplay *d=objc_getAssociatedObject(model,&displayKey);
    /* Label reads must not masquerade as bubble-layout consumption. */
    WUVoiceDisplay *saved=layoutOwner; layoutOwner=nil;
    @try {
        if([d valid]) return WUVoiceTime(d.milliseconds,d.carry ? d.carry() : YES);
        return ((id(*)(id,SEL))textOriginal)(model,cmd);
    } @finally { layoutOwner=saved; }
}
@implementation WUVoiceDisplay
- (BOOL)valid {
    if(!NSThread.isMainThread || !self.identity || !self.enabled ||
       object_getClass(self.model)!=modelClass || object_getClass(self.message)!=messageClass) return NO;
    @try {
        return self.enabled() && WUVoiceDisplaySame(self.lease,self.identity()) &&
            ((unsigned(*)(id,SEL))objc_msgSend)(self.message,NSSelectorFromString(@"m_uiMessageType"))==34 &&
            ((id(*)(id,SEL))objc_msgSend)(self.model,NSSelectorFromString(@"messageWrap"))==self.message;
    } @catch(NSException *e) { return NO; }
}
- (BOOL)applyModel:(id)model message:(id)message milliseconds:(double)ms {
    if(!NSThread.isMainThread) return NO;
    if(!durationOriginal || !textOriginal || !self.identity || !WUVoiceDisplayMS(ms) ||
       object_getClass(model)!=modelClass || object_getClass(message)!=messageClass) { [self clear]; return NO; }
    @try {
        if(((unsigned(*)(id,SEL))objc_msgSend)(message,NSSelectorFromString(@"m_uiMessageType"))!=34) { [self clear]; return NO; }
        WUVoiceDisplayIdentity lease=self.identity();
        if(self.model!=model || self.message!=message || !WUVoiceDisplaySame(self.lease,lease) || self.milliseconds!=ms) {
            [self clear]; self.model=model; self.message=message; self.lease=lease; self.milliseconds=ms;
        }
        if(![self valid]) { [self clear]; return NO; }
        objc_setAssociatedObject(model,&displayKey,self,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    } @catch(NSException *e) { [self clear]; return NO; }
}
- (void)clear {
    if(!NSThread.isMainThread) return;
    if(self.model && objc_getAssociatedObject(self.model,&displayKey)==self)
        objc_setAssociatedObject(self.model,&displayKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.model=nil; self.message=nil; self.lease=(WUVoiceDisplayIdentity){0};
    self.layoutObserved=NO; self.layoutConsumedDuration=NO;
}
- (void)layout:(void (^)(void))original { WUVoiceDisplayLayout(self,original); }
- (NSString *)originalText:(id)model {
    if(!NSThread.isMainThread || !textOriginal || object_getClass(model)!=modelClass) return nil;
    WUVoiceDisplay *saved=layoutOwner; layoutOwner=nil;
    @try {
        id text=((id(*)(id,SEL))textOriginal)(model,NSSelectorFromString(@"voiceTimeStirng"));
        return [text isKindOfClass:NSString.class]?text:nil;
    } @catch(NSException *e) { return nil; }
    @finally { layoutOwner=saved; }
}
@end
void WUVoiceDisplayLayout(WUVoiceDisplay *display, void (^original)(void)) {
    if(!NSThread.isMainThread) { original(); return; }
    WUVoiceDisplay *saved=layoutOwner; layoutOwner=[display valid]?display:nil;
    if(layoutOwner) { display.layoutObserved=YES; display.layoutConsumedDuration=NO; }
    @try { original(); }
    @catch(NSException *e) { [display clear]; @throw; }
    @finally { layoutOwner=saved; }
}
void WUInstallVoiceDisplay(void) {
    if(!NSThread.isMainThread || (durationOriginal && textOriginal)) return;
    modelClass=NSClassFromString(@"VoiceMessageViewModel"); messageClass=NSClassFromString(@"CMessageWrap");
    if(!WUMatches(class_getInstanceMethod(modelClass,NSSelectorFromString(@"voiceTimeStirng")),"@",@[]) ||
       !WUMatches(class_getInstanceMethod(modelClass,NSSelectorFromString(@"messageWrap")),"@",@[]) ||
       !WUMatches(class_getInstanceMethod(messageClass,NSSelectorFromString(@"m_uiVoiceTime")),"I",@[]) ||
       !WUMatches(class_getInstanceMethod(messageClass,NSSelectorFromString(@"m_uiMessageType")),"I",@[])) return;
    if(!durationOriginal) WUHook(@"CMessageWrap",@"m_uiVoiceTime",NO,"I",@[],(IMP)Duration,&durationOriginal);
    if(!textOriginal) WUHook(@"VoiceMessageViewModel",@"voiceTimeStirng",NO,"@",@[],(IMP)TimeText,&textOriginal);
}
NSString *WUVoiceDisplaySourceVersion(NSString *path) {
    path=WUVoiceCanonicalLocalPath(path); if(!path) return nil;
    struct stat st;
    if(lstat(path.fileSystemRepresentation,&st) || !S_ISREG(st.st_mode) || st.st_size<12 || st.st_size>8*1024*1024) return nil;
    return [NSString stringWithFormat:@"%llu:%llu:%lld:%lld:%ld:%lld:%ld",
        (unsigned long long)st.st_dev,(unsigned long long)st.st_ino,(long long)st.st_size,
        (long long)st.st_mtimespec.tv_sec,st.st_mtimespec.tv_nsec,
        (long long)st.st_ctimespec.tv_sec,st.st_ctimespec.tv_nsec];
}
