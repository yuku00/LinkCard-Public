#import "WU.h"
#import "DraftsLogic.h"
static NSURL *Directory(void) { return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"WeChatUnified/MomentsTextDrafts" isDirectory:YES]; }
static BOOL Active(NSString *a, NSUInteger g) { return NSThread.isMainThread && a.length && [a isEqual:WUCurrentAccount()] && g==WUContextGeneration() && WUEnabled(@"convenientMoments") && UIApplication.sharedApplication.applicationState==UIApplicationStateActive; }
static void Notice(UIViewController *v, NSString *message) {
    if(v.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"朋友圈文字草稿" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [v presentViewController:a animated:YES completion:nil];
}
static char draftIDKey;
@interface WUDraftsList : UITableViewController
@property(nonatomic,copy) NSString *account;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,copy) NSArray *rows;
@property(nonatomic) BOOL healthy;
@end
@implementation WUDraftsList
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"文字草稿 · 仅本账号";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"新建" style:UIBarButtonItemStylePlain target:self action:@selector(create)];
    UILabel *footer=[[UILabel alloc] initWithFrame:CGRectMake(0,0,300,100)]; footer.numberOfLines=0; footer.textAlignment=NSTextAlignmentCenter; footer.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    footer.text=@"只保存正文，不保存图片、视频、位置或可见范围。\n恢复至微信真实发表编辑器，请重新核对发布设置。\n保存使用半屏顶部“草稿/存文字”；发布后不自动删除。"; self.tableView.tableFooterView=footer;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadDrafts]; }
- (void)reloadDrafts {
    if(!Active(self.account,self.generation)) { self.rows=@[]; self.healthy=NO; [self.tableView reloadData]; return; }
    NSError *e=nil; self.rows=WUDraftsLoad(Directory(),self.account,&e); self.healthy=self.rows!=nil;
    self.navigationItem.rightBarButtonItem.enabled=self.healthy; [self.tableView reloadData];
    if(!self.healthy) dispatch_async(dispatch_get_main_queue(),^{ if(Active(self.account,self.generation) && self.view.window) Notice(self,e.localizedDescription?:@"加载失败，原文件未覆盖"); });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; NSDictionary *row=self.rows[path.row];
    cell.textLabel.text=row[@"name"]; cell.textLabel.numberOfLines=2; cell.detailTextLabel.text=@"点按预览与恢复 · 左滑删除自有草稿"; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)openRow:(NSDictionary *)row {
    if(!self.healthy || !Active(self.account,self.generation) || self.navigationController.topViewController!=self) return;
    Class cls=NSClassFromString(@"WCNewCommitViewController");
    if(![cls isSubclassOfClass:UIViewController.class] || !WUDraftsEditorAvailable(cls)) { Notice(self,@"宿主文字编辑器签名不匹配，草稿保留"); return; }
    @try {
        UIViewController *editor=WUDraftsCreateEditor(cls);
        if(![editor isKindOfClass:cls]) { Notice(self,@"宿主初始化失败，草稿保留"); return; }
        [editor loadViewIfNeeded]; id text=WUDraftsTextView(editor);
        if(![text isKindOfClass:UITextView.class] || ![(UITextView *)text isDescendantOfView:editor.view]) { Notice(self,@"宿主正文控件不匹配，未进入恢复编辑"); return; }
        UITextView *view=text; NSString *body=row?row[@"parts"][0][@"text"]:@"";
        view.text=body;
        if([view.delegate respondsToSelector:@selector(textViewDidChange:)]) [view.delegate textViewDidChange:view];
        [NSNotificationCenter.defaultCenter postNotificationName:UITextViewTextDidChangeNotification object:view];
        if(![view.text isEqual:body] || !Active(self.account,self.generation)) { Notice(self,@"回填未确认，原草稿保留"); return; }
        objc_setAssociatedObject(editor,&draftIDKey,row[@"id"]?:NSUUID.UUID.UUIDString,OBJC_ASSOCIATION_COPY_NONATOMIC);
        [self.navigationController pushViewController:editor animated:YES];
    } @catch(NSException *e) { Notice(self,@"恢复异常，原草稿未修改"); }
}
- (void)create { [self openRow:nil]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if(!Active(self.account,self.generation)) return;
    NSDictionary *row=self.rows[path.row]; UIAlertController *a=[UIAlertController alertControllerWithTitle:@"预览正文（不含媒体/发布设置）" message:row[@"parts"][0][@"text"] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"恢复到微信编辑器" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [self openRow:row]; }]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if(style!=UITableViewCellEditingStyleDelete || !Active(self.account,self.generation)) return;
    NSString *uuid=self.rows[path.row][@"id"]; UIAlertController *a=[UIAlertController alertControllerWithTitle:@"删除这条自有文字草稿？" message:@"不删除朋友圈、聊天或任何媒体文件。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        if(!Active(self.account,self.generation)) return; NSError *e=nil;
        if(!WUDraftsDelete(Directory(),self.account,uuid,&e)) Notice(self,e.localizedDescription); [self reloadDrafts];
    }]]; [self presentViewController:a animated:YES completion:nil];
}
@end
void WUMomentsDraftsAction(UINavigationController *nav, NSString *account, NSUInteger generation) {
    if(!Active(account,generation) || nav.presentedViewController || nav.topViewController.presentedViewController) return;
    UIViewController *top=nav.topViewController; Class cls=NSClassFromString(@"WCNewCommitViewController");
    if(cls && [top isKindOfClass:cls]) {
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"仅保存当前正文？" message:@"图片、视频、位置、可见范围等不保存。不会退出、取消或发布原编辑器。" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"保存文字" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            if(!Active(account,generation) || nav.topViewController!=top) return;
            @try {
                id view=WUDraftsTextView(top);
                if(![view isKindOfClass:UITextView.class] || ![(UITextView *)view isDescendantOfView:top.view]) { Notice(top,@"正文控件不匹配，未保存"); return; }
                NSString *text=[[(UITextView *)view text] copy]; NSString *uuid=objc_getAssociatedObject(top,&draftIDKey)?:NSUUID.UUID.UUIDString; NSError *e=nil;
                if(!WUDraftsPut(Directory(),account,uuid,text,&e)) { Notice(top,e.localizedDescription); return; }
                objc_setAssociatedObject(top,&draftIDKey,uuid,OBJC_ASSOCIATION_COPY_NONATOMIC);
                Notice(top,@"正文已原子保存。原编辑器未退出；返回草稿箱即可预览或恢复。发布后不会自动删除草稿。");
            } @catch(NSException *e) { Notice(top,@"保存异常，原草稿保留"); }
        }]]; [top presentViewController:a animated:YES completion:nil]; return;
    }
    if([top isKindOfClass:WUDraftsList.class]) return;
    WUDraftsList *list=[[WUDraftsList alloc] initWithStyle:UITableViewStyleInsetGrouped]; list.account=account; list.generation=generation; [nav pushViewController:list animated:YES];
}
