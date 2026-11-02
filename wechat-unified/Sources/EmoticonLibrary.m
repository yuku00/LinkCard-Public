#import "EmoticonLibrary.h"
#import "EmoticonLibraryLogic.h"
#import "EmoticonLogic.h"
#import "EmoticonSubmission.h"
#import "MessageEntries.h"
#import "WU.h"
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
@implementation WUEmoticonLibraryBinding
@end
static dispatch_queue_t Queue(void) { static dispatch_queue_t q; static dispatch_once_t once; dispatch_once(&once,^{ q=dispatch_queue_create("WU.emoticon-library",DISPATCH_QUEUE_SERIAL); }); return q; }
@interface WUEmoticonPreview : UIViewController {
    CGImageSourceRef _source;
    size_t _frame;
}
@property(nonatomic,strong) NSData *data;
@property(nonatomic,strong) UIImageView *imageView;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) BOOL (^current)(void);
@end
@implementation WUEmoticonPreview
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.imageView=[[UIImageView alloc] initWithFrame:self.view.bounds]; self.imageView.contentMode=UIViewContentModeScaleAspectFit; self.imageView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:self.imageView];
    self.imageView.accessibilityLabel=@"原表情预览；GIF按原帧时长播放，不改保存字节";
    _source=CGImageSourceCreateWithData((__bridge CFDataRef)self.data,(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
}
- (void)nextFrame {
    if(!_source || !self.current || !self.current() || !self.view.window) { [self.timer invalidate]; self.timer=nil; return; }
    size_t count=CGImageSourceGetCount(_source); if(!count || count>500) return;
    CGImageRef image=CGImageSourceCreateThumbnailAtIndex(_source,_frame,(__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(id)kCGImageSourceThumbnailMaxPixelSize:@512,(id)kCGImageSourceShouldCacheImmediately:@YES});
    if(!image) return; self.imageView.image=[UIImage imageWithCGImage:image]; CGImageRelease(image);
    NSDictionary *p=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(_source,_frame,NULL)), *gif=p[(id)kCGImagePropertyGIFDictionary];
    double delay=[gif[(id)kCGImagePropertyGIFUnclampedDelayTime] doubleValue]; if(delay<=0) delay=[gif[(id)kCGImagePropertyGIFDelayTime] doubleValue]; if(delay<0.02) delay=0.1;
    _frame=(_frame+1)%count;
    if(count>1) { __weak typeof(self) weak=self; self.timer=[NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(NSTimer *t){ [weak nextFrame]; }]; }
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self nextFrame]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; [self.timer invalidate]; self.timer=nil; }
- (void)dealloc { [self.timer invalidate]; if(_source) CFRelease(_source); }
@end
@interface WUEmoticonLibraryController : UITableViewController <UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@property(nonatomic,strong) WUEmoticonLibraryBinding *binding;
@property(nonatomic,strong) WUEmoticonLibraryStore *store;
@property(nonatomic,strong) NSDictionary *state;
@property(nonatomic,copy) NSString *filter;
@property(nonatomic,strong) NSArray *rows;
@property(nonatomic,strong) NSMutableSet *submitted;
@property(nonatomic,strong) NSProgress *cancel;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) id backgroundObserver;
@property(nonatomic,weak) UIDocumentPickerViewController *picker;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL invalid;
@end
@implementation WUEmoticonLibraryController
- (BOOL)current { return !self.invalid && self.binding.current && self.binding.current(); }
- (void)invalidate { self.invalid=YES; [self.cancel cancel]; [self.timer invalidate]; self.timer=nil; self.rows=nil; self.state=nil; }
- (void)close { [self invalidate]; [self.navigationController.presentingViewController dismissViewControllerAnimated:NO completion:nil]; }
- (BOOL)presentationControllerShouldDismiss:(UIPresentationController *)presentationController { return !self.busy; }
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController { [self invalidate]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; if(self.navigationController.isBeingDismissed || !self.navigationController.presentingViewController) [self invalidate]; }
- (void)notice:(NSString *)message {
    if(![self current]) return;
    UIViewController *presented=self.presentedViewController;
    if(presented) {
        if([presented isKindOfClass:UIAlertController.class] || [presented isKindOfClass:UIDocumentPickerViewController.class]) [self dismissViewControllerAnimated:NO completion:^{ [self notice:message]; }];
        return;
    }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"本账号本地表情库" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"本地表情分组"; self.cancel=[NSProgress progressWithTotalUnitCount:1]; self.submitted=[NSMutableSet set];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc] initWithTitle:@"导入" style:UIBarButtonItemStylePlain target:self action:@selector(importMenu)],[[UIBarButtonItem alloc] initWithTitle:@"新分组" style:UIBarButtonItemStylePlain target:self action:@selector(createGroup)]];
    __weak typeof(self) weak=self;
    self.backgroundObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ [weak close]; }];
    self.timer=[NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t){ if(![weak current]) [weak close]; }]; [self reload];
}
- (void)dealloc { if(self.backgroundObserver) [NSNotificationCenter.defaultCenter removeObserver:self.backgroundObserver]; [self.timer invalidate]; }
- (void)reload {
    if(![self current] || self.busy) return; self.busy=YES;
    dispatch_async(Queue(),^{ NSError *error=nil; NSDictionary *state=[self.store load:&error];
        dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; if(![self current]) return; self.state=state; self.rows=WUEmoticonLibraryRows(state,self.filter); [self.tableView reloadData]; if(error) [self notice:error.localizedDescription]; });
    });
}
- (void)write:(BOOL (^)(BOOL (^)(void),NSError **))operation {
    if(![self current] || self.busy) return; self.busy=YES; NSUInteger gen=self.binding.generation;
    dispatch_async(Queue(),^{ NSError *error=nil;
        BOOL ok=operation(^BOOL{ return !self.cancel.cancelled && gen==WUContextGenerationSnapshot(); },&error);
        dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; if(![self current]) return; if(ok) [self reload]; else [self notice:error.localizedDescription?:@"保存失败，旧库保留"]; });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section==0?2+[self.state[@"groups"] count]:self.rows.count; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return section==0?@"本账号分组 · 长按改名/排序/删除":@"点按预览 / 移动 / 重命名 / 手动确认发送"; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if(section==0) return @"删组只解除自有映射，不删库内资源或宿主表情。与官方心形页分组独立。";
    NSString *text=@"原始GIF/PNG/JPEG，不转码不取首帧；每条≤20MiB、共128条/48MiB。只按手动选择复制，不扫描媒体。关闭或切号后待处理动作失效。发送请求不等于送达。";
    return self.binding.canSubmit && self.binding.canSubmit()?text:[text stringByAppendingString:@" 当前宿主缺少已核对表情工厂/提交签名，发送动作不展示；导入与管理仍可用。"];
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if(p.section==0) {
        NSString *gid=p.row==0?nil:(p.row==1?@"":self.state[@"groups"][p.row-2][@"id"]);
        c.textLabel.text=p.row==0?@"全部":(p.row==1?@"未分组":self.state[@"groups"][p.row-2][@"name"]);
        if((!gid&&!self.filter)||[gid isEqual:self.filter]) c.accessoryType=UITableViewCellAccessoryCheckmark;
    } else { NSDictionary *r=self.rows[p.row]; c.textLabel.text=r[@"name"]; c.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %lu字节",[r[@"uti"] isEqual:@"com.compuserve.gif"]?@"GIF（原动画）":r[@"uti"],(unsigned long)[r[@"data"] length]]; }
    return c;
}
- (void)input:(NSString *)title value:(NSString *)value completion:(void (^)(NSString *))completion {
    if(![self current] || self.busy || self.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t){ t.text=value; }]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weak=a; __block BOOL used=NO;
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ if(used || ![self current]) return; used=YES; completion([weak.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]); }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)createGroup { [self input:@"新建本地表情分组" value:nil completion:^(NSString *name){ [self write:^BOOL(BOOL (^valid)(void),NSError **error){ return [self.store createGroup:name current:valid error:error]; }]; }]; }
- (void)saveSelectedGIFOnly:(BOOL)GIFOnly {
    NSDictionary *capture=self.binding.capture?self.binding.capture():nil;
    if(!capture) { [self notice:@"请先在当前聊天多选一个就绪表情（47类），再打开本地库；普通图片消息、未选择消息、缩略图或相册不作替代。"]; return; }
    [self input:GIFOnly?@"保存所选GIF到本账号本地库（非官方心形）":@"复制所选原表情到本账号库" value:GIFOnly?@"所选GIF":@"所选表情" completion:^(NSString *name){
        if(!self.binding.selectionCurrent || !self.binding.selectionCurrent(capture)) { [self notice:@"所选消息已经变化，未读取文件"]; return; }
        NSString *group=self.filter?:@"";
        [self write:^BOOL(BOOL (^valid)(void),NSError **error){
            BOOL (^selectedCurrent)(void)=^BOOL {
                if(!valid()) return NO;
                __block BOOL selected=NO;
                // Host selection and UIKit access stay on main; the UI never waits for Queue().
                void (^check)(void)=^{ selected=[self current] && self.binding.selectionCurrent && self.binding.selectionCurrent(capture); };
                if(NSThread.isMainThread) check(); else dispatch_sync(dispatch_get_main_queue(),check);
                return selected && valid();
            };
            return [self.store importSelectedPath:capture[@"path"] md5:capture[@"md5"] GIFOnly:GIFOnly name:name group:group current:selectedCurrent error:error];
        }];
    }];
}
- (void)prepareSelectedOfficialGIF {
    if(![self current] || self.busy || self.presentedViewController) return;
    NSDictionary *capture=self.binding.capture?self.binding.capture():nil;
    if(!capture || !self.binding.selectionCurrent || !self.binding.selectionCurrent(capture)) { [self notice:@"请先在当前聊天选择一个已就绪的GIF表情；未读取或提交。"]; return; }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"检查所选GIF的微信添加条件？" message:@"仅检查当前所选表情的原始字节和微信包装字段；数据交付及回调契约尚未核实，本操作不会提交或添加到微信官方表情。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __block BOOL used=NO;
    [a addAction:[UIAlertAction actionWithTitle:@"检查" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if(used) return; used=YES;
        if(![self current] || !self.binding.selectionCurrent(capture)) return;
        self.busy=YES; NSUInteger gen=self.binding.generation;
        dispatch_async(Queue(),^{
            NSData *data=gen==WUContextGenerationSnapshot()?WUEmoticonRead(capture[@"path"]):nil;
            dispatch_async(dispatch_get_main_queue(),^{
                self.busy=NO;
                BOOL (^valid)(void)=^BOOL { return [self current] && self.binding.selectionCurrent && self.binding.selectionCurrent(capture); };
                if(!valid()) return;
                NSString *result=WUPrepareOfficialGIF(data,capture[@"md5"],valid);
                if(valid()) [self notice:result];
            });
        });
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)importMenu {
    if(self.busy || ![self current] || self.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"导入到本账号库" message:@"仅保存本账号隔离的本地副本，不是微信官方心形表情入库。复制原始字节并保留GIF动画；不删除原消息，不上传、不自动发送。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"检查所选GIF的微信添加条件（暂不提交）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self dismissViewControllerAnimated:NO completion:^{ [self prepareSelectedOfficialGIF]; }]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存聊天所选GIF（仅本地库）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self dismissViewControllerAnimated:NO completion:^{ [self saveSelectedGIFOnly:YES]; }]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"复制聊天所选原表情" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self dismissViewControllerAnimated:NO completion:^{ [self saveSelectedGIFOnly:NO]; }]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"选择一个本地GIF/PNG/JPEG文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self dismissViewControllerAnimated:NO completion:^{
        if(![self current]) return;
        UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES]; p.delegate=self; p.allowsMultipleSelection=NO; self.picker=p; self.busy=YES; [self presentViewController:p animated:YES completion:nil];
    }]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { if(controller==self.picker) { self.picker=nil; self.busy=NO; } }
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if(controller!=self.picker) return; self.picker=nil; self.busy=NO;
    if(![self current] || urls.count!=1) return;
    NSURL *url=urls.firstObject; NSString *name=url.lastPathComponent.stringByDeletingPathExtension; if(name.length>80) name=[name substringToIndex:80];
    NSString *group=self.filter?:@"";
    [self write:^BOOL(BOOL (^valid)(void),NSError **error){
        if(!valid()) return NO;
        BOOL scoped=[url startAccessingSecurityScopedResource];
        @try { return [self.store importFile:url name:name group:group current:valid error:error]; }
        @finally { if(scoped) [url stopAccessingSecurityScopedResource]; }
    }];
}
- (void)use:(NSDictionary *)row sending:(BOOL)sending {
    if(self.busy || ![self current] || self.presentedViewController) return;
    if(sending && [self.submitted containsObject:row[@"id"]]) { [self notice:@"本次页面已提交此资源；请核对聊天记录，不自动重试。重新打开仍需手动确认。"]; return; }
    self.busy=YES;
    dispatch_async(Queue(),^{ NSError *error=nil; NSDictionary *held=[self.store resource:row[@"id"] error:&error];
        dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; if(![self current]) return;
            if(!held) { [self notice:error.localizedDescription?:@"资源不可用"]; return; }
            if(!sending) {
                WUEmoticonPreview *p=[WUEmoticonPreview new]; p.title=held[@"name"]; p.data=held[@"data"]; __weak typeof(self) weak=self; p.current=^BOOL{ return [weak current]; }; [self.navigationController pushViewController:p animated:YES]; return;
            }
            NSString *hint=[held[@"uti"] isEqual:@"com.compuserve.gif"]?@"\n如微信支持该表情，发送后可在聊天中长按它并选择微信原生的添加表情；是否可添加及结果以微信页面为准。此按钮本身不向官方表情库入库。":@"";
            UIAlertController *a=[UIAlertController alertControllerWithTitle:@"手动发送这一个原表情？" message:[NSString stringWithFormat:@"名称：%@\n账号：%@\n当前会话收件人：%@\n只提交一次，不批量、不后台发送。%@",held[@"name"],self.binding.account,self.binding.target,hint] preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            __block BOOL used=NO;
            [a addAction:[UIAlertAction actionWithTitle:@"确认发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
                if(used || ![self current] || [self.submitted containsObject:held[@"id"]]) return; used=YES; [self.submitted addObject:held[@"id"]];
                NSString *result=self.binding.submit?self.binding.submit(held[@"data"]):@"当前没有已核对发送接口；未发送";
                [self dismissViewControllerAnimated:NO completion:^{ if([self current]) [self notice:result]; }];
            }]]; [self presentViewController:a animated:YES completion:nil];
        });
    });
}
- (void)exportRow:(NSDictionary *)row {
    if(self.busy || ![self current] || self.presentedViewController) return;
    self.busy=YES;
    dispatch_async(Queue(),^{ NSError *error=nil; NSDictionary *held=[self.store resource:row[@"id"] error:&error];
        dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; if(![self current]) return;
            if(!held) { [self notice:error.localizedDescription?:@"资源不可用，未导出"]; return; }
            __weak typeof(self) weak=self;
            WUExportEmoticonData(self,held[@"data"],^BOOL{ return weak && [weak current]; });
        });
    });
}
- (void)assign:(NSDictionary *)row {
    if(![self current] || self.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"移动自有表情分组" message:@"仅改变本地库映射，原宿主表情不动。" preferredStyle:UIAlertControllerStyleAlert];
    NSArray *groups=[@[@{@"id":@"",@"name":@"未分组"}] arrayByAddingObjectsFromArray:self.state[@"groups"]?:@[]];
    for(NSDictionary *g in groups) [a addAction:[UIAlertAction actionWithTitle:g[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self write:^BOOL(BOOL (^valid)(void),NSError **error){ return [self.store assign:row[@"id"] group:g[@"id"] current:valid error:error]; }]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)manage:(NSDictionary *)row group:(BOOL)group {
    if(self.busy || ![self current] || self.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:row[@"name"] message:group?@"只改本地库分组；删组保留全部资源。":@"只操作本账号自有副本，不改微信原表情。" preferredStyle:UIAlertControllerStyleAlert];
    if(!group) {
        [a addAction:[UIAlertAction actionWithTitle:@"预览原图/动画" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self dismissViewControllerAnimated:NO completion:^{ [self use:row sending:NO]; }]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"导出原文件到文件App" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self dismissViewControllerAnimated:NO completion:^{ [self exportRow:row]; }]; }]];
        if(self.binding.canSubmit && self.binding.canSubmit()) [a addAction:[UIAlertAction actionWithTitle:@"确认后发送到当前会话" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self dismissViewControllerAnimated:NO completion:^{ [self use:row sending:YES]; }]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"移动到分组" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self dismissViewControllerAnimated:NO completion:^{ [self assign:row]; }]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"重命名" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self dismissViewControllerAnimated:NO completion:^{
        [self input:@"重命名" value:row[@"name"] completion:^(NSString *name){ [self write:^BOOL(BOOL (^valid)(void),NSError **error){ return [self.store rename:row[@"id"] group:group name:name current:valid error:error]; }]; }];
    }]; }]];
    NSArray *items=self.state[group?@"groups":@"rows"], *scope=group?items:self.rows;
    NSUInteger i=[scope indexOfObjectPassingTest:^BOOL(NSDictionary *r,NSUInteger idx,BOOL *stop){ return [r[@"id"] isEqual:row[@"id"]]; }];
    if(i!=NSNotFound) for(NSNumber *target in [NSOrderedSet orderedSetWithArray:@[@0,@(i?i-1:0),@(MIN(i+1,scope.count-1)),@(scope.count-1)]]) {
        NSUInteger index=target.unsignedIntegerValue; if(index==i) continue;
        NSString *destinationID=scope[index][@"id"];
        NSUInteger destination=[items indexOfObjectPassingTest:^BOOL(NSDictionary *r,NSUInteger idx,BOOL *stop){ return [r[@"id"] isEqual:destinationID]; }];
        if(destination==NSNotFound) continue;
        NSString *title=index==0?@"移到最前":(index==scope.count-1?@"移到最后":(index<i?@"前移一位":@"后移一位"));
        [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self write:^BOOL(BOOL (^valid)(void),NSError **error){ return [self.store move:row[@"id"] group:group to:destination current:valid error:error]; }]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:group?@"删除分组（保留表情）":@"删除自有副本" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
        [self dismissViewControllerAnimated:NO completion:^{
            if(![self current]) return;
            UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"确定删除？" message:group?@"库内表情全部保留并回到未分组，不删除任何源文件。":@"只删除本账号库中这一份副本；不会访问或删除微信原媒体。" preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [confirm addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
                if(group && [self.filter isEqual:row[@"id"]]) self.filter=nil;
                [self write:^BOOL(BOOL (^valid)(void),NSError **error){ return [self.store remove:row[@"id"] group:group current:valid error:error]; }];
            }]]; [self presentViewController:confirm animated:YES completion:nil];
        }];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)p {
    [table deselectRowAtIndexPath:p animated:YES]; if(![self current] || self.busy) return;
    if(p.section==0) { self.filter=p.row==0?nil:(p.row==1?@"":self.state[@"groups"][p.row-2][@"id"]); self.rows=WUEmoticonLibraryRows(self.state,self.filter); [table reloadData]; }
    else [self manage:self.rows[p.row] group:NO];
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)table contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)p point:(CGPoint)point {
    if(![self current] || self.busy || (p.section==0 && p.row<2)) return nil;
    BOOL group=p.section==0; NSDictionary *row=group?self.state[@"groups"][p.row-2]:self.rows[p.row];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested){
        return [UIMenu menuWithTitle:row[@"name"] children:@[[UIAction actionWithTitle:@"管理 / 重命名 / 排序" image:nil identifier:nil handler:^(UIAction *x){ [self manage:row group:group]; }]]];
    }];
}
@end
BOOL WUIsEmoticonLibraryController(UIViewController *controller) {
    return [controller isKindOfClass:UINavigationController.class] && [[(UINavigationController *)controller viewControllers].firstObject isKindOfClass:WUEmoticonLibraryController.class];
}
void WUShowEmoticonLibrary(UIViewController *owner, WUEmoticonLibraryBinding *binding) {
    if(!NSThread.isMainThread || !owner.viewIfLoaded.window || owner.presentedViewController || !binding.current || !binding.current()) return;
    NSURL *root=[[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByResolvingSymlinksInPath] URLByAppendingPathComponent:@"WeChatUnifiedEmoticons" isDirectory:YES];
    WUEmoticonLibraryStore *store=[[WUEmoticonLibraryStore alloc] initWithRoot:root account:binding.account]; if(!store) return;
    WUEmoticonLibraryController *controller=[[WUEmoticonLibraryController alloc] initWithStyle:UITableViewStyleInsetGrouped]; controller.binding=binding; controller.store=store;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:controller]; nav.presentationController.delegate=controller; [owner presentViewController:nav animated:YES completion:nil];
}
