#import "WU.h"
#import "DraftsLogic.h"
#import "DraftMediaLogic.h"
static NSURL *MediaDirectory(void) { return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"WeChatUnified/MomentsMediaDrafts" isDirectory:YES]; }
static NSString *Body(NSDictionary *row) { return row[@"kind"]?row[@"text"]:row[@"parts"][0][@"text"]; }
// Only observed selectors; unknown selection objects are never archived or fabricated.
static NSDictionary *Capture(id editor, NSString **failure) {
    id selector=WUDraftsObject(editor,@"imageSelectorController");
    id sight=WUDraftsObject(selector,@"sightDraft")?:WUDraftsObject(editor,@"sightDraft");
    if(sight) {
        id path=WUDraftsObject(sight,@"draftItemVideoPath");
        if(![path isKindOfClass:NSString.class] || ![path isAbsolutePath]) {
            id items=WUDraftsObject(sight,@"itemAry"); id item=[items isKindOfClass:NSArray.class] && [items count]?items[0]:nil;
            path=WUDraftsObject(item,@"getVideoPath")?:WUDraftsObject(item,@"videoDraftPath");
        }
        if(![path isKindOfClass:NSString.class] || ![path isAbsolutePath]) { *failure=@"视频路径协议不可用，未保存；不会降级丢掉视频"; return nil; }
        return @{@"kind":@"video-backup",@"sources":@[[NSURL fileURLWithPath:path]]};
    }
    id images=WUDraftsObject(selector,@"arrImages");
    if(![images isKindOfClass:NSArray.class] || ![images count] || [images count]>9) { *failure=@"未取得1–9张真实选择图片；媒体保存拒绝，不自动改为文字"; return nil; }
    NSMutableArray *sources=[NSMutableArray array];
    for(id value in images) {
        if(![value isKindOfClass:UIImage.class]) { *failure=@"选择项不是UIImage；宿主图片包装对象的解包/重建协议尚缺，未保存"; return nil; }
        UIImage *image=value;
        if(!image.CGImage || image.images.count || image.imageOrientation!=UIImageOrientationUp || (uint64_t)CGImageGetWidth(image.CGImage)*CGImageGetHeight(image.CGImage)>16000000) { *failure=@"暂不支持动画、旋转或超过1600万像素的图片；未保存"; return nil; }
        NSData *data=UIImagePNGRepresentation(image); if(!data.length || data.length>20*1024*1024) { *failure=@"图片编码失败或超过20MiB；未保存"; return nil; } [sources addObject:data];
    }
    return @{@"kind":@"images",@"sources":sources};
}
static NSURL *Directory(void) { return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"WeChatUnified/MomentsTextDrafts" isDirectory:YES]; }
static BOOL Active(NSString *a, NSUInteger g) { return NSThread.isMainThread && a.length && [a isEqual:WUCurrentAccount()] && g==WUContextGeneration() && WUEnabled(@"convenientMoments") && UIApplication.sharedApplication.applicationState==UIApplicationStateActive; }
static void Notice(UIViewController *v, NSString *message) {
    if(v.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"朋友圈草稿" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [v presentViewController:a animated:YES completion:nil];
}
static char draftIDKey, draftMediaKey;
@interface WUDraftsList : UITableViewController
@property(nonatomic,copy) NSString *account;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,copy) NSArray *rows;
@property(nonatomic) BOOL healthy;
@property(nonatomic) BOOL restoring;
@end
@implementation WUDraftsList
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"草稿与媒体备份 · 本账号";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"新建" style:UIBarButtonItemStylePlain target:self action:@selector(create)];
    UILabel *footer=[[UILabel alloc] initWithFrame:CGRectMake(0,0,300,100)]; footer.numberOfLines=0; footer.textAlignment=NSTextAlignmentCenter; footer.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    footer.text=@"图片仅支持真实UIImage静态正向像素；视频可用独立副本重建宿主编辑器，原剪辑轨道不恢复。\n位置/可见范围/原图元数据不保存，必须重新核对。\n删除只移除索引；资源保留保护编辑中引用，每账号上限512MiB。"; self.tableView.tableFooterView=footer;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadDrafts]; }
- (void)reloadDrafts {
    if(!Active(self.account,self.generation)) { self.rows=@[]; self.healthy=NO; [self.tableView reloadData]; return; }
    NSError *e=nil; NSArray *text=WUDraftsLoad(Directory(),self.account,&e); NSArray *media=WUDraftMediaLoad(MediaDirectory(),self.account,&e);
    self.healthy=text!=nil && media!=nil; self.rows=self.healthy?[media arrayByAddingObjectsFromArray:text]:@[];
    self.navigationItem.rightBarButtonItem.enabled=self.healthy; [self.tableView reloadData];
    if(!self.healthy) dispatch_async(dispatch_get_main_queue(),^{ if(Active(self.account,self.generation) && self.view.window) Notice(self,e.localizedDescription?:@"加载失败，原文件未覆盖"); });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; NSDictionary *row=self.rows[path.row];
    cell.textLabel.text=[row[@"kind"] isEqual:@"video-backup"] && [row[@"name"] isEqual:@"视频备份（不可恢复）"]?@"视频草稿":row[@"name"]; cell.textLabel.numberOfLines=2; cell.detailTextLabel.text=[row[@"kind"] isEqual:@"video-backup"]?@"视频草稿 · 从保存视频重建编辑":([row[@"kind"] isEqual:@"images"]?@"图片草稿 · 不含位置/可见范围":@"文字草稿 · 不含媒体/发布设置"); cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)openRow:(NSDictionary *)row { [self openRow:row videoURL:nil]; }
- (void)openRow:(NSDictionary *)row videoURL:(NSURL *)videoURL {
    if(self.restoring || !self.healthy || !Active(self.account,self.generation) || self.navigationController.topViewController!=self) return;
    Class cls=NSClassFromString(@"WCNewCommitViewController");
    BOOL video=[row[@"kind"] isEqual:@"video-backup"];
    if(![cls isSubclassOfClass:UIViewController.class] || (video?!WUDraftsVideoEditorAvailable(cls,NSClassFromString(@"SightDraft")):!WUDraftsEditorAvailable(cls))) { Notice(self,@"宿主编辑器/视频工厂签名不匹配，草稿保留"); return; }
    @try {
        NSArray *images=nil;
        if(video && !videoURL) {
            self.restoring=YES; self.navigationItem.rightBarButtonItem.enabled=NO;
            NSString *account=[self.account copy]; NSUInteger generation=self.generation;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
                NSError *error=nil; NSURL *copy=WUDraftMediaVideoEditingCopy(MediaDirectory(),account,row,^BOOL{ return generation==WUContextGenerationSnapshot(); },&error);
                dispatch_async(dispatch_get_main_queue(),^{
                    self.restoring=NO; self.navigationItem.rightBarButtonItem.enabled=self.healthy;
                    if(!Active(account,generation) || self.navigationController.topViewController!=self) return;
                    if(!copy) { Notice(self,error.localizedDescription?:@"视频恢复副本创建失败，原稿保留"); return; }
                    [self openRow:row videoURL:copy];
                });
            }); return;
        }
        if([row[@"kind"] isEqual:@"images"]) {
            NSError *e=nil; NSArray *urls=WUDraftMediaURLs(MediaDirectory(),self.account,row,&e); if(!urls) { Notice(self,e.localizedDescription); return; }
            NSMutableArray *decoded=[NSMutableArray array]; for(NSURL *url in urls) { UIImage *image=[UIImage imageWithContentsOfFile:url.path]; if(!image) { Notice(self,@"自有图片解码失败，未恢复"); return; } [decoded addObject:image]; } images=decoded;
        }
        id expectedSight=nil;
        UIViewController *editor=video?WUDraftsCreateVideoEditor(cls,NSClassFromString(@"SightDraft"),videoURL,^BOOL{ return Active(self.account,self.generation) && self.navigationController.topViewController==self; },&expectedSight):(images?WUDraftsCreateImageEditor(cls,images):WUDraftsCreateEditor(cls));
        if(![editor isKindOfClass:cls]) { Notice(self,@"宿主初始化失败，草稿保留"); return; }
        [editor loadViewIfNeeded];
        if(video) {
            id selection=WUDraftsObject(WUDraftsObject(editor,@"imageSelectorController"),@"sightDraft")?:WUDraftsObject(editor,@"sightDraft");
            if(!expectedSight || selection!=expectedSight) { Notice(self,@"宿主未确认重建的视频选择，未进入编辑；原稿保留"); return; }
        }
        if(images) {
            id selection=WUDraftsObject(WUDraftsObject(editor,@"imageSelectorController"),@"arrImages");
            if(![selection isKindOfClass:NSArray.class] || ![selection isEqualToArray:images]) { Notice(self,@"宿主未确认图片选择数组，未进入编辑；草稿保留"); return; }
        }
        id text=WUDraftsTextView(editor);
        if(![text isKindOfClass:UITextView.class] || ![(UITextView *)text isDescendantOfView:editor.view]) { Notice(self,@"宿主正文控件不匹配，未进入恢复编辑"); return; }
        UITextView *view=text; NSString *body=row?Body(row):@"";
        view.text=body;
        if([view.delegate respondsToSelector:@selector(textViewDidChange:)]) [view.delegate textViewDidChange:view];
        [NSNotificationCenter.defaultCenter postNotificationName:UITextViewTextDidChangeNotification object:view];
        if(![view.text isEqual:body] || !Active(self.account,self.generation)) { Notice(self,@"回填未确认，原草稿保留"); return; }
        objc_setAssociatedObject(editor,&draftIDKey,row[@"id"]?:NSUUID.UUID.UUIDString,OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(editor,&draftMediaKey,@(images!=nil || video),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self.navigationController pushViewController:editor animated:YES];
    } @catch(NSException *e) { Notice(self,@"恢复异常，原草稿未修改"); }
}
- (void)create { [self openRow:nil]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if(!Active(self.account,self.generation)) return;
    NSDictionary *row=self.rows[path.row]; UIAlertController *a=[UIAlertController alertControllerWithTitle:@"预览正文（不含媒体/发布设置）" message:[row[@"kind"] isEqual:@"video-backup"]?[(Body(row)?:@"") stringByAppendingString:@"\n\n使用保存的视频文件重建新编辑草稿；封面/时长由宿主从文件读取。原剪辑轨道、封面选择、位置/可见范围不恢复，发布前必须核对。"]:Body(row) preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"恢复到微信编辑器" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [self openRow:row]; }]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if(style!=UITableViewCellEditingStyleDelete || !Active(self.account,self.generation)) return;
    NSDictionary *selected=self.rows[path.row]; NSString *uuid=selected[@"id"]; UIAlertController *a=[UIAlertController alertControllerWithTitle:@"删除这条自有草稿索引？" message:@"媒体文件继续保留（保护共享/编辑中资源）；不删除宿主原文件。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        if(!Active(self.account,self.generation)) return; NSError *e=nil;
        BOOL ok=selected[@"kind"]?WUDraftMediaDelete(MediaDirectory(),self.account,uuid,&e):WUDraftsDelete(Directory(),self.account,uuid,&e); if(!ok) Notice(self,e.localizedDescription); [self reloadDrafts];
    }]]; [self presentViewController:a animated:YES completion:nil];
}
@end
void WUMomentsDraftsAction(UINavigationController *nav, NSString *account, NSUInteger generation) {
    if(!Active(account,generation) || nav.presentedViewController || nav.topViewController.presentedViewController) return;
    UIViewController *top=nav.topViewController; Class cls=NSClassFromString(@"WCNewCommitViewController");
    if(cls && [top isKindOfClass:cls]) {
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"选择保存内容" message:@"图片仅支持静态正向UIImage像素；视频独立保存后可重建编辑，原剪辑轨道不保存。位置、可见范围、联系人及原图元数据不保存。不退出、不取消、不发布。" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"保存图片 / 视频草稿" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            if(!Active(account,generation) || nav.topViewController!=top) return;
            @try {
                id view=WUDraftsTextView(top); if(![view isKindOfClass:UITextView.class] || ![(UITextView *)view isDescendantOfView:top.view]) { Notice(top,@"正文控件不匹配，未保存"); return; }
                NSString *failure=nil; NSDictionary *capture=Capture(top,&failure); if(!capture) { Notice(top,failure); return; }
                NSString *uuid=[objc_getAssociatedObject(top,&draftMediaKey) boolValue]?objc_getAssociatedObject(top,&draftIDKey):nil; uuid=uuid?:NSUUID.UUID.UUIDString;
                NSError *e=nil; if(!Active(account,generation) || nav.topViewController!=top) return;
                if(!WUDraftMediaPut(MediaDirectory(),account,uuid,[view text],capture[@"kind"],capture[@"sources"],&e)) { Notice(top,e.localizedDescription); return; }
                objc_setAssociatedObject(top,&draftIDKey,uuid,OBJC_ASSOCIATION_COPY_NONATOMIC); objc_setAssociatedObject(top,&draftMediaKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                Notice(top,[capture[@"kind"] isEqual:@"images"]?@"图片像素及正文已独立保存，可尝试恢复真实编辑器。位置/可见范围/原图元数据不保存；没有发布。":@"视频与正文已独立保存，可从草稿箱重建真实视频编辑器。封面/时长由宿主读取，原剪辑轨道及发布设置不恢复；没有发布。");
            } @catch(NSException *e) { Notice(top,@"媒体保存异常，未确认成功；原草稿与宿主文件保留"); }
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"保存文字" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            if(!Active(account,generation) || nav.topViewController!=top) return;
            if([objc_getAssociatedObject(top,&draftMediaKey) boolValue]) { Notice(top,@"当前关联媒体草稿，请选择保存媒体；不以文字覆盖媒体记录"); return; }
            @try {
                id view=WUDraftsTextView(top);
                if(![view isKindOfClass:UITextView.class] || ![(UITextView *)view isDescendantOfView:top.view]) { Notice(top,@"正文控件不匹配，未保存"); return; }
                NSString *text=[[(UITextView *)view text] copy]; NSString *uuid=objc_getAssociatedObject(top,&draftIDKey)?:NSUUID.UUID.UUIDString; NSError *e=nil;
                if(!Active(account,generation) || nav.topViewController!=top) return;
                if(!WUDraftsPut(Directory(),account,uuid,text,&e)) { Notice(top,e.localizedDescription); return; }
                objc_setAssociatedObject(top,&draftIDKey,uuid,OBJC_ASSOCIATION_COPY_NONATOMIC);
                Notice(top,@"正文已原子保存。原编辑器未退出；返回草稿箱即可预览或恢复。发布后不会自动删除草稿。");
            } @catch(NSException *e) { Notice(top,@"保存异常，原草稿保留"); }
        }]]; [top presentViewController:a animated:YES completion:nil]; return;
    }
    if([top isKindOfClass:WUDraftsList.class]) return;
    WUDraftsList *list=[[WUDraftsList alloc] initWithStyle:UITableViewStyleInsetGrouped]; list.account=account; list.generation=generation; [nav pushViewController:list animated:YES];
}
