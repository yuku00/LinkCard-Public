#import "WUImageEntry.h"
#import "WU.h"
#import "GroupLogic.h"
#import "EmoticonLogic.h"
#import <ImageIO/ImageIO.h>
#import <Photos/Photos.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdatomic.h>
#include <math.h>

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
    // Only actual checked getters, never KVC or guessed paths.
    for(NSString *selector in @[@"m_nsImageHDPath",@"m_nsImagePath"]) {
        if(!Has(wrap,selector,"@",@[])) continue;
        id path=Object(wrap,selector);
        if(path && ![path isKindOfClass:NSString.class]) return nil;
        if([path length]) [out addObject:@{@"getter":selector,@"path":[path copy]}];
    }
    // Checked class API fallback.
    // It supplies a cache path, NOT a guarantee of original/HD bytes.
    if(!out.count && !Has(wrap,@"m_nsImageHDPath","@",@[]) && !Has(wrap,@"m_nsImagePath","@",@[])) {
        Class c=NSClassFromString(@"CMessageWrap");
        if(c && [wrap isKindOfClass:c] && Has(c,@"getPathOfMsgImg:","@",@[@"@"])) {
            id path=((id(*)(id,SEL,id))objc_msgSend)(c,NSSelectorFromString(@"getPathOfMsgImg:"),wrap);
            if(path && ![path isKindOfClass:NSString.class]) return nil;
            if([path length]) [out addObject:@{@"getter":@"+getPathOfMsgImg:",@"path":[path copy]}];
        }
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
BOOL WUImageEntryValidateData(NSData *data) { @try { return StaticImage(data); } @catch(__unused NSException *e) { return NO; } }
static void NoticeWithTitle(UIViewController *owner, NSString *title, NSString *text) {
    if(!owner.viewIfLoaded.window || owner.presentedViewController || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [owner presentViewController:a animated:YES completion:nil];
}
static void Notice(UIViewController *owner, NSString *text) { NoticeWithTitle(owner,@"图片转表情",text); }
static void ExportNotice(UIViewController *owner, NSString *text) { NoticeWithTitle(owner,@"保存原表情",text); }
@interface WUEmoticonExport : NSObject <UIDocumentPickerDelegate>
@property(nonatomic,strong) NSURL *directory;
@end
@implementation WUEmoticonExport
- (void)clean { if(self.directory) { [NSFileManager.defaultManager removeItemAtURL:self.directory error:NULL]; self.directory=nil; } }
- (void)dealloc { [self clean]; }
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker { [self clean]; }
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls { [self clean]; }
@end
static char WUEmoticonExportKey;
static NSData *WUSelectedEmoticonData(id wrap, NSString **kind) {
    NSString *md5=Text(wrap,@"m_nsEmoticonMD5");
    if(!md5.length) md5=Text(Object(wrap,@"m_extendInfoWithMsgType"),@"m_nsEmoticonMD5");
    if(!WUValidMD5(md5)) return nil;
    Class util=NSClassFromString(@"EmoticonUtil");
    NSString *dataSelector=@"dataOfEmoticonForMd5:needUpdateTime:ignoreWxAM:";
    NSString *pathSelector=@"pathOfEmoticonForMd5:needUpdateTime:ignoreWxAM:";
    id path=Has(util,pathSelector,"@",@[@"@",@"B",@"B"])?((id(*)(id,SEL,id,BOOL,BOOL))objc_msgSend)(util,NSSelectorFromString(pathSelector),md5,NO,NO):nil;
    id data=WUEmoticonRead(path);
    if(!data && Has(util,dataSelector,"@",@[@"@",@"B",@"B"]))
        data=((id(*)(id,SEL,id,BOOL,BOOL))objc_msgSend)(util,NSSelectorFromString(dataSelector),md5,NO,NO);
    if(![data isKindOfClass:NSData.class] || ![data length] || [data length]>20*1024*1024) return nil;
    NSString *type=WUEmoticonType(data);
    if(!type && Has(util,@"isWxAMData:","B",@[@"@"]) && ((BOOL(*)(id,SEL,id))objc_msgSend)(util,NSSelectorFromString(@"isWxAMData:"),data)) type=@"wxam";
    if(!type) return nil;
    if(kind) *kind=type;
    return [data copy];
}
static NSData *WUWxAMPhotoGIF(NSData *data) {
    Class util=NSClassFromString(@"EmoticonUtil"), decoder=NSClassFromString(@"WxAMAnimatedImageDecoder"), animated=NSClassFromString(@"MMAnimatedImageDecoder");
    NSString *convert=@"createGifFromWxAMData:", *frames=@"frameCountForImageData:", *decode=@"framesOfData:";
    if(!Has(util,convert,"@",@[@"@"]) || !Has(decoder,frames,"i",@[@"@"]) || !Has(animated,decode,"@",@[@"@"])) return nil;
    int count=((int(*)(id,SEL,id))objc_msgSend)(decoder,NSSelectorFromString(frames),data);
    if(count<1 || count>500) return nil;
    id gif=((id(*)(id,SEL,id))objc_msgSend)(util,NSSelectorFromString(convert),data);
    if(![WUEmoticonType(gif) isEqual:@"com.compuserve.gif"]) return nil;
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)gif,NULL);
    BOOL valid=source && CGImageSourceGetCount(source)==(size_t)count;
    id decoded=valid?((id(*)(id,SEL,id))objc_msgSend)(animated,NSSelectorFromString(decode),data):nil;
    if(![decoded isKindOfClass:NSArray.class] || [decoded count]!=(NSUInteger)count) valid=NO;
    for(int i=0;valid && i<count;i++) {
        id frame=decoded[i];
        if(!Has(frame,@"duration","d",@[])) { valid=NO; break; }
        double duration=((double(*)(id,SEL))objc_msgSend)(frame,NSSelectorFromString(@"duration"));
        NSDictionary *props=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,(size_t)i,NULL));
        NSDictionary *gifProps=props[(id)kCGImagePropertyGIFDictionary];
        NSNumber *delay=gifProps[(id)kCGImagePropertyGIFUnclampedDelayTime] ?: gifProps[(id)kCGImagePropertyGIFDelayTime];
        // GIF stores delays in centiseconds; never silently alter the animation timing.
        if(![delay isKindOfClass:NSNumber.class] || !isfinite(duration) || duration<=0 || fabs(delay.doubleValue-duration)>0.011) valid=NO;
    }
    if(source) CFRelease(source);
    return valid?gif:nil;
}
static NSData *WUWxAMPhotoPNG(NSData *data) {
    Class converter=NSClassFromString(@"WxamImageConvert");
    NSString *selector=@"decodeWxamToUIImage:scene:";
    if(!Has(converter,selector,"@",@[@"@",@"Q"])) return nil;
    id image=((id(*)(id,SEL,id,unsigned long long))objc_msgSend)(converter,NSSelectorFromString(selector),data,0ULL);
    if(![image isKindOfClass:UIImage.class]) return nil;
    NSData *png=UIImagePNGRepresentation(image);
    return StaticImage(png)?png:nil;
}
void WUSaveSelectedEmoticonToPhotos(UIViewController *owner, id wrap, BOOL (^current)(void)) {
    if(!NSThread.isMainThread || !owner || !wrap || !current || !current() || owner.presentedViewController) return;
    @try {
        id addUsage=[NSBundle.mainBundle objectForInfoDictionaryKey:@"NSPhotoLibraryAddUsageDescription"];
        id readUsage=[NSBundle.mainBundle objectForInfoDictionaryKey:@"NSPhotoLibraryUsageDescription"];
        BOOL hasAdd=[addUsage isKindOfClass:NSString.class] && [addUsage length];
        BOOL hasRead=[readUsage isKindOfClass:NSString.class] && [readUsage length];
        if(!hasAdd && !hasRead) { ExportNotice(owner,@"宿主缺少照片权限声明，未保存。"); return; }
        PHAccessLevel level=hasAdd?PHAccessLevelAddOnly:PHAccessLevelReadWrite;
        PHAuthorizationStatus status=[PHPhotoLibrary authorizationStatusForAccessLevel:level];
        if(status==PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:level handler:^(PHAuthorizationStatus result) {
                dispatch_async(dispatch_get_main_queue(),^{ if(current()) ExportNotice(owner,@"权限请求已结束，请再次选择保存到图库。"); });
            }];
            return;
        }
        if(status!=PHAuthorizationStatusAuthorized && status!=PHAuthorizationStatusLimited) { ExportNotice(owner,@"没有添加照片权限，未保存。"); return; }
        NSString *kind=nil; NSData *raw=WUSelectedEmoticonData(wrap,&kind);
        NSData *photo=[kind isEqual:@"wxam"]?WUWxAMPhotoGIF(raw):raw;
        BOOL staticFallback=[kind isEqual:@"wxam"] && !photo;
        if(staticFallback) photo=WUWxAMPhotoPNG(raw);
        NSString *uti=WUEmoticonType(photo);
        if(!uti || !current()) { if(current()) ExportNotice(owner,@"无法读取表情或转换为可保存图片，未保存；可尝试另存原文件。"); return; }
        if([uti isEqual:@"public.png"] && !StaticImage(photo)) { ExportNotice(owner,@"图库保存暂不支持动态 PNG；可保存原文件，不会用静图替代。"); return; }
        __weak UIViewController *weak=owner;
        __block BOOL added=NO;
        [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
            __block BOOL valid=NO;
            if(NSThread.isMainThread) valid=current(); else dispatch_sync(dispatch_get_main_queue(),^{ valid=current(); });
            if(!valid) return;
            PHAssetResourceCreationOptions *options=[PHAssetResourceCreationOptions new]; options.uniformTypeIdentifier=uti;
            options.originalFilename=[@"Emoticon." stringByAppendingString:[uti isEqual:@"com.compuserve.gif"]?@"gif":([uti isEqual:@"public.png"]?@"png":@"jpg")];
            PHAssetCreationRequest *request=[PHAssetCreationRequest creationRequestForAsset];
            if(request) { [request addResourceWithType:PHAssetResourceTypePhoto data:photo options:options]; added=YES; }
        } completionHandler:^(BOOL success,NSError *error){ dispatch_async(dispatch_get_main_queue(),^{
            if(current()) ExportNotice(weak,added && success && !error?(staticFallback?@"Photos 已确认保存静态 PNG，不含动画；原 WxAM 文件可另存到文件。":([kind isEqual:@"wxam"]?@"Photos 已确认保存微信转换的 GIF；原 WxAM 文件可另存到文件。":@"Photos 已确认保存原表情。")): @"Photos 未确认保存成功，请检查图库。");
        }); }];
    } @catch(__unused NSException *e) { ExportNotice(owner,@"准备表情失败，未保存。"); }
}
static void WUExportEmoticon(UIViewController *owner, id wrap, BOOL (^current)(void), BOOL original) {
    if(!NSThread.isMainThread || !owner || !wrap || !current || !current() || owner.presentedViewController) return;
    WUEmoticonExport *lease=nil;
    @try {
        NSString *type=nil; NSData *data=WUSelectedEmoticonData(wrap,&type);
        if(!data || !current()) { if(current()) ExportNotice(owner,@"无法读取微信已缓存的完整表情，未导出缩略图。"); return; }
        BOOL staticFallback=NO;
        if([type isEqual:@"wxam"] && !original) {
            NSData *raw=data;
            data=WUWxAMPhotoGIF(raw);
            if(data) type=@"com.compuserve.gif";
            else {
                data=WUWxAMPhotoPNG(raw);
                if(!data) { ExportNotice(owner,@"无法转换为可验证的 GIF 或静态 PNG，未保存；可尝试保存 WxAM 原文件。"); return; }
                type=@"public.png"; staticFallback=YES;
            }
        }
        NSString *ext=[type isEqual:@"wxam"]?@"wxam":([type isEqual:@"com.compuserve.gif"]?@"gif":([type isEqual:@"public.png"]?@"png":@"jpg"));
        if(!current()) return;
        NSURL *dir=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        NSError *error=nil;
        if(![NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:@{NSFileProtectionKey:NSFileProtectionComplete} error:&error]) { ExportNotice(owner,@"无法创建临时导出目录，未保存。"); return; }
        lease=[WUEmoticonExport new]; lease.directory=dir;
        NSURL *file=[dir URLByAppendingPathComponent:[(staticFallback?@"emoticon-static":@"emoticon") stringByAppendingPathExtension:ext]];
        if(![data writeToURL:file options:NSDataWritingWithoutOverwriting error:&error]) { [lease clean]; if(current()) ExportNotice(owner,@"无法写入临时导出文件，未保存。"); return; }
        if(!current()) { [lease clean]; return; }
        UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[file] asCopy:YES];
        if(!picker || !owner.viewIfLoaded.window || owner.presentedViewController) { [lease clean]; if(current()) ExportNotice(owner,@"无法打开文件选择器，未保存。"); return; }
        picker.delegate=lease; objc_setAssociatedObject(picker,&WUEmoticonExportKey,lease,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [owner presentViewController:picker animated:YES completion:nil];
    } @catch(__unused NSException *e) { [lease clean]; ExportNotice(owner,@"表情导出准备失败，未保存。"); }
}
void WUExportEmoticonForWrap(UIViewController *owner, id wrap, BOOL (^current)(void)) { WUExportEmoticon(owner,wrap,current,NO); }
void WUExportOriginalEmoticonForWrap(UIViewController *owner, id wrap, BOOL (^current)(void)) { WUExportEmoticon(owner,wrap,current,YES); }
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
@property(nonatomic) BOOL stopped, consumed, pushing, copying;
@property(nonatomic,copy) BOOL (^dataCurrent)(BOOL editing);
@property(nonatomic,copy) BOOL (^menuCurrent)(void);
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
        if(self.dataCurrent) {
            BOOL (^sourceCurrent)(BOOL)=[self.dataCurrent copy];
            if(self.stopped || !owner || !nav || owner.navigationController!=nav || ![nav.viewControllers containsObject:owner] || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || ![WUValue(@"enabled") boolValue] || ![self.account isEqual:WUCurrentAccount()] || self.generation!=WUContextGeneration() || !sourceCurrent || !sourceCurrent(self.editor!=nil)) return NO;
            if(self.stopped) return NO;
            if(self.editor) return self.pushing || ([nav.viewControllers containsObject:self.editor] && [nav.viewControllers indexOfObjectIdenticalTo:owner]<[nav.viewControllers indexOfObjectIdenticalTo:self.editor]);
            return nav.topViewController==owner && owner.viewIfLoaded.window && !owner.presentedViewController;
        }
        if(self.stopped || !owner || !nav || owner.navigationController!=nav || ![nav.viewControllers containsObject:owner] || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || ![WUValue(@"enabled") boolValue] || ![self.account isEqual:WUCurrentAccount()] || self.generation!=WUContextGeneration() || ![self.session isEqual:WUChatSession(owner)] || (!self.menuCurrent && ![WUToolbarActions(WUAccountOptions(self.account)[@"toolbar"]) containsObject:@"imageEmoji"])) return NO;
        if(self.editor) { if(!self.pushing && (![nav.viewControllers containsObject:self.editor] || [nav.viewControllers indexOfObjectIdenticalTo:owner]>=[nav.viewControllers indexOfObjectIdenticalTo:self.editor])) return NO; }
        else if(nav.topViewController!=owner || !owner.viewIfLoaded.window || (owner.presentedViewController && owner.presentedViewController!=self.prompt)) return NO;
        if(![self.identity isEqual:Identity(self.wrap,self.account,self.session)] || ![self.paths isEqual:Paths(self.wrap)]) return NO;
        // Once our editor was pushed, the host may legitimately clear multi-select.
        // Keep the already-confirmed image snapshot; still invalidate account/session,
        // generation, source identity, path changes and navigation ownership above.
        if(self.editor && !self.pushing) return !self.menuCurrent || self.menuCurrent();
        if(self.menuCurrent) return self.menuCurrent();
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
    self.account=nil; self.session=nil; self.owner=nil; self.nav=nil; self.dataCurrent=nil; self.menuCurrent=nil;
    [entries removeObject:self];
}
- (void)fail:(NSString *)message {
    UIViewController *owner=self.owner; BOOL current=[self current]; [self stop];
    if(current) { if(self.copying) NoticeWithTitle(owner,@"复制图片",message); else Notice(owner,message); }
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
        } @catch(__unused NSException *e) { error=@"缓存图片读取或校验失败，未操作。"; }
        dispatch_async(dispatch_get_main_queue(),^{
            if(![self current]) { [self stop]; return; }
            if(error) { [self fail:error]; return; }
            @try {
                self.image=[UIImage imageWithData:data];
                if(!self.image || self.image.images.count) { [self fail:@"图片解码失败或包含动画，未操作。"]; return; }
                if(self.copying) {
                    if(![self current]) { [self stop]; return; }
                    NSString *type=WUEmoticonType(data);
                    if(!type || ![self current]) { [self stop]; return; }
                    [UIPasteboard.generalPasteboard setItems:@[@{type:data}] options:@{UIPasteboardOptionLocalOnly:@YES}];
                    UIViewController *owner=self.owner; [self stop];
                    NoticeWithTitle(owner,@"复制图片",@"已复制当前缓存图片到本机剪贴板，可能不是原图。剪贴板内容可被你主动粘贴到其他应用。");
                    return;
                }
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
            } @catch(__unused NSException *e) { [self fail:@"图片处理失败，未自动重试。"]; }
        });
    });
}
- (void)open {
    if(![self current] || self.editor || !self.image) { [self stop]; return; }
    @try {
        // Verify the editor contract before allocation and navigation.
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
static void EnsureEntries(void) {
    static dispatch_once_t once; dispatch_once(&once,^{
        entries=[NSMutableSet set];
        for(NSString *name in @[UIApplicationWillResignActiveNotification,WUChanged]) [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ WUCancelImageEntries(); }];
    });
}
void WUCancelImageDataEditor(UIViewController *owner) {
    if(!NSThread.isMainThread) return;
    for(WUImageEntry *op in entries.allObjects) if(op.owner==owner && op.dataCurrent) [op stop];
}
BOOL WUOpenConfirmedImageDataEditor(UIViewController *owner, NSData *data, BOOL (^current)(BOOL)) {
    if(!NSThread.isMainThread || !current || !current(NO) || !WUImageEntryValidateData(data)) return NO;
    @try {
        for(WUImageEntry *live in entries) if(live.owner==owner) return NO;
        EnsureEntries();
        WUImageEntry *op=[WUImageEntry new]; op.owner=owner; op.nav=owner.navigationController;
        op.account=WUCurrentAccount(); op.generation=WUContextGeneration(); op.dataCurrent=current;
        op.image=[UIImage imageWithData:data];
        if(!op.account.length || !op.image || op.image.images.count || ![op current]) return NO;
        [entries addObject:op];
        __weak WUImageEntry *weak=op;
        op.timer=[NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer){ WUImageEntry *live=weak; if(![live current]) [live stop]; }];
        [NSRunLoop.mainRunLoop addTimer:op.timer forMode:NSRunLoopCommonModes];
        [op open]; return !op.stopped && op.editor!=nil;
    } @catch(__unused NSException *e) { WUCancelImageDataEditor(owner); return NO; }
}
static void WUStartMessageImage(UIViewController *owner, id wrap, BOOL (^current)(void), BOOL copying) {
    if(!NSThread.isMainThread || !current || !current()) return;
    @try {
        if(!owner.viewIfLoaded.window || owner.presentedViewController || !owner.navigationController || owner.navigationController.topViewController!=owner || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || ![WUValue(@"enabled") boolValue]) return;
        for(WUImageEntry *live in entries) if(live.owner==owner) return;
        NSString *account=WUCurrentAccount(), *session=WUChatSession(owner);
        if(!account.length || !session.length) return;
        NSDictionary *identity=Identity(wrap,account,session); NSArray *paths=identity?Paths(wrap):nil;
        if(!identity || !paths.count) { NoticeWithTitle(owner,copying?@"复制图片":@"图片转表情",@"图片身份或缓存路径不可核验。请先在微信加载图片；未读取其他图片。"); return; }
        EnsureEntries();
        WUImageEntry *op=[WUImageEntry new]; op.owner=owner; op.nav=owner.navigationController; op.account=account; op.session=session; op.generation=WUContextGeneration(); op.wrap=wrap; op.identity=identity; op.paths=paths; op.menuCurrent=current; op.copying=copying;
        [entries addObject:op];
        __weak WUImageEntry *weak=op;
        op.timer=[NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer){ WUImageEntry *live=weak; if(![live current]) [live stop]; }];
        [NSRunLoop.mainRunLoop addTimer:op.timer forMode:NSRunLoopCommonModes];
        if([op current]) [op prepare]; else [op stop];
    } @catch(__unused NSException *e) { NoticeWithTitle(owner,copying?@"复制图片":@"图片转表情",@"图片上下文读取失败，未操作。"); }
}
void WUOpenMessageImageEditor(UIViewController *owner, id wrap, BOOL (^current)(void)) { WUStartMessageImage(owner,wrap,current,NO); }
void WUCopyMessageImage(UIViewController *owner, id wrap, BOOL (^current)(void)) { WUStartMessageImage(owner,wrap,current,YES); }
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
        EnsureEntries();
        WUImageEntry *op=[WUImageEntry new]; op.owner=owner; op.nav=owner.navigationController; op.account=account; op.session=session; op.generation=WUContextGeneration(); op.wrap=wrap; op.identity=identity; op.paths=paths;
        [entries addObject:op];
        __weak WUImageEntry *weak=op;
        op.timer=[NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer){ WUImageEntry *live=weak; if(![live current]) [live stop]; }];
        [NSRunLoop.mainRunLoop addTimer:op.timer forMode:NSRunLoopCommonModes];
        if([op current]) [op prepare]; else [op stop];
    } @catch(__unused NSException *e) { WUCancelImageEntries(); Notice(owner,@"所选图片上下文读取失败，未打开编辑器。"); }
}
