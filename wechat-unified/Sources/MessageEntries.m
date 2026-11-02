#import "MessageEntries.h"
#import "LinkLogic.h"
#import "EmoticonLogic.h"
#import "RepeatOptions.h"
#import "ThemeRendering.h"
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#include <errno.h>
static NSString *StoreIcon(NSData *data);
@interface WUMessageEntryFlow : NSObject <UIDocumentPickerDelegate, SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate>
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,copy) BOOL (^current)(void);
@property(nonatomic,strong) UIViewController *controller;
@property(nonatomic,strong) NSURL *staging;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL transitioning;
@property(nonatomic) BOOL importIcon;
@property(nonatomic) BOOL picked;
- (BOOL)valid;
- (void)finish;
- (void)show:(UIViewController *)controller;
- (void)chooseController:(UIViewController *)expected action:(void (^)(void))action;
- (void)notice:(NSString *)text;
- (void)links:(NSArray<NSDictionary *> *)candidates;
- (void)destination:(NSURL *)url;
@end
static NSMutableSet<WUMessageEntryFlow *> *flows;
static NSTimer *poll;
BOOL WUMessageEntriesOwnsController(UIViewController *controller) {
    if(!controller) return NO;
    for(WUMessageEntryFlow *flow in flows) if(flow.controller==controller) return YES;
    return NO;
}
void WUCancelMessageEntries(void) { for(WUMessageEntryFlow *flow in flows.allObjects) [flow finish]; }
static WUMessageEntryFlow *Begin(UIViewController *owner,BOOL (^current)(void)) {
    if(!NSThread.isMainThread || !owner.viewIfLoaded.window || owner.presentedViewController || !current) return nil;
    static dispatch_once_t once; dispatch_once(&once,^{
        flows=[NSMutableSet set];
        for(NSString *name in @[WUChanged,UIApplicationWillResignActiveNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ WUCancelMessageEntries(); }];
    });
    for(WUMessageEntryFlow *other in flows) if(other.owner==owner) return nil;
    WUMessageEntryFlow *flow=[WUMessageEntryFlow new]; flow.owner=owner; flow.current=current;
    if(![flow valid]) return nil;
    [flows addObject:flow];
    if(!poll) { poll=[NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer){
        for(WUMessageEntryFlow *pending in flows.allObjects) {
            if(![pending valid] || (!pending.transitioning && pending.controller && pending.owner.presentedViewController!=pending.controller)) [pending finish];
        }
    }]; [NSRunLoop.mainRunLoop addTimer:poll forMode:NSRunLoopCommonModes]; }
    return flow;
}
@implementation WUMessageEntryFlow
- (BOOL)valid {
    @try { return !self.finished && self.owner && (!self.owner.presentedViewController || self.owner.presentedViewController==self.controller) && (self.owner.viewIfLoaded.window || WUMessageEntriesOwnsController(self.owner.presentedViewController)) && (!self.owner.navigationController || self.owner.navigationController.topViewController==self.owner) && UIApplication.sharedApplication.applicationState==UIApplicationStateActive && self.current && self.current(); }
    @catch(__unused NSException *e) { return NO; }
}
- (void)finish {
    if(self.finished) return; self.finished=YES;
    UIViewController *controller=self.controller; self.controller=nil;
    if(controller && self.owner.presentedViewController==controller) [controller dismissViewControllerAnimated:NO completion:nil];
    if(self.staging) [NSFileManager.defaultManager removeItemAtURL:self.staging error:NULL]; self.staging=nil;
    [flows removeObject:self]; if(!flows.count) { [poll invalidate]; poll=nil; }
    self.current=nil;
}
- (void)show:(UIViewController *)controller {
    if(![self valid] || self.owner.presentedViewController) { [self finish]; return; }
    self.controller=controller; self.transitioning=YES;
    __weak WUMessageEntryFlow *weak=self;
    @try { [self.owner presentViewController:controller animated:YES completion:^{ weak.transitioning=NO; controller.presentationController.delegate=weak; }]; }
    @catch(__unused NSException *e) { [self finish]; }
}
- (void)chooseController:(UIViewController *)expected action:(void (^)(void))action {
    if(self.transitioning || !expected || self.controller!=expected || ![self valid]) return;
    self.transitioning=YES;
    UIViewController *controller=self.controller;
    void (^next)(void)=^{
        if(self.finished) return;
        self.controller=nil; self.transitioning=NO;
        if(![self valid] || self.owner.presentedViewController) { [self finish]; return; }
        action();
    };
    if(controller && self.owner.presentedViewController==controller) [controller dismissViewControllerAnimated:NO completion:next]; else next();
}
- (void)notice:(NSString *)text {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"微信整合" message:text preferredStyle:UIAlertControllerStyleAlert];
    __weak WUMessageEntryFlow *weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){ [weak finish]; }]]; [self show:a];
}
- (void)links:(NSArray<NSDictionary *> *)candidates {
    if(!candidates.count) { [self notice:@"所选消息未发现可用 HTTP(S) 链接。仅识别文本和卡片 msg/appmsg/url；不读取网页、附件、缩略图或未选消息。每条≤8192字符、总计≤65536字符。 "]; return; }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"选择所选消息中的网址" message:@"最多列出10个；即使只有一个也需要主动选择。不会自动访问或保存历史。" preferredStyle:UIAlertControllerStyleAlert];
    __weak WUMessageEntryFlow *weak=self; __weak UIAlertController *expected=a;
    for(NSDictionary *candidate in candidates) {
        NSURL *url=candidate[@"url"];
        NSString *title=[NSString stringWithFormat:@"%@\n%@",candidate[@"source"],url.absoluteString];
        [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [weak chooseController:expected action:^{ [weak destination:url]; }]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){ [weak finish]; }]]; [self show:a];
}
- (void)destination:(NSURL *)url {
    NSDictionary *destination=WULinkDestination(url);
    if(destination[@"error"]) { [self notice:destination[@"error"]]; return; }
    NSURL *target=destination[@"url"];
    NSString *warning=[destination[@"risk"] boolValue]?@"警告：从微信风险提示地址的唯一 url 参数提取原目标。这不是安全认证，也不是解除服务器封禁。\n":@"识别网址不代表安全，不关闭微信或系统风险检查。\n";
    NSString *message=[NSString stringWithFormat:@"%@目标域名：%@\n%@\n\n内置 Safari 组件留在本应用；系统默认浏览器不一定是 Safari，也不保证排除通用链接的系统路由。",warning,target.host,target.absoluteString];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认目标并选择打开方式" message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak WUMessageEntryFlow *weak=self; __weak UIAlertController *expected=a;
    [a addAction:[UIAlertAction actionWithTitle:@"内置 Safari 组件打开" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [weak chooseController:expected action:^{
        WUMessageEntryFlow *flow=weak; if(![flow valid]) return;
        SFSafariViewController *safari=[[SFSafariViewController alloc] initWithURL:target]; safari.delegate=flow; [flow show:safari];
    }]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"交给系统默认浏览器" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [weak chooseController:expected action:^{
        WUMessageEntryFlow *flow=weak; if(![flow valid]) return;
        [UIApplication.sharedApplication openURL:target options:@{} completionHandler:^(BOOL ok){ dispatch_async(dispatch_get_main_queue(),^{
            if(![flow valid]) { [flow finish]; return; }
            if(ok) [flow finish]; else [flow notice:@"系统未接受打开请求，未重试。外部浏览器由系统设置及通用链接路由决定。"];
        }); }];
    }]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){ [weak finish]; }]]; [self show:a];
}
- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller { [self finish]; }
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller { [self finish]; }
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { [self finish]; }
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if(self.finished || self.picked || controller!=self.controller) return; self.picked=YES;
    if(![self valid]) { [self finish]; return; }
    if(!self.importIcon) {
        BOOL confirmed=urls.count==1 && [urls.firstObject isFileURL];
        [self chooseController:controller action:^{
            if(self.staging) [NSFileManager.defaultManager removeItemAtURL:self.staging error:NULL]; self.staging=nil;
            [self notice:confirmed?@"系统文件选择器已确认导出原表情；GIF原字节保留。云盘后续同步以Files状态为准。":@"文件选择器没有返回已导出的目标，不能确认下载成功。未重试。"];
        }]; return;
    }
    NSURL *source=urls.count==1?urls.firstObject:nil;
    [self chooseController:controller action:^{
        if(!source.isFileURL) { [self notice:@"未选中可读取的本地图片文件，图标未更改。"]; return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            BOOL scoped=[source startAccessingSecurityScopedResource]; __block NSData *data=nil;
            NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil]; NSError *error=nil;
            [coordinator coordinateReadingItemAtURL:source options:0 error:&error byAccessor:^(NSURL *url){ data=WUEmoticonRead(url.path); }];
            if(scoped) [source stopAccessingSecurityScopedResource];
            BOOL valid=!error && WUEmoticonType(data)!=nil && WUThemeValidImage(data);
            dispatch_async(dispatch_get_main_queue(),^{
                if(![self valid]) { [self finish]; return; }
                if(!valid) { [self notice:@"图标读取或格式验证失败。请选择完整GIF/PNG/JPEG（≤8MiB）；原配置保留。"]; return; }
                NSString *identifier=StoreIcon(data);
                if(!identifier) { [self notice:@"图标文件写入失败或已达32个导入文件，未改变配置。"]; return; }
                NSMutableDictionary *next=[(WUValue(@"repeatOptions")?:WURepeatDefaults()) mutableCopy]; next[@"userIcon"]=identifier;
                // Config notification cancels every pending action, including this picker. Finish first.
                UIViewController *owner=self.owner; BOOL (^current)(void)=self.current; [self finish];
                if(!current()) return;
                if(!WUSave(@"repeatOptions",next)) {
                    WUMessageEntryFlow *failure=Begin(owner,current);
                    [failure notice:@"图标配置写盘失败，原配置保留；不会假报导入成功。"];
                }
            });
        });
    }];
}
@end
static NSString *StoreIcon(NSData *data) {
    NSString *support=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;
    if(!support.length) return nil;
    // Resolve the system-provided base alias, but never follow our own child directory.
    NSString *base=[support.stringByResolvingSymlinksInPath stringByAppendingPathComponent:@"WeChatUnified"];
    int root=open(base.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); if(root<0) return nil;
    mkdirat(root,"RepeatIcons",0700); int dir=openat(root,"RepeatIcons",O_RDONLY|O_DIRECTORY|O_NOFOLLOW); close(root); if(dir<0) return nil;
    NSString *path=[base stringByAppendingPathComponent:@"RepeatIcons"];
    NSArray *existing=[NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:NULL];
    if(!existing || existing.count>=32) { close(dir); return nil; }
    NSString *identifier=NSUUID.UUID.UUIDString; int fd=openat(dir,identifier.UTF8String,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(fd<0) { close(dir); return nil; }
    NSUInteger offset=0;
    while(offset<data.length) { ssize_t n=write(fd,(const char *)data.bytes+offset,data.length-offset); if(n<0 && errno==EINTR) continue; if(n<=0) break; offset+=(NSUInteger)n; }
    BOOL ok=offset==data.length && fsync(fd)==0; if(close(fd)!=0) ok=NO;
    if(!ok) unlinkat(dir,identifier.UTF8String,0); else fsync(dir); close(dir); return ok?identifier:nil;
}
void WUOpenSelectedLinks(UIViewController *owner,NSArray<NSDictionary *> *frozen,BOOL (^current)(void)) {
    WUMessageEntryFlow *flow=Begin(owner,current); if(flow) [flow links:WULinkCandidates(frozen)];
}
static void ExportEmoticon(UIViewController *owner,NSString *path,NSData *bytes,BOOL (^current)(void)) {
    WUMessageEntryFlow *flow=Begin(owner,current); if(!flow) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"下载原表情到文件？" message:@"仅复制当前表情的原GIF/PNG/JPEG字节，再由系统文件选择器选择目标。不用Photos替代，不自动拉取媒体。" preferredStyle:UIAlertControllerStyleAlert];
    __weak WUMessageEntryFlow *weak=flow; __weak UIAlertController *expected=a;
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){ [weak finish]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"选择文件保存位置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [weak chooseController:expected action:^{
        WUMessageEntryFlow *pending=weak; if(![pending valid]) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            NSData *data=bytes?:WUEmoticonRead(path); NSString *type=WUEmoticonType(data);
            dispatch_async(dispatch_get_main_queue(),^{
                if(![pending valid]) { [pending finish]; return; }
                if(!type) { [pending notice:@"原表情文件不可得、损坏、超限或格式不支持，未导出。没有静默重编码，也没有用缩略图替代。"]; return; }
                NSURL *directory=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[@"WUExport-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
                if(![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:NULL]) { [pending notice:@"暂存目录不可写，未导出。"]; return; }
                pending.staging=directory;
                NSString *extension=[type isEqual:@"com.compuserve.gif"]?@"gif":([type isEqual:@"public.png"]?@"png":@"jpg");
                NSURL *file=[directory URLByAppendingPathComponent:[@"Emoticon" stringByAppendingPathExtension:extension]];
                if(![data writeToURL:file options:NSDataWritingAtomic error:NULL]) { [NSFileManager.defaultManager removeItemAtURL:directory error:NULL]; pending.staging=nil; [pending notice:@"原表情暂存失败，未导出。"]; return; }
                UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[file] asCopy:YES];
                picker.delegate=pending; [pending show:picker];
            });
        });
    }]; }]]; [flow show:a];
}
void WUExportEmoticon(UIViewController *owner,NSString *path,BOOL (^current)(void)) { ExportEmoticon(owner,path,nil,current); }
void WUExportEmoticonData(UIViewController *owner,NSData *data,BOOL (^current)(void)) { ExportEmoticon(owner,nil,[data copy],current); }
void WUChooseRepeatIcon(UIViewController *owner) {
    NSString *account=WUCurrentAccount(); NSUInteger generation=WUContextGeneration(); __weak UIViewController *weak=owner;
    if(!account.length) return;
    WUMessageEntryFlow *flow=Begin(owner,^BOOL {
        return weak && [WUValue(@"enabled") boolValue] && [account isEqual:WUCurrentAccount()] && generation==WUContextGeneration();
    }); if(!flow) return;
    flow.importIcon=YES;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES]; picker.allowsMultipleSelection=NO; picker.delegate=flow; [flow show:picker];
}
void WUOpenLinkInput(UIViewController *owner) {
    NSString *account=WUCurrentAccount(); NSUInteger generation=WUContextGeneration(); if(!account.length) return;
    WUMessageEntryFlow *flow=Begin(owner,^BOOL { return [WUValue(@"enabled") boolValue] && [account isEqual:WUCurrentAccount()] && generation==WUContextGeneration(); });
    if(!flow) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"手动识别链接" message:@"不自动读取剪贴板；限8192字符。不保存输入或网址历史。聊天消息请使用账号工具栏中的“所选消息链接”。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *field){ field.placeholder=@"https://example.com"; field.autocorrectionType=UITextAutocorrectionTypeNo; field.autocapitalizationType=UITextAutocapitalizationTypeNone; }];
    __weak WUMessageEntryFlow *weak=flow; __weak UIAlertController *input=a;
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){ [weak finish]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"识别" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *text=[input.textFields.firstObject.text copy]?:@"";
        [weak chooseController:input action:^{
            NSMutableArray *candidates=[NSMutableArray array];
            for(NSDictionary *candidate in WULinkCandidates(@[@{@"type":@1,@"content":text}])) [candidates addObject:@{@"url":candidate[@"url"],@"source":@"手动输入"}];
            [weak links:candidates];
        }];
    }]]; [flow show:a];
}
