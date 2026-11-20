#import <UIKit/UIKit.h>
#import "WUStorage.h"
#import "WUNeoSettings.h"
#import "WUBackupTar.h"

@interface WUBackupController : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,strong) NSURL *staging;
@property(nonatomic,assign) BOOL busy;
- (void)confirm;
- (void)prepare;
@end

@implementation WUBackupController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"插件数据备份"; WUNeoPreparePage(self);
    UILabel *text=[UILabel new]; text.numberOfLines=0; text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    text.text=@"手动导出本机插件数据副本（包括所有账号的配置、语音包、消息仓库、主题与气泡、插件表情及其他插件数据）。不会自动上传。备份不加密，包含账号标识及私密内容，请保存到可信位置。\n\n请先停止修改插件数据；备份不是跨模块原子快照，且仅保存文件内容和插件统计布局偏好，不保存扩展属性、系统权限或钥匙串。仓库中的微信消息/媒体引用不是媒体副本，不包含微信数据库。文件不可读、文件变化、符号链接或路径超出TAR格式限制时会失败，不会跳过或修改源数据。\n\n本页仅导出，没有导入或自动恢复。当前插件数据位于 Documents/WeChatUnifiedStorage；旧 Application Support 副本保留但不再更新。Documents 不保证在 Files 中可见，卸载微信仍会删除整个应用容器。";
    self.status=[UILabel new]; self.status.numberOfLines=0; self.status.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.button=[UIButton buttonWithType:UIButtonTypeSystem]; [self.button setTitle:@"选择文件位置导出备份" forState:UIControlStateNormal]; [self.button addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[text,self.status,self.button]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=16; stack.translatesAutoresizingMaskIntoConstraints=NO;
    UIScrollView *scroll=[UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:scroll]; [scroll addSubview:stack];
    UILayoutGuide *g=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:g.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],[scroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]]];
}
- (void)clean { NSURL *dir=self.staging; self.staging=nil; if(dir) [NSFileManager.defaultManager removeItemAtURL:dir error:NULL]; }
- (void)confirm {
    if(self.busy) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"导出未加密插件备份？" message:@"包含所有账号的私密数据；请选可信位置并保管副本。不会自动上传；如选云盘，后续同步由该服务决定。请停止插件数据写入后继续。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [self prepare]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)prepare {
    if(self.busy) return; self.busy=YES; self.button.enabled=NO; self.status.text=@"正在生成并逐文件校验，可能需要较长时间和额外空间……";
    NSDictionary *all=NSUserDefaults.standardUserDefaults.dictionaryRepresentation; NSMutableDictionary *owned=[NSMutableDictionary dictionary];
    for(NSString *key in all) if([key hasPrefix:@"WU.stats.sections."]) owned[key]=all[key];
    NSData *preferences=[NSPropertyListSerialization dataWithPropertyList:owned format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    NSURL *support=WUStorageEnvelope();
    NSURL *dir=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[@"WUBackup-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        BOOL ok=NO; NSURL *file=[dir URLByAppendingPathComponent:@"WeChatUnified-backup.tar"];
        BOOL created=support && preferences && mkdir(dir.fileSystemRepresentation,0700)==0;
        if(created && [NSFileManager.defaultManager setAttributes:@{NSFileProtectionKey:NSFileProtectionComplete} ofItemAtPath:dir.path error:NULL]) {
            int root=open(support.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
            int out=open(file.fileSystemRepresentation,O_CREAT|O_EXCL|O_RDWR|O_NOFOLLOW,0600);
            if(root>=0 && out>=0) ok=wu_backup_tar(root,out,preferences.bytes,preferences.length);
            if(root>=0) close(root); if(out>=0 && close(out)!=0) ok=NO;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if(created) self.staging=dir;
            if(!ok || !self.viewIfLoaded.window) { [self clean]; self.busy=NO; self.button.enabled=YES; self.status.text=@"备份未生成：可能是文件变化、不可读、符号链接、路径限制或空间不足；原数据未更改。"; return; }
            self.status.text=@"已校验临时副本，请在系统文件选择器选择位置；取消不会保存。";
            UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForExportingURLs:@[file] asCopy:YES]; picker.delegate=self;
            [self presentViewController:picker animated:YES completion:nil];
        });
    });
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { [self clean]; self.busy=NO; self.button.enabled=YES; self.status.text=@"已取消，未确认保存。"; }
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self clean]; self.busy=NO; self.button.enabled=YES;
    self.status.text=urls.count?@"系统文件选择器已确认保存副本；请在所选位置核验，云盘同步状态由服务决定。该备份未加密。":@"未确认保存，请检查所选位置。";
}
@end

void WUShowBackup(UIViewController *owner) { [owner.navigationController pushViewController:[WUBackupController new] animated:YES]; }
