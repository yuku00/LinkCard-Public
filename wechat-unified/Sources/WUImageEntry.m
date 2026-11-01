#import "WUImageEntry.h"
#import "WU.h"
#import "GroupLogic.h"
#import "EmoticonLogic.h"
#import <ImageIO/ImageIO.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdatomic.h>

static BOOL Has(id o, NSString *s, const char *r, NSArray *a) {
    return o && WUMatches(class_getInstanceMethod(object_getClass(o),NSSelectorFromString(s)),r,a);
}
static id Object(id o, NSString *s) {
    return Has(o,s,"@",@[])?((id(*)(id,SEL))objc_msgSend)(o,NSSelectorFromString(s)):nil;
}
static NSString *Text(id o, NSString *s) {
    id v=Object(o,s); return [v isKindOfClass:NSString.class]?[v copy]:nil;
}
static NSNumber *Number(id o, NSString *s) {
    SEL sel=NSSelectorFromString(s);
    if(Has(o,s,"I",@[])) return @(((unsigned int(*)(id,SEL))objc_msgSend)(o,sel));
    if(Has(o,s,"Q",@[])) return @(((unsigned long long(*)(id,SEL))objc_msgSend)(o,sel));
    if(Has(o,s,"i",@[])) { int n=((int(*)(id,SEL))objc_msgSend)(o,sel); return n<0?nil:@(n); }
    if(Has(o,s,"q",@[])) { long long n=((long long(*)(id,SEL))objc_msgSend)(o,sel); return n<0?nil:@(n); }
    return nil;
}
static NSDictionary *Identity(id wrap, NSString *account, NSString *session) {
    Class c=NSClassFromString(@"CMessageWrap");
    if(!c || ![wrap isKindOfClass:c]) return nil;
    NSNumber *type=Number(wrap,@"m_uiMessageType"), *mid=Number(wrap,@"m_n64MesSvrID"), *local=Number(wrap,@"m_uiMesLocalID"), *time=Number(wrap,@"m_uiCreateTime");
    NSString *from=Text(wrap,@"m_nsFromUsr"), *to=Text(wrap,@"m_nsToUsr");
    if(type.unsignedLongLongValue!=3 || !mid || !local || !time || !(mid.unsignedLongLongValue || local.unsignedLongLongValue) || !from.length || !to.length) return nil;
    BOOL belongs=[session hasSuffix:@"@chatroom"]?([from isEqual:session] || ([from isEqual:account] && [to isEqual:session])):(([from isEqual:account] && [to isEqual:session]) || ([from isEqual:session] && [to isEqual:account]));
    return belongs?@{@"from":from,@"to":to,@"real":Text(wrap,@"m_nsRealChatUsr")?:@"",@"type":type,@"id":mid,@"local":local,@"time":time}:nil;
}
static NSArray *Paths(id wrap) {
    NSMutableArray *out=[NSMutableArray array];
    // Evidence: WCRefine 0xfb0098. Only actual checked getters, never KVC or guessed paths.
    for(NSString *selector in @[@"m_nsImageHDPath",@"m_nsImagePath"]) {
        if(!Has(wrap,selector,"@",@[])) continue;
        id path=Object(wrap,selector);
        if(path && ![path isKindOfClass:NSString.class]) return nil;
        if([path length]) [out addObject:@{@"getter":selector,@"path":[path copy]}];
    }
    return [out copy];
}
static NSString *LocalPath(NSString *path) {
    if(path.length>=4096 || !path.isAbsolutePath || ![path isEqual:path.stringByStandardizingPath] || [path rangeOfString:[NSString stringWithFormat:@"%C",(unichar)0]].location!=NSNotFound) return nil;
    NSString *home=NSHomeDirectory().stringByStandardizingPath;
    NSString *root=[home.stringByResolvingSymlinksInPath stringByAppendingString:@"/"];
    NSString *prefix=[home stringByAppendingString:@"/"];
    // Normalize only the OS-provided sandbox root alias (e.g. /var -> /private/var).
    // Any symlink below that root, including a symlink to another cache file, is refused.
    if([path hasPrefix:prefix]) path=[root stringByAppendingString:[path substringFromIndex:prefix.length]];
    return [path hasPrefix:root] && [path isEqual:path.stringByResolvingSymlinksInPath]?path:nil;
}
static BOOL StaticImage(NSData *data) {
    NSString *type=WUEmoticonType(data);
    if(![type isEqual:@"public.png"] && ![type isEqual:@"public.jpeg"]) return NO;
    if([type isEqual:@"public.png"]) {
        // Reject APNG even on ImageIO versions exposing just its default image.
        const unsigned char *b=data.bytes; NSUInteger p=8, n=data.length;
        while(n-p>=12) {
            uint32_t size=((uint32_t)b[p]<<24)|((uint32_t)b[p+1]<<16)|((uint32_t)b[p+2]<<8)|b[p+3];
            if(size>n-p-12 || !memcmp(b+p+4,"acTL",4)) return NO;
            p+=12+size;
        }
    }
    CGImageSourceRef src=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
    BOOL ok=src && CGImageSourceGetCount(src)==1;
    if(src) CFRelease(src); return ok;
}
static void Notice(UIViewController *owner, NSString *text) {
    if(!owner.viewIfLoaded.window || owner.presentedViewController || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"图片转表情" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [owner presentViewController:a animated:YES completion:nil];
}
@interface WUImageEntry : NSObject { _Atomic(BOOL) _cancelled; }
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,weak) UINavigationController *nav;
@property(nonatomic,strong) id wrap;
@property(nonatomic,copy) NSString *account, *session;
@property(nonatomic,copy) NSDictionary *identity;
@property(nonatomic,copy) NSArray *paths;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,strong) UIImage *image;
@property(nonatomic,strong) UIViewController *editor;
@property(nonatomic,strong) UIAlertController *prompt;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) BOOL stopped, consumed, pushing;
- (BOOL)current;
- (void)stop;
- (void)fail:(NSString *)message;
- (void)prepare;
- (void)open;
@end
static NSMutableSet<WUImageEntry *> *entries;
@implementation WUImageEntry
- (instancetype)init { if((self=[super init])) atomic_init(&_cancelled,NO); return self; }
- (BOOL)current {
    @try {
        UIViewController *owner=self.owner; UINavigationController *nav=self.nav;
        if(self.stopped || !owner || !nav || owner.navigationController!=nav || ![nav.viewControllers containsObject:owner] || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || ![WUValue(@"enabled") boolValue] || ![self.account isEqual:WUCurrentAccount()] || self.generation!=WUContextGeneration() || ![self.session isEqual:WUChatSession(owner)] || ![WUToolbarActions(WUAccountOptions(self.account)[@"toolbar"]) containsObject:@"imageEmoji"]) return NO;
        if(self.editor) { if(!self.pushing && (![nav.viewControllers containsObject:self.editor] || [nav.viewControllers indexOfObjectIdenticalTo:owner]>=[nav.viewControllers indexOfObjectIdenticalTo:self.editor])) return NO; }
        else if(nav.topViewController!=owner || !owner.viewIfLoaded.window || (owner.presentedViewController && owner.presentedViewController!=self.prompt)) return NO;
        if(![self.identity isEqual:Identity(self.wrap,self.account,self.session)] || ![self.paths isEqual:Paths(self.wrap)]) return NO;
        // Once our editor was pushed, the host may legitimately clear multi-select.
        // Keep the already-confirmed image snapshot; still invalidate account/session,
        // generation, source identity, path changes and navigation ownership above.
        if(self.editor && !self.pushing) return YES;
        id selected=Object(owner,@"getSelectedMsgs");
        return [selected isKindOfClass:NSArray.class] && [selected count]==1 && [selected firstObject]==self.wrap;
    } @catch(__unused NSException *e) { return NO; }
}
- (void)stop {
    if(self.stopped) return; self.stopped=YES; atomic_store(&_cancelled,YES);
    [self.timer invalidate]; self.timer=nil;
    UIViewController *editor=self.editor; UINavigationController *nav=self.nav;
    BOOL ownsImage=self.pushing || (editor && [nav.viewControllers containsObject:editor]);
    @try {
        // Remove only the exact controller we created. Never popTo/pop/dismiss another page.
        if(editor && [nav.viewControllers containsObject:editor]) {
            NSMutableArray *stack=[nav.viewControllers mutableCopy]; [stack removeObjectIdenticalTo:editor];
            if(stack.count) [nav setViewControllers:stack animated:NO];
        }
    } @catch(__unused NSException *e) {}
    @try { if(ownsImage && Has(editor,@"setM_image:","v",@[@"@"])) ((void(*)(id,SEL,id))objc_msgSend)(editor,NSSelectorFromString(@"setM_image:"),nil); } @catch(__unused NSException *e) {}
    @try { if(self.prompt && self.owner.presentedViewController==self.prompt && !self.prompt.presentedViewController) [self.prompt dismissViewControllerAnimated:NO completion:nil]; } @catch(__unused NSException *e) {}
    self.pushing=NO; self.editor=nil; self.prompt=nil; self.image=nil; self.wrap=nil; self.identity=nil; self.paths=nil;
    self.account=nil; self.session=nil; self.owner=nil; self.nav=nil;
    [entries removeObject:self];
}
- (void)fail:(NSString *)message {
    UIViewController *owner=self.owner; BOOL current=[self current]; [self stop];
    if(current) Notice(owner,message);
}
- (void)prepare {
    NSArray *paths=self.paths; NSUInteger frozenGeneration=self.generation;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        BOOL (^cancelled)(void)=^BOOL { return atomic_load(&self->_cancelled) || frozenGeneration!=WUContextGenerationSnapshot(); };
        NSData *data=nil; NSString *error=nil;
        @try {
            for(NSDictionary *entry in paths) {
                if(cancelled()) { dispatch_async(dispatch_get_main_queue(),^{ [self stop]; }); return; }
                NSString *path=LocalPath(entry[@"path"]);
                if(!path) { error=@"所选消息的缓存路径不安全或不在宿主容器内，未读取。请先在微信加载该图片。"; break; }
                struct stat info;
                if(lstat(path.fileSystemRepresentation,&info)!=0 && errno==ENOENT) continue;
                data=WUEmoticonRead(path);
                if(!data) error=@"所选图片缓存存在但不可安全读取、为空或超过20MiB，未用其他图片替代。请先在微信重新加载。";
                break;
            }
            if(cancelled()) { dispatch_async(dispatch_get_main_queue(),^{ [self stop]; }); return; }
            if(!error && !data) error=@"没有可靠的已缓存图片。请先在微信打开并加载所选图片，再手动尝试；不会下载或猜测文件路径。";
            if(!error && !StaticImage(data)) error=@"仅支持完整静态 PNG/JPEG（不超过20MiB）。GIF、APNG、多帧、损坏或超限图片均拒绝，不会取首帧冒充表情动画。";
        } @catch(__unused NSException *e) { error=@"缓存图片读取或校验失败，未打开编辑器。"; }
        dispatch_async(dispatch_get_main_queue(),^{
            if(![self current]) { [self stop]; return; }
            if(error) { [self fail:error]; return; }
            @try {
                self.image=[UIImage imageWithData:data];
                if(!self.image || self.image.images.count) { [self fail:@"图片解码失败或包含动画，未打开编辑器。"]; return; }
                UIAlertController *prompt=[UIAlertController alertControllerWithTitle:@"用当前缓存图片编辑表情？" message:@"当前缓存图片、可能非原图。仅把所选静图交给微信原生编辑页面；请在该页面确认或取消。打开页面不代表已添加表情。" preferredStyle:UIAlertControllerStyleAlert];
                self.prompt=prompt; __weak WUImageEntry *weak=self;
                [prompt addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ [weak stop]; }]];
                [prompt addAction:[UIAlertAction actionWithTitle:@"打开微信编辑器" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
                    WUImageEntry *op=weak;
                    if(!op || op.consumed) return; op.consumed=YES;
                    if(![op current]) { [op stop]; return; }
                    // Dismiss only our prompt. UIKit may already have auto-dismissed it.
                    void (^next)(void)=^{ op.prompt=nil; [op open]; };
                    if(op.owner.presentedViewController==op.prompt) [op.prompt dismissViewControllerAnimated:YES completion:next];
                    else if(!op.owner.presentedViewController) next();
                    else [op stop];
                }]];
                [self.owner presentViewController:prompt animated:YES completion:nil];
            } @catch(__unused NSException *e) { [self fail:@"图片编辑准备失败，未自动重试。"]; }
        });
    });
}
- (void)open {
    if(![self current] || self.editor || !self.image) { [self stop]; return; }
    @try {
        // WCRefine 0xfc65e8: alloc/init -> setM_image: -> source navigation push.
        Class c=NSClassFromString(@"EmoticonPickViewController");
        if(!c || ![c isSubclassOfClass:UIViewController.class] || !WUMatches(class_getInstanceMethod(c,@selector(init)),"@",@[]) || !WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"setM_image:")),"v",@[@"@"])) {
            [self fail:@"此微信版本的表情编辑器类型或方法签名不匹配，未打开。"]; return;
        }
        id editor=[[c alloc] init];
        if(![editor isKindOfClass:c] || ![editor isKindOfClass:UIViewController.class] || !Has(editor,@"setM_image:","v",@[@"@"])) { [self fail:@"微信表情编辑器初始化失败，未打开。"]; return; }
        self.editor=editor; self.pushing=YES;
        ((void(*)(id,SEL,id))objc_msgSend)(editor,NSSelectorFromString(@"setM_image:"),self.image);
        if(![self current] || self.owner.presentedViewController || self.nav.topViewController!=self.owner) { [self stop]; return; }
        [self.nav pushViewController:editor animated:YES];
        self.pushing=NO;
        if(self.nav.topViewController!=editor || ![self current]) [self stop];
        // Native UI owns confirmation/cancellation. No delegate, backend or success claim.
    } @catch(__unused NSException *e) { [self fail:@"微信表情编辑器未能打开，未自动重试；请在微信核对页面。"]; }
}
@end
BOOL WUImageEntryOwnsNavigation(UIViewController *owner) {
    if(!NSThread.isMainThread) return NO;
    for(WUImageEntry *op in entries) if(!op.stopped && op.owner==owner && op.editor && (op.pushing || (op.nav.topViewController==op.editor && [op.nav.viewControllers containsObject:owner]))) return YES;
    return NO;
}
void WUCancelImageEntries(void) {
    if(!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{ WUCancelImageEntries(); }); return; }
    for(WUImageEntry *op in entries.allObjects) [op stop];
}
void WUOpenSelectedImageEditor(UIViewController *owner) {
    if(!NSThread.isMainThread) return;
    @try {
        if(!owner.viewIfLoaded.window || owner.presentedViewController || !owner.navigationController || owner.navigationController.topViewController!=owner || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || ![WUValue(@"enabled") boolValue]) return;
        for(WUImageEntry *op in entries) if(op.owner==owner) return;
        NSString *account=WUCurrentAccount(), *session=WUChatSession(owner);
        if(!account.length || !session.length || ![WUToolbarActions(WUAccountOptions(account)[@"toolbar"]) containsObject:@"imageEmoji"]) return;
        id selected=Object(owner,@"getSelectedMsgs");
        if(![selected isKindOfClass:NSArray.class] || [selected count]!=1) { Notice(owner,@"请先用微信多选仅选中一张聊天图片，再打开此工具。不会读取其他消息。"); return; }
        id wrap=[selected firstObject]; NSDictionary *identity=Identity(wrap,account,session); NSArray *paths=identity?Paths(wrap):nil;
        if(!identity) { Notice(owner,@"所选单张图片的消息身份或当前会话归属不可核验，未读取。"); return; }
        if(!paths.count) { Notice(owner,@"没有可核验的所选图片缓存路径。请先在微信加载图片；此版本若没有匹配的路径 getter，则不支持此入口。"); return; }
        static dispatch_once_t once; dispatch_once(&once,^{
            entries=[NSMutableSet set];
            for(NSString *name in @[UIApplicationWillResignActiveNotification,WUChanged]) [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ WUCancelImageEntries(); }];
        });
        WUImageEntry *op=[WUImageEntry new]; op.owner=owner; op.nav=owner.navigationController; op.account=account; op.session=session; op.generation=WUContextGeneration(); op.wrap=wrap; op.identity=identity; op.paths=paths;
        [entries addObject:op];
        __weak WUImageEntry *weak=op;
        op.timer=[NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer){ WUImageEntry *live=weak; if(![live current]) [live stop]; }];
        [NSRunLoop.mainRunLoop addTimer:op.timer forMode:NSRunLoopCommonModes];
        if([op current]) [op prepare]; else [op stop];
    } @catch(__unused NSException *e) { WUCancelImageEntries(); Notice(owner,@"所选图片上下文读取失败，未打开编辑器。"); }
}
