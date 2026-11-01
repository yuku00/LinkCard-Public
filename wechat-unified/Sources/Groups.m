#import "WU.h"
#import "GroupLogic.h"
NSDictionary *WUAccountOptions(NSString *account) {
    if(!account.length || ![account isEqual:WUCurrentAccount()]) return @{};
    id accounts=WUValue(@"accounts"); return accounts[account]?:@{};
}
BOOL WUSaveAccountOption(NSString *account, NSString *key, id value) {
    if(!NSThread.isMainThread || !account.length || ![account isEqual:WUCurrentAccount()] || ![@[@"emoji",@"toolbar",@"home"] containsObject:key]) return NO;
    NSMutableDictionary *accounts=[WUValue(@"accounts") mutableCopy]?:[NSMutableDictionary dictionary];
    NSMutableDictionary *options=[accounts[account] mutableCopy]?:[NSMutableDictionary dictionary]; options[key]=value; accounts[account]=options;
    return WUValidAccountOptions(accounts) && WUSave(@"accounts",accounts);
}
static NSDictionary *EmojiState(NSString *account) { return WUAccountOptions(account)[@"emoji"]?:WUEmptyEmojiGroups(); }
static id Object(id o, NSString *selector) {
    SEL s=NSSelectorFromString(selector); if(!o || !WUMatches(class_getInstanceMethod(object_getClass(o),s),"@",@[])) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(o,s);
}
static NSString *Identifier(id wrap) {
    for(id o in @[wrap?:NSNull.null,Object(wrap,@"m_emojiInfo")?:NSNull.null]) {
        for(NSString *field in @[@"md5",@"m_md5"]) {
            id v=Object(o,field); if([v isKindOfClass:NSString.class]) { NSString *s=[v lowercaseString]; if(WUValidMD5(s) || [s isEqual:@"custom_emoticon_pid"]) return s; }
        }
    }
    return nil;
}
static UIViewController *Owner(UIView *view) { for(UIResponder *r=view;r;r=r.nextResponder) if([r isKindOfClass:UIViewController.class]) return (id)r; return nil; }
static UICollectionView *Collection(UIView *v, NSUInteger depth) {
    if(!depth) return nil; if([v isKindOfClass:UICollectionView.class]) return (id)v;
    if(v.subviews.count>100) return nil;
    for(UIView *child in v.subviews) { UICollectionView *c=Collection(child,depth-1); if(c) return c; } return nil;
}
@interface WUEmojiPage : NSObject
@property(nonatomic,weak) UIView *view;
@property(nonatomic,weak) UICollectionView *collection;
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSArray<NSString *> *identifiers;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic) UIEdgeInsets savedInset;
@property(nonatomic) BOOL insetOwned;
@property(nonatomic) BOOL invalidated;
- (void)restore;
- (void)refresh;
@end
static NSHashTable<WUEmojiPage *> *pages;
static char pageKey;
static BOOL emojiReady;
static WUEmojiPage *Page(UIView *v) {
    WUEmojiPage *p=objc_getAssociatedObject(v,&pageKey);
    if(!p) { p=[WUEmojiPage new]; p.view=v; p.account=WUCurrentAccount(); objc_setAssociatedObject(v,&pageKey,p,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [pages addObject:p]; }
    return p;
}
static BOOL CurrentPage(WUEmojiPage *p) {
    NSString *account=WUCurrentAccount();
    if(!account.length || ![account isEqual:p.account]) { p.invalidated=YES; p.identifiers=nil; [p restore]; return NO; }
    return !p.invalidated;
}
static void ReloadPages(void) {
    for(WUEmojiPage *p in pages.allObjects) {
        if(!CurrentPage(p)) continue;
        [p refresh]; [p.collection reloadData]; [p.view setNeedsLayout];
    }
}
@implementation WUEmojiPage
- (void)restore {
    [self.button removeFromSuperview]; self.button=nil;
    if(self.insetOwned) {
        UIEdgeInsets expected=self.savedInset; expected.top+=40;
        if(UIEdgeInsetsEqualToEdgeInsets(self.collection.contentInset,expected)) self.collection.contentInset=self.savedInset;
        self.insetOwned=NO;
    }
}
- (void)refresh {
    if(!CurrentPage(self)) return;
    NSDictionary *state=EmojiState(self.account);
    if(!emojiReady || ![WUValue(@"enabled") boolValue] || ![state[@"enabled"] boolValue] || !self.identifiers.count || !self.view.window) { [self restore]; return; }
    UICollectionView *c=Collection(self.view,6); if(!c) { [self restore]; return; }
    if(self.collection!=c) { [self restore]; self.collection=c; }
    if(!self.insetOwned) { self.savedInset=c.contentInset; UIEdgeInsets inset=self.savedInset; inset.top+=40; c.contentInset=inset; self.insetOwned=YES; }
    if(!self.button) { self.button=[UIButton buttonWithType:UIButtonTypeSystem]; self.button.backgroundColor=UIColor.secondarySystemBackgroundColor; self.button.showsMenuAsPrimaryAction=YES; [self.view addSubview:self.button]; }
    self.button.frame=CGRectMake(0,0,self.view.bounds.size.width,40); self.button.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    NSMutableArray *actions=[NSMutableArray array];
    NSArray *groups=[@[@{@"id":@"__all__",@"name":@"全部"},@{@"id":@"__ungrouped__",@"name":@"未分组"}] arrayByAddingObjectsFromArray:state[@"groups"]];
    __weak WUEmojiPage *weak=self;
    NSString *account=self.account; NSUInteger gen=WUContextGeneration();
    NSString *title=@"单个表情分组";
    for(NSDictionary *group in groups) {
        NSString *gid=group[@"id"];
        UIAction *action=[UIAction actionWithTitle:group[@"name"] image:nil identifier:nil handler:^(UIAction *a){
            WUEmojiPage *p=weak;
            if(!p.view.window || !CurrentPage(p) || gen!=WUContextGeneration() || ![account isEqual:WUCurrentAccount()] || ![WUValue(@"enabled") boolValue]) return;
            NSMutableDictionary *next=[EmojiState(account) mutableCopy]; next[@"selected"]=gid;
            if(!WUSaveAccountOption(account,@"emoji",next)) { [p.button setTitle:@"保存失败，原分组保留" forState:UIControlStateNormal]; }
        }];
        if([gid isEqual:state[@"selected"]]) { action.state=UIMenuElementStateOn; title=[@"单个表情 · " stringByAppendingString:group[@"name"]]; }
        [actions addObject:action];
    }
    [actions addObject:[UIAction actionWithTitle:@"管理分组 / 移动表情" image:nil identifier:nil handler:^(UIAction *a){ WUEmojiPage *p=weak; if(p.view.window && CurrentPage(p) && gen==WUContextGeneration()) WUShowGroups(Owner(p.view)); }]];
    self.button.menu=[UIMenu menuWithTitle:@"仅添加的单个表情" children:actions]; [self.button setTitle:title forState:UIControlStateNormal];
}
@end
static IMP listOriginal, setListOriginal, sectionOriginal, layoutOriginal, reuseOriginal;
static id EmojiList(UIView *v, SEL s) {
    id original=((id(*)(id,SEL))listOriginal)(v,s);
    if(!NSThread.isMainThread || !emojiReady || ![original isKindOfClass:NSArray.class] || [original count]>2000) return original;
    @try {
        WUEmojiPage *p=Page(v); if(!CurrentPage(p)) return original;
        NSMutableArray *ids=[NSMutableArray array]; BOOL placeholder=NO;
        for(id wrap in original) { NSString *md5=Identifier(wrap); if(!md5) { p.identifiers=nil; [p restore]; return original; } [ids addObject:md5]; if([md5 isEqual:@"custom_emoticon_pid"]) placeholder=YES; }
        // Evidence-backed scope marker. Never apply to an entire downloaded pack or recent-use list.
        if(!placeholder) { p.identifiers=nil; [p restore]; return original; }
        p.identifiers=[ids copy];
        if(![WUValue(@"enabled") boolValue]) return original;
        NSArray *indexes=WUEmojiIndexes(ids,EmojiState(p.account)); if(!indexes) return original;
        NSMutableArray *out=[NSMutableArray array]; for(NSNumber *index in indexes) [out addObject:original[index.unsignedIntegerValue]];
        return [out copy];
    } @catch(NSException *e) { return original; }
}
static void ResetPage(UIView *v) {
    if(!NSThread.isMainThread) return;
    WUEmojiPage *p=Page(v); [p restore]; p.identifiers=nil; p.account=WUCurrentAccount(); p.invalidated=NO;
}
static void SetList(UIView *v,SEL s,id list) { ResetPage(v); ((void(*)(id,SEL,id))setListOriginal)(v,s,list); }
static void SetSection(UIView *v,SEL s,id section) { ResetPage(v); if(NSThread.isMainThread) Page(v).invalidated=YES; ((void(*)(id,SEL,id))sectionOriginal)(v,s,section); }
static void Layout(UIView *v,SEL s) { ((void(*)(id,SEL))layoutOriginal)(v,s); @try { WUEmojiPage *p=Page(v); (void)EmojiList(v,NSSelectorFromString(@"emoticonList")); [p refresh]; } @catch(NSException *e) {} }
static void Reuse(UIView *v,SEL s) { ResetPage(v); WUEmojiPage *p=Page(v); p.invalidated=YES; ((void(*)(id,SEL))reuseOriginal)(v,s); }

@interface WUGroupsController : UITableViewController
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSArray<NSString *> *identifiers;
@end
@implementation WUGroupsController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"账号分组与工具栏"; self.account=WUCurrentAccount();
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:WUChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:UIApplicationDidBecomeActiveNotification object:nil]; [self refresh];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (BOOL)current { return self.account.length && [self.account isEqual:WUCurrentAccount()]; }
- (void)refresh {
    NSMutableOrderedSet *ids=[NSMutableOrderedSet orderedSet];
    if([self current]) for(WUEmojiPage *p in pages.allObjects) if(CurrentPage(p) && [p.account isEqual:self.account]) for(NSString *md5 in p.identifiers) if(WUValidMD5(md5)) [ids addObject:md5];
    self.identifiers=ids.array; [self.tableView reloadData];
}
- (void)notice:(NSString *)text {
    if(self.presentedViewController) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"微信整合" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)save:(NSDictionary *)state {
    if(![self current] || !WUSaveAccountOption(self.account,@"emoji",state)) { [self notice:@"未保存：账号变化、数据超限或写盘失败。原分组保留。请关闭后重新打开。 "]; return NO; } return YES;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 4; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if(![self current]) return 0;
    return s==3?1:(s==0?4+[EmojiState(self.account)[@"groups"] count]:(s==1?self.identifiers.count:7));
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return @[@"官方添加的单个表情",@"已打开面板中的表情（点按移动）",@"聊天工具栏 · 手动选择动作",@"首页会话分组"][s]; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if(![self current]) return @"账号不可核验或已经切换，请关闭后重新打开；不会使用上个账号的配置。";
    if(s==0) return emojiReady?@"分组按账号保存；左滑删除分组仅移除映射，不删媒体。先打开添加的单个表情面板。只有识别到添加占位且全部MD5可核验时才筛选；整包、最近使用保持原样。":@"此宿主缺少官方表情列表或生命周期签名，当前不可启用。";
    if(s==1) return @"仅当前账号宿主列表的MD5，不复制媒体、不读取聊天数据库。没有可核验列表时不提供手工假数据入口。";
    if(s==3) return @"全部、私信、群聊、其他及自定义组；宿主签名与原会话快照通过后才筛选。";
    return @"默认不选任何动作；聊天页头工具按钮仅列出所选且可用动作。无AI、自动回复或Dock入口；仓库必须手动打开并确认目标才发送。";
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0;
    if(p.section==3) { cell.textLabel.text=@"首页电报分组"; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell; }
    NSDictionary *state=EmojiState(self.account);
    if(p.section==0) {
        if(p.row==0) { cell.textLabel.text=@"启用单个表情分组"; UISwitch *sw=[UISwitch new]; sw.on=[state[@"enabled"] boolValue]; sw.enabled=emojiReady; [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=sw; }
        else if(p.row==1) cell.textLabel.text=@"＋ 创建分组";
        else { NSDictionary *g=p.row==2?@{@"id":@"__all__",@"name":@"全部"}:(p.row==3?@{@"id":@"__ungrouped__",@"name":@"未分组"}:state[@"groups"][p.row-4]); cell.textLabel.text=g[@"name"]; if([g[@"id"] isEqual:state[@"selected"]]) cell.accessoryType=UITableViewCellAccessoryCheckmark; }
    } else if(p.section==1) {
        NSString *md5=self.identifiers[p.row]; cell.textLabel.text=md5; NSString *gid=state[@"membership"][md5]; cell.detailTextLabel.text=@"未分组";
        for(NSDictionary *g in state[@"groups"]) if([gid isEqual:g[@"id"]]) cell.detailTextLabel.text=g[@"name"];
    } else { NSString *key=@[@"search",@"stats",@"settings",@"moments",@"repository",@"emojiSave",@"voiceForward"][p.row]; cell.textLabel.text=@[@"当前会话搜索",@"当前会话统计",@"整合设置",@"半屏朋友圈（需启用）",@"消息仓库（手动管理/发送）",@"所选原表情保存图库（先在聊天多选一个）",@"所选普通语音转发（单条、确认收件人）"][p.row]; if([WUToolbarActions(WUAccountOptions(self.account)[@"toolbar"]) containsObject:key]) cell.accessoryType=UITableViewCellAccessoryCheckmark; }
    return cell;
}
- (void)toggle:(UISwitch *)sw { NSMutableDictionary *s=[EmojiState(self.account) mutableCopy]; s[@"enabled"]=@(sw.on); if(![self save:s]) sw.on=!sw.on; }
- (void)create {
    if(![self current] || self.presentedViewController) return;
    NSUInteger gen=WUContextGeneration();
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"创建表情分组" message:@"名称1–40字符；最多32组。不会复制或删除表情。" preferredStyle:UIAlertControllerStyleAlert]; [a addTextFieldWithConfigurationHandler:nil];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak WUGroupsController *weak=self; __weak UIAlertController *input=a;
    [a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        WUGroupsController *v=weak; if(!v.viewIfLoaded.window || ![v current] || gen!=WUContextGeneration() || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
        NSString *name=[input.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(!name.length || name.length>40) return;
        NSMutableDictionary *s=[EmojiState(v.account) mutableCopy]; NSMutableArray *groups=[s[@"groups"] mutableCopy]; [groups addObject:@{@"id":NSUUID.UUID.UUIDString,@"name":name}]; s[@"groups"]=groups;
        [v save:s];
    }]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; if(![self current]) return;
    if(p.section==3) { WUShowHomeGroups(self); return; }
    if(p.section==2) {
        NSString *key=@[@"search",@"stats",@"settings",@"moments",@"repository",@"emojiSave",@"voiceForward"][p.row]; NSMutableArray *actions=[WUToolbarActions(WUAccountOptions(self.account)[@"toolbar"]) mutableCopy];
        if([actions containsObject:key]) [actions removeObject:key]; else [actions addObject:key];
        if(!WUSaveAccountOption(self.account,@"toolbar",actions)) [self notice:@"保存失败，原选择保留。"]; return;
    }
    NSDictionary *s=EmojiState(self.account);
    if(p.section==0) {
        if(p.row==0) return; if(p.row==1) { [self create]; return; }
        NSMutableDictionary *next=[s mutableCopy]; next[@"selected"]=p.row==2?@"__all__":(p.row==3?@"__ungrouped__":s[@"groups"][p.row-4][@"id"]); [self save:next]; return;
    }
    if(p.row<0 || (NSUInteger)p.row>=self.identifiers.count || self.presentedViewController) return;
    NSString *md5=self.identifiers[p.row]; NSUInteger gen=WUContextGeneration();
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"移动表情分组" message:md5 preferredStyle:UIAlertControllerStyleAlert];
    __weak WUGroupsController *weak=self;
    for(NSDictionary *group in [@[@{@"id":@"__ungrouped__",@"name":@"未分组"}] arrayByAddingObjectsFromArray:s[@"groups"]]) {
        [a addAction:[UIAlertAction actionWithTitle:group[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            WUGroupsController *v=weak; if(!v.viewIfLoaded.window || ![v current] || gen!=WUContextGeneration() || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || ![v.identifiers containsObject:md5]) return;
            NSMutableDictionary *next=[EmojiState(v.account) mutableCopy], *membership=[next[@"membership"] mutableCopy];
            if([group[@"id"] isEqual:@"__ungrouped__"]) [membership removeObjectForKey:md5]; else membership[md5]=group[@"id"];
            next[@"membership"]=membership; [v save:next];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)p { return [self current] && p.section==0 && p.row>=4; }
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)p {
    if(style!=UITableViewCellEditingStyleDelete || ![self current] || p.section!=0 || p.row<4) return;
    NSDictionary *s=EmojiState(self.account); if((NSUInteger)(p.row-4)>=[s[@"groups"] count]) return;
    [self save:WURemoveEmojiGroup(s,s[@"groups"][p.row-4][@"id"])];
}
@end
void WUShowGroups(UIViewController *owner) {
    if(!owner.viewIfLoaded.window || owner.presentedViewController) return;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:[[WUGroupsController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; [owner presentViewController:nav animated:YES completion:nil];
}
void WUInstallGroups(void) {
    static dispatch_once_t once; dispatch_once(&once,^{
        pages=[NSHashTable weakObjectsHashTable];
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ ReloadPages(); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ for(WUEmojiPage *p in pages.allObjects) [p restore]; }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ ReloadPages(); }];
    });
    Class cls=NSClassFromString(@"EmoticonBoardCrossCollectionEmoticonPageCell");
    if(!cls || ![cls isSubclassOfClass:UIView.class]) return;
    // Check the entire narrow lifecycle contract before installing any part of it.
    for(NSString *name in @[@"emoticonList",@"setEmoticonList:",@"setSectionInfo:",@"layoutSubviews",@"prepareForReuse"]) {
        BOOL setter=[name hasSuffix:@":"]; if(!WUMatches(class_getInstanceMethod(cls,NSSelectorFromString(name)),[name isEqual:@"emoticonList"]?"@":"v",setter?@[@"@"]:@[])) return;
    }
    BOOL ok=WUHook(@"EmoticonBoardCrossCollectionEmoticonPageCell",@"emoticonList",NO,"@",@[],(IMP)EmojiList,&listOriginal);
    ok=WUHook(@"EmoticonBoardCrossCollectionEmoticonPageCell",@"setEmoticonList:",NO,"v",@[@"@"],(IMP)SetList,&setListOriginal)&&ok;
    ok=WUHook(@"EmoticonBoardCrossCollectionEmoticonPageCell",@"setSectionInfo:",NO,"v",@[@"@"],(IMP)SetSection,&sectionOriginal)&&ok;
    ok=WUHook(@"EmoticonBoardCrossCollectionEmoticonPageCell",@"layoutSubviews",NO,"v",@[],(IMP)Layout,&layoutOriginal)&&ok;
    ok=WUHook(@"EmoticonBoardCrossCollectionEmoticonPageCell",@"prepareForReuse",NO,"v",@[],(IMP)Reuse,&reuseOriginal)&&ok; emojiReady=ok;
}
