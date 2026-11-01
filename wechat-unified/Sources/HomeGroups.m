#import "WU.h"
#import "HomeLogic.h"
static BOOL ready, applying;
static IMP setters[3], countSetter;
static NSArray<NSString *> *getNames, *setNames;
static NSHashTable *managers, *homePages;
static char managerKey, pageKey;
static id Obj(id o,NSString *name) { SEL s=NSSelectorFromString(name); if(!o || !WUMatches(class_getInstanceMethod(object_getClass(o),s),"@",@[])) return nil; return ((id(*)(id,SEL))objc_msgSend)(o,s); }
static id CurrentManager(void) {
    id center=Obj(NSClassFromString(@"MMServiceCenter"),@"defaultCenter"); Class cls=NSClassFromString(@"MainSessionMgr"); SEL sel=NSSelectorFromString(@"getService:"); Method method=class_getInstanceMethod(object_getClass(center),sel);
    if(!cls || (!WUMatches(method,"@",@[@"#"]) && !WUMatches(method,"@",@[@"@"]))) return nil;
    return ((id(*)(id,SEL,Class))objc_msgSend)(center,sel,cls);
}
static BOOL Flag(id o,NSString *name,BOOL *value) { SEL s=NSSelectorFromString(name); Method m=class_getInstanceMethod(object_getClass(o),s); if(WUMatches(m,"B",@[])) { *value=((BOOL(*)(id,SEL))objc_msgSend)(o,s); return YES; } if(WUMatches(m,"c",@[])) { *value=((signed char(*)(id,SEL))objc_msgSend)(o,s)!=0; return YES; } return NO; }
static NSDictionary *State(NSString *a) { return WUAccountOptions(a)[@"home"]?:WUEmptyHomeGroups(); }
static NSDictionary *Row(id session) {
    if(![session isKindOfClass:NSClassFromString(@"MMSessionInfo")]) return nil;
    NSString *u=nil; for(NSString *key in @[@"m_nsUserName",@"m_nsUsrName",@"userName",@"username"]) { id v=Obj(session,key); if([v isKindOfClass:NSString.class] && [v length]>0 && [v length]<=256) { u=v; break; } }
    if(!u) return nil;
    BOOL single=NO,box=NO,brand=NO;
    // These are native session predicates, not plugin helper selectors or display titles.
    BOOL singleKnown=Flag(session,@"isSingleChatSession",&single);
    (void)Flag(session,@"isChatBoxSession",&box);
    BOOL b=NO; if(Flag(session,@"isBrandSessionHolder",&b)) brand|=b;
    if(Flag(session,@"isBrandServiceBoxSession",&b)) brand|=b;
    id contact=Obj(session,@"m_contact"); if(contact && Flag(contact,@"isBrandContact",&b)) brand|=b;
    NSString *kind=WUHomeKind(u,box,brand,single);
    if([kind isEqual:@"other"] && !singleKnown && !brand && ![u.lowercaseString hasPrefix:@"gh_"] && ![@[@"brandsessionholder",@"brandservicesessionholder"] containsObject:u.lowercaseString]) return nil;
    return @{@"username":u,@"kind":kind};
}
@interface WUHomeSnapshot : NSObject
@property(nonatomic,weak) id manager;
@property(nonatomic,copy) NSString *account;
@property(nonatomic,strong) NSMutableArray *source;
@property(nonatomic,strong) NSArray *published;
@property(nonatomic) NSUInteger topCount;
@property(nonatomic) BOOL countKnown, filtered, invalid, queued;
- (BOOL)current;
- (void)apply;
- (void)schedule;
@end
static WUHomeSnapshot *Snapshot(id m) {
    WUHomeSnapshot *s=objc_getAssociatedObject(m,&managerKey);
    if(!s) {
        s=[WUHomeSnapshot new]; s.manager=m; s.account=WUCurrentAccount(); s.source=[NSMutableArray array];
        for(NSString *name in getNames) { id a=Obj(m,name); [s.source addObject:[a isKindOfClass:NSArray.class] && [a count]<=20000?[a copy]:NSNull.null]; }
        objc_setAssociatedObject(m,&managerKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [managers addObject:s];
    }
    return s;
}
static void Refresh(void);
@implementation WUHomeSnapshot
- (void)schedule {
    if(self.queued) return; self.queued=YES;
    NSString *account=[self.account copy]; NSUInteger gen=WUContextGeneration(); __weak WUHomeSnapshot *weak=self;
    dispatch_async(dispatch_get_main_queue(), ^{ WUHomeSnapshot *s=weak; s.queued=NO; if(!s || ![s current] || ![s.account isEqual:account] || gen!=WUContextGeneration()) return; Refresh(); });
}
- (BOOL)current { NSString *a=WUCurrentAccount(); return a.length && [a isEqual:self.account] && self.manager==CurrentManager(); }
- (void)apply {
    if(applying || !NSThread.isMainThread || ![self current] || self.invalid || !self.countKnown || [self.source containsObject:NSNull.null]) return;
    NSDictionary *state=State(self.account); BOOL active=ready && [WUValue(@"enabled") boolValue] && [state[@"enabled"] boolValue];
    NSMutableArray *output=[NSMutableArray array], *decoded=[NSMutableArray array]; NSDictionary *plan=nil;
    if(active) for(NSArray *array in self.source) {
        NSMutableArray *rows=[NSMutableArray array]; for(id native in array) { NSDictionary *r=Row(native); if(!r) { active=NO; break; } [rows addObject:r]; }
        if(!active) break; [decoded addObject:rows];
    }
    if(active) { plan=WUHomeProjection(self.source,decoded,state,self.topCount); active=plan!=nil; if(active) output=[plan[@"arrays"] mutableCopy]; }
    if(!active) output=[self.source mutableCopy];
    if(!active && !self.filtered) return;
    BOOL unchanged=self.filtered==active && self.published.count==3;
    for(NSUInteger i=0;unchanged && i<3;i++) unchanged=[Obj(self.manager,getNames[i]) isEqualToArray:output[i]];
    if(unchanged) return;
    // Preserve original session objects/order: host cells, unread and tap lookup use the same arrays.
    applying=YES;
    @try {
        for(NSUInteger i=0;i<3;i++) ((void(*)(id,SEL,id))setters[i])(self.manager,NSSelectorFromString(setNames[i]),[output[i] mutableCopy]);
        ((void(*)(id,SEL,NSUInteger))countSetter)(self.manager,NSSelectorFromString(@"setTotalTopSessionCount:"),active?[plan[@"topCount"] unsignedIntegerValue]:self.topCount);
        NSMutableArray *actual=[NSMutableArray array]; for(NSString *name in getNames) [actual addObject:Obj(self.manager,name)?:NSNull.null]; self.published=actual; self.filtered=active;
    } @catch(NSException *e) {
        self.invalid=YES;
        // Roll back all three slots, not just the setter that threw; never leave a mixed index space.
        for(NSUInteger i=0;i<3;i++) @try { ((void(*)(id,SEL,id))setters[i])(self.manager,NSSelectorFromString(setNames[i]),[self.source[i] mutableCopy]); } @catch(NSException *ignored) {}
        @try { ((void(*)(id,SEL,NSUInteger))countSetter)(self.manager,NSSelectorFromString(@"setTotalTopSessionCount:"),self.topCount); } @catch(NSException *ignored) {}
        self.filtered=NO; self.published=nil;
    } @finally { applying=NO; }
}
@end
static void Capture(id m,SEL sel,id array,NSUInteger index) {
    if(applying || !NSThread.isMainThread) { ((void(*)(id,SEL,id))setters[index])(m,sel,array); return; }
    WUHomeSnapshot *s=Snapshot(m);
    if(![s current]) { s.account=WUCurrentAccount(); s.source=[NSMutableArray arrayWithArray:@[NSNull.null,NSNull.null,NSNull.null]]; s.published=nil; s.filtered=NO; s.countKnown=NO; s.invalid=NO; }
    // A host echo of our projection must not replace the unfiltered snapshot.
    BOOL echo=s.published.count==3 && array==s.published[index];
    ((void(*)(id,SEL,id))setters[index])(m,sel,array);
    if(!echo) { if(![array isKindOfClass:NSArray.class] || [array count]>20000) { s.invalid=YES; return; } s.source[index]=[array copy]; }
    [s schedule];
}
static void Top(id m,SEL s,id a) { Capture(m,s,a,0); }
static void AllTop(id m,SEL s,id a) { Capture(m,s,a,1); }
static void Normal(id m,SEL s,id a) { Capture(m,s,a,2); }
static void Count(id m,SEL s,NSUInteger n) {
    if(applying || !NSThread.isMainThread) { ((void(*)(id,SEL,NSUInteger))countSetter)(m,s,n); return; }
    WUHomeSnapshot *snap=Snapshot(m);
    if(![snap current]) { snap.account=WUCurrentAccount(); snap.source=[NSMutableArray arrayWithArray:@[NSNull.null,NSNull.null,NSNull.null]]; snap.filtered=NO; snap.invalid=NO; }
    snap.topCount=n; snap.countKnown=YES; snap.published=nil;
    ((void(*)(id,SEL,NSUInteger))countSetter)(m,s,n); [snap schedule];
}
static UITableView *Table(UIView *v,NSUInteger depth) { if(!depth) return nil; if([v isKindOfClass:UITableView.class]) return (id)v; if(v.subviews.count>100) return nil; for(UIView *c in v.subviews) { UITableView *t=Table(c,depth-1); if(t) return t; } return nil; }
static NSArray *Tabs(NSDictionary *s) { return [@[@{@"id":@"all",@"name":@"全部"},@{@"id":@"private",@"name":@"私信"},@{@"id":@"chatroom",@"name":@"群聊"},@{@"id":@"other",@"name":@"其他"}] arrayByAddingObjectsFromArray:s[@"groups"]]; }
@interface WUHomePage : NSObject
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,weak) UITableView *table;
@property(nonatomic,strong) UIView *originalHeader, *header;
@property(nonatomic,strong) UISegmentedControl *tabs;
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSArray *ids;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,copy) NSDictionary *renderedState;
@property(nonatomic) CGRect originalHeaderFrame;
@property(nonatomic) CGFloat renderedWidth;
- (void)restore;
- (void)refresh;
@end
@implementation WUHomePage
- (void)restore { if(self.table.tableHeaderView==self.header) { [self.originalHeader removeFromSuperview]; self.originalHeader.frame=self.originalHeaderFrame; self.table.tableHeaderView=self.originalHeader; } [self.header removeFromSuperview]; self.header=nil; self.tabs=nil; self.originalHeader=nil; self.renderedState=nil; }
- (void)refresh {
    NSString *a=WUCurrentAccount(); NSDictionary *state=State(a); BOOL available=NO;
    for(WUHomeSnapshot *s in managers.allObjects) if([s current] && !s.invalid && s.countKnown && ![s.source containsObject:NSNull.null]) { [s apply]; available=s.filtered; }
    if(!ready || !available || ![state[@"enabled"] boolValue] || ![WUValue(@"enabled") boolValue] || !self.owner.viewIfLoaded.window) { [self restore]; return; }
    UITableView *t=Table(self.owner.view,8); if(!t) { [self restore]; return; }
    if(self.table!=t || ![a isEqual:self.account]) { [self restore]; self.table=t; }
    self.account=a; self.generation=WUContextGeneration();
    if(self.header && t.tableHeaderView!=self.header) [self restore];
    if(self.header && [self.renderedState isEqual:state] && self.renderedWidth==t.bounds.size.width) return;
    self.renderedState=[state copy]; self.renderedWidth=t.bounds.size.width;
    if(!self.header) { self.originalHeader=t.tableHeaderView; self.originalHeaderFrame=self.originalHeader.frame; self.header=[[UIView alloc] initWithFrame:CGRectMake(0,0,t.bounds.size.width,44+self.originalHeader.bounds.size.height)]; self.header.autoresizingMask=UIViewAutoresizingFlexibleWidth; if(self.originalHeader) { CGRect f=self.originalHeader.frame; f.origin.y=44; self.originalHeader.frame=f; [self.header addSubview:self.originalHeader]; } t.tableHeaderView=self.header; }
    [self.tabs removeFromSuperview]; NSArray *tabs=Tabs(state); NSMutableArray *titles=[NSMutableArray array],*ids=[NSMutableArray array]; for(NSDictionary *tab in tabs) { [titles addObject:tab[@"name"]]; [ids addObject:tab[@"id"]]; } self.ids=ids;
    UIScrollView *scroll=(id)[self.header viewWithTag:7184]; if(!scroll) { scroll=[[UIScrollView alloc] initWithFrame:CGRectMake(0,0,t.bounds.size.width,44)]; scroll.tag=7184; scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth; [self.header addSubview:scroll]; }
    self.tabs=[[UISegmentedControl alloc] initWithItems:titles]; self.tabs.frame=CGRectMake(8,4,MAX(t.bounds.size.width-16,ids.count*76),36); scroll.contentSize=CGSizeMake(self.tabs.bounds.size.width+16,44); self.tabs.selectedSegmentIndex=[ids indexOfObject:state[@"selected"]]; [self.tabs addTarget:self action:@selector(select:) forControlEvents:UIControlEventValueChanged]; [scroll addSubview:self.tabs];
}
- (void)select:(UISegmentedControl *)sender { NSInteger index=sender.selectedSegmentIndex; if(index<0 || (NSUInteger)index>=self.ids.count || self.generation!=WUContextGeneration() || ![self.account isEqual:WUCurrentAccount()] || !self.owner.viewIfLoaded.window || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) { [self restore]; return; } NSMutableDictionary *s=[State(self.account) mutableCopy]; s[@"selected"]=self.ids[index]; (void)WUSaveAccountOption(self.account,@"home",s); }
@end
void WURefreshHome(UIViewController *owner) {
    if(!NSThread.isMainThread) return;
    WUHomePage *p=objc_getAssociatedObject(owner,&pageKey); if(!p) { p=[WUHomePage new]; p.owner=owner; objc_setAssociatedObject(owner,&pageKey,p,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [homePages addObject:p]; }
    @try { [p refresh]; } @catch(NSException *e) { [p restore]; }
}
static void Refresh(void) { for(WUHomeSnapshot *s in managers.allObjects) [s apply]; for(WUHomePage *p in homePages.allObjects) { [p refresh]; [p.table reloadData]; } }

@interface WUHomeGroupsController : UITableViewController
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSArray *users;
@end
@implementation WUHomeGroupsController
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"首页电报分组"; self.account=WUCurrentAccount(); [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:WUChanged object:nil]; [self refresh]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (BOOL)current { return self.account.length && [self.account isEqual:WUCurrentAccount()]; }
- (void)refresh { NSMutableOrderedSet *users=[NSMutableOrderedSet orderedSet]; if([self current]) for(WUHomeSnapshot *s in managers.allObjects) if([s current]) for(id array in s.source) if([array isKindOfClass:NSArray.class]) for(id native in array) { NSDictionary *r=Row(native); if(r) [users addObject:r[@"username"]]; } self.users=users.array; [self.tableView reloadData]; }
- (BOOL)save:(NSDictionary *)state { if(![self current]) return NO; BOOL ok=WUSaveAccountOption(self.account,@"home",state); if(!ok && !self.presentedViewController) { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"保存失败" message:@"账号改变、配置超限或写入失败；原配置保留。" preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; } return ok; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return ![self current]?0:(s==0?2+Tabs(State(self.account)).count:self.users.count); }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return s==0?@"账号独立页签":@"原会话标识 · 点按移动到自定义组"; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s { return s==0?(ready?@"关闭恢复原列表。左滑只删除自定义组及成员映射，不删除聊天。页签仅在宿主已提供完整、可分类的三数组快照后显示；未知模型保持原列表。":@"宿主签名不匹配，首页分组不可用；不修改列表。"): @"标识取自原生session，非界面标题。置顶、未读与点击仍由宿主处理；无真机兼容承诺。"; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; NSDictionary *s=State(self.account);
    if(p.section==1) { c.textLabel.text=self.users[p.row]; c.detailTextLabel.text=@"未分组"; for(NSDictionary *g in s[@"groups"]) if([g[@"id"] isEqual:s[@"membership"][self.users[p.row]]]) c.detailTextLabel.text=g[@"name"]; }
    else if(p.row==0) { c.textLabel.text=@"启用首页电报分组"; UISwitch *sw=[UISwitch new]; sw.enabled=ready; sw.on=[s[@"enabled"] boolValue]; [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; c.accessoryView=sw; }
    else if(p.row==1) c.textLabel.text=@"＋ 创建自定义组";
    else { NSDictionary *g=Tabs(s)[p.row-2]; c.textLabel.text=g[@"name"]; if([s[@"selected"] isEqual:g[@"id"]]) c.accessoryType=UITableViewCellAccessoryCheckmark; } return c;
}
- (void)toggle:(UISwitch *)sw { NSMutableDictionary *s=[State(self.account) mutableCopy]; s[@"enabled"]=@(sw.on); if(![self save:s]) sw.on=!sw.on; }
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; if(![self current] || self.presentedViewController) return;
    if(p.section==0 && p.row!=1) { if(p.row==0) return; NSMutableDictionary *s=[State(self.account) mutableCopy]; s[@"selected"]=Tabs(s)[p.row-2][@"id"]; [self save:s]; return; }
    NSUInteger gen=WUContextGeneration(); __weak WUHomeGroupsController *weak=self;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:p.section==0?@"创建分组":@"移动会话" message:nil preferredStyle:UIAlertControllerStyleAlert];
    if(p.section==0) { [a addTextFieldWithConfigurationHandler:nil]; __weak UIAlertController *input=a;
        [a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { WUHomeGroupsController *v=weak; if(!v.viewIfLoaded.window || ![v current] || gen!=WUContextGeneration() || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return; NSString *name=[input.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!name.length || name.length>40) return; NSMutableDictionary *s=[State(v.account) mutableCopy]; NSMutableArray *g=[s[@"groups"] mutableCopy]; [g addObject:@{@"id":NSUUID.UUID.UUIDString,@"name":name}]; s[@"groups"]=g; [v save:s]; }]];
    } else { NSString *user=self.users[p.row]; NSArray *groups=[@[@{@"id":@"",@"name":@"未分组"}] arrayByAddingObjectsFromArray:State(self.account)[@"groups"]]; for(NSDictionary *group in groups) [a addAction:[UIAlertAction actionWithTitle:group[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { WUHomeGroupsController *v=weak; if(!v.viewIfLoaded.window || ![v current] || gen!=WUContextGeneration() || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return; NSMutableDictionary *s=[State(v.account) mutableCopy],*members=[s[@"membership"] mutableCopy]; if([group[@"id"] length]) members[user]=group[@"id"]; else [members removeObjectForKey:user]; s[@"membership"]=members; [v save:s]; }]]; }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)p { return p.section==0 && p.row>=6 && [self current]; }
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)p { if(style==UITableViewCellEditingStyleDelete && [self current] && p.section==0 && p.row>=6) [self save:WURemoveHomeGroup(State(self.account),Tabs(State(self.account))[p.row-2][@"id"])]; }
@end
void WUShowHomeGroups(UIViewController *owner) { if(!owner.navigationController) return; [owner.navigationController pushViewController:[[WUHomeGroupsController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES]; }
void WUInstallHomeGroups(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{
        managers=[NSHashTable weakObjectsHashTable]; homePages=[NSHashTable weakObjectsHashTable];
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ Refresh(); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ Refresh(); }];
    });
    if(ready) return;
    getNames=@[@"topSessions",@"allTopSessions",@"normalSessions"]; setNames=@[@"setTopSessions:",@"setAllTopSessions:",@"setNormalSessions:"];
    Class cls=NSClassFromString(@"MainSessionMgr"); BOOL valid=cls!=Nil;
    for(NSUInteger i=0;i<3;i++) valid=valid && WUMatches(class_getInstanceMethod(cls,NSSelectorFromString(getNames[i])),"@",@[]) && WUMatches(class_getInstanceMethod(cls,NSSelectorFromString(setNames[i])),"v",@[@"@"]);
    valid=valid && WUMatches(class_getInstanceMethod(cls,NSSelectorFromString(@"setTotalTopSessionCount:")),"v",@[@(@encode(NSUInteger))]);
    if(valid) { BOOL a=WUHook(@"MainSessionMgr",setNames[0],NO,"v",@[@"@"],(IMP)Top,&setters[0]); BOOL b=WUHook(@"MainSessionMgr",setNames[1],NO,"v",@[@"@"],(IMP)AllTop,&setters[1]); BOOL c=WUHook(@"MainSessionMgr",setNames[2],NO,"v",@[@"@"],(IMP)Normal,&setters[2]); BOOL d=WUHook(@"MainSessionMgr",@"setTotalTopSessionCount:",NO,"v",@[@(@encode(NSUInteger))],(IMP)Count,&countSetter); ready=a&&b&&c&&d; }
}
