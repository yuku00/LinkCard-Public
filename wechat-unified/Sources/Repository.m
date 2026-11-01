#import "Repository.h"
@implementation WURepositoryBinding
@end
@interface WURepositoryController : UITableViewController
@property(nonatomic,strong) WURepositoryBinding *binding;
@property(nonatomic,strong) NSArray *items;
@property(nonatomic,strong) NSMutableOrderedSet *selected;
@property(nonatomic,strong) NSMutableDictionary *results;
@property(nonatomic,strong) NSMutableSet *submitted;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) NSURL *directory;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL invalid;
@property(nonatomic) BOOL loaded;
@end
@implementation WURepositoryController
- (BOOL)current { return !self.invalid && self.binding.current && self.binding.current(); }
- (void)notice:(NSString *)text {
    if(self.presentedViewController || !self.viewIfLoaded.window) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"消息仓库" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"账号消息仓库";
    self.selected=[NSMutableOrderedSet orderedSet]; self.results=[NSMutableDictionary dictionary]; self.submitted=[NSMutableSet set];
    self.directory=[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"WeChatUnified/Repository" isDirectory:YES];
    NSError *error=nil; self.items=WURepositoryLoad(self.directory,self.binding.account,&error); self.loaded=self.items!=nil;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"发送所选" style:UIBarButtonItemStylePlain target:self action:@selector(confirmSend)];
    self.toolbarItems=@[[[UIBarButtonItem alloc] initWithTitle:@"新建文本" style:UIBarButtonItemStylePlain target:self action:@selector(newText)],[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL],[[UIBarButtonItem alloc] initWithTitle:@"助手所选入库" style:UIBarButtonItemStylePlain target:self action:@selector(capture)]];
    self.navigationController.toolbarHidden=NO;
    __weak WURepositoryController *weak=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer){
        WURepositoryController *s=weak; if(!s) { [timer invalidate]; return; }
        if(![s current]) { s.invalid=YES; [timer invalidate]; [s.selected removeAllObjects]; s.items=@[]; [s.tableView reloadData]; [s.navigationController dismissViewControllerAnimated:NO completion:nil]; }
    }];
    if(error) dispatch_async(dispatch_get_main_queue(),^{ [weak notice:error.localizedDescription]; });
}
- (void)dealloc { [_timer invalidate]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; if(!self.navigationController.presentingViewController) { self.invalid=YES; [self.timer invalidate]; } }
- (void)close { self.invalid=YES; [self.timer invalidate]; [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }
- (BOOL)save:(NSArray *)items {
    if(!self.loaded || self.busy || ![self current]) return NO;
    NSError *e=nil; if(!WURepositorySave(self.directory,self.binding.account,items,&e)) { [self notice:e.localizedDescription?:@"保存失败，原仓库保留"]; return NO; }
    self.items=[items copy]; [self.tableView reloadData]; return YES;
}
- (void)addParts:(NSArray *)parts name:(NSString *)name {
    if(![self current] || self.busy) return;
    NSMutableArray *next=[self.items mutableCopy]; [next addObject:@{@"id":NSUUID.UUID.UUIDString,@"name":name?:@"",@"parts":parts?:@[]}]; [self save:next];
}
- (void)newText {
    if(![self current] || self.busy || !self.loaded || self.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"新建独立纯文本" message:@"备注1–80字，正文1–10000字；不引用原消息。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"备注"; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"纯文本正文"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __block BOOL used=NO; [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ if(used) return; used=YES; NSString *name=a.textFields[0].text, *text=a.textFields[1].text; [self dismissViewControllerAnimated:YES completion:^{ [self addParts:@[@{@"kind":@"text",@"text":text?:@""}] name:name]; }]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)capture {
    if(![self current] || self.busy || !self.loaded || self.presentedViewController) return;
    NSArray *parts=self.binding.capture?self.binding.capture():nil;
    if(!parts.count) { [self notice:@"请先在文件传输助手进入宿主多选并选择1–50条，再打开此工具。源消息/接口不能核验时不入库。不会自动打开、选择或删除原聊天。"]; return; }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"原消息引用入库" message:@"只保存消息身份引用，不是独立媒体备份。原消息删除/媒体清理后可能无法发送；不会用文本或路径假恢复。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"备注（1–80字）"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __block BOOL used=NO; [a addAction:[UIAlertAction actionWithTitle:@"保存引用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ if(used) return; used=YES; NSString *name=a.textFields.firstObject.text; [self dismissViewControllerAnimated:YES completion:^{ [self addParts:parts name:name]; }]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section { return [self current]?self.items.count:0; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)section { return @"点选条目组合发送（按点选顺序）；左滑改备注/删除。删除只移除自有条目。纯文本独立保存；原消息引用必须仍在助手中且身份一致。所有状态仅描述本地请求，不表示送达。"; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    NSDictionary *item=self.items[p.row]; UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.textLabel.text=item[@"name"]; c.detailTextLabel.numberOfLines=0; c.detailTextLabel.text=self.results[item[@"id"]]?:[NSString stringWithFormat:@"%lu项 · %@",(unsigned long)[item[@"parts"] count],[item[@"parts"][0][@"kind"] isEqual:@"text"]?@"独立文本":@"原消息引用，非备份"];
    c.accessoryType=[self.selected containsObject:item[@"id"]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone; return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; if(self.busy || ![self current]) return;
    NSString *key=self.items[p.row][@"id"]; if([self.submitted containsObject:key]) { [self notice:@"本次打开已经处理此条目，不重复发送。请先核对宿主；如确需再次发送，请关闭后重新打开并再次确认。"]; return; }
    if([self.selected containsObject:key]) [self.selected removeObject:key]; else [self.selected addObject:key]; [t reloadData];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)p {
    if(self.busy || ![self current]) return nil; NSDictionary *item=self.items[p.row];
    UIContextualAction *remove=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除条目" handler:^(UIContextualAction *a, UIView *v, void(^done)(BOOL)){
        NSMutableArray *next=[self.items mutableCopy]; [next removeObject:item]; BOOL saved=[self save:next]; if(saved) [self.selected removeObject:item[@"id"]]; done(saved);
    }];
    UIContextualAction *rename=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"备注" handler:^(UIContextualAction *action, UIView *v, void(^done)(BOOL)){
        done(NO); if(![self current] || self.busy || self.presentedViewController) return;
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"修改备注" message:@"只改仓库备注，不改原消息" preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text=item[@"name"]; }];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *b){ NSString *name=a.textFields.firstObject.text;
            [self dismissViewControllerAnimated:YES completion:^{ NSMutableArray *next=[self.items mutableCopy]; NSUInteger index=[next indexOfObject:item]; if(index==NSNotFound) return; NSMutableDictionary *copy=[item mutableCopy]; copy[@"name"]=name?:@""; next[index]=copy; [self save:next]; }];
        }]]; [self presentViewController:a animated:YES completion:nil];
    }];
    UISwipeActionsConfiguration *c=[UISwipeActionsConfiguration configurationWithActions:@[remove,rename]]; c.performsFirstActionWithFullSwipe=NO; return c;
}
- (void)step:(NSArray *)work index:(NSUInteger)index {
    if(index>=work.count) { self.busy=NO; self.navigationItem.rightBarButtonItem.enabled=YES; [self.selected removeAllObjects]; [self.tableView reloadData]; if([self current]) [self notice:@"本批处理结束。请查看逐项已请求/失败/未知；没有送达回执，未自动重发。未知项必须先在宿主核对。"]; return; }
    NSDictionary *job=work[index]; NSString *status;
    if(![self current]) status=@"失败：上下文变化，未提交";
    else { @try { status=self.binding.send(job[@"part"]); } @catch(NSException *e) { status=@"未知：请在宿主核对，未重试"; } }
    NSString *line=[NSString stringWithFormat:@"%@: %@",job[@"number"],status?:@"失败：未提交"];
    NSString *old=self.results[job[@"id"]]; self.results[job[@"id"]]=old.length?[old stringByAppendingFormat:@"\n%@",line]:line;
    [self.tableView reloadData];
    // Yield for account/background cancellation, not an invented delivery delay.
    dispatch_async(dispatch_get_main_queue(),^{ [self step:work index:index+1]; });
}
- (void)confirmSend {
    if(![self current] || self.busy || !self.selected.count || self.presentedViewController) return;
    NSMutableArray *work=[NSMutableArray array];
    for(NSString *key in self.selected) for(NSDictionary *item in self.items) if([item[@"id"] isEqual:key] && ![self.submitted containsObject:key]) {
        NSUInteger n=0; for(NSDictionary *part in item[@"parts"]) [work addObject:@{@"id":key,@"part":part,@"number":@(++n)}];
    }
    if(!work.count || work.count>50) { [self notice:@"单批只允许1–50项，请减少所选条目。"]; return; }
    self.busy=YES;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认目标后请求发送" message:[NSString stringWithFormat:@"账号：%@\n目标用户名：%@\n共%lu项，按所选顺序逐项请求。\n前项已请求不会因后项失败撤销；不保证送达。不自动重试或回退。",self.binding.account,self.binding.target,(unsigned long)work.count] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){ self.busy=NO; }]];
    __block BOOL consumed=NO;
    [a addAction:[UIAlertAction actionWithTitle:@"确认请求" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        if(consumed) return; consumed=YES;
        [self dismissViewControllerAnimated:YES completion:^{
            if(![self current]) { self.busy=NO; return; }
            for(NSDictionary *job in work) [self.submitted addObject:job[@"id"]];
            self.navigationItem.rightBarButtonItem.enabled=NO; [self step:[work copy] index:0];
        }];
    }]]; [self presentViewController:a animated:YES completion:nil];
}
@end
void WUShowRepository(UIViewController *owner, WURepositoryBinding *binding) {
    if(!NSThread.isMainThread || owner.presentedViewController || !owner.viewIfLoaded.window || !binding.current || !binding.current()) return;
    WURepositoryController *v=[[WURepositoryController alloc] initWithStyle:UITableViewStyleInsetGrouped]; v.binding=binding;
    UINavigationController *n=[[UINavigationController alloc] initWithRootViewController:v]; n.modalInPresentation=YES;
    [owner presentViewController:n animated:YES completion:nil];
}
