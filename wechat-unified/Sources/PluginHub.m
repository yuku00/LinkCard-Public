#import "PluginHub.h"
static NSString *const HubChanged=@"org.wechatunified.plugin-hub.changed";
static NSMutableDictionary<NSString *,NSDictionary *> *entries;
static NSMapTable<NSString *,UIViewController *> *instances;
static IMP registerOriginal, registerClassOriginal;
static Class ControllerClass(NSString *name) {
    if(!WUHubValidControllerName(name)) return Nil;
    Class c=NSClassFromString(name);
    return c && [c isSubclassOfClass:UIViewController.class]?c:Nil;
}
static NSDictionary *Options(void) {
    id value=WUValue(@"pluginHub"); return WUHubValidOptions(value)?value:WUHubDefaultOptions();
}
static BOOL Enabled(void) { return [WUValue(@"enabled") boolValue] && [Options()[@"enabled"] boolValue]; }
static void Changed(void) {
    dispatch_async(dispatch_get_main_queue(),^{ [NSNotificationCenter.defaultCenter postNotificationName:HubChanged object:nil]; });
}
@implementation WUPluginHubManager
+ (instancetype)sharedInstance { static WUPluginHubManager *shared; static dispatch_once_t once; dispatch_once(&once,^{ shared=[self new]; }); return shared; }
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(id)controller {
    if(![title isKindOfClass:NSString.class] || !title.length || title.length>80) return;
    NSString *name=nil; UIViewController *instance=nil;
    if([controller isKindOfClass:NSString.class]) name=controller;
    else if(controller && object_isClass(controller)) name=NSStringFromClass(controller);
    else if([controller isKindOfClass:UIViewController.class]) { instance=controller; name=NSStringFromClass([controller class]); }
    if(!ControllerClass(name)) return;
    if(![version isKindOfClass:NSString.class] || version.length>80) version=@"";
    BOOL changed=NO;
    @synchronized(WUPluginHubManager.class) {
        if(!entries) { entries=[NSMutableDictionary dictionary]; instances=[NSMapTable strongToWeakObjectsMapTable]; }
        if(entries.count>=100 && !entries[name]) return;
        NSDictionary *row=@{@"controller":name,@"title":title,@"version":version};
        changed=![entries[name] isEqual:row]; entries[name]=row;
        if(instance) [instances setObject:instance forKey:name];
    }
    if(changed) Changed();
}
@end
static void Registered(id o,SEL s,id title,id version,id controller) {
    ((void(*)(id,SEL,id,id,id))registerOriginal)(o,s,title,version,controller);
    [[WUPluginHubManager sharedInstance] registerControllerWithTitle:title version:version controller:controller];
}
static void RegisteredClass(id o,SEL s,id title,id version,id controller) {
    ((void(*)(id,SEL,id,id,id))registerClassOriginal)(o,s,title,version,controller);
    [[WUPluginHubManager sharedInstance] registerControllerWithTitle:title version:version controller:controller];
}
void WUInstallPluginHub(void) {
    if(!registerOriginal) WUHook(@"WCPluginsMgr",@"registerControllerWithTitle:version:controller:",NO,"v",@[@"@",@"@",@"@"],(IMP)Registered,&registerOriginal);
    if(!registerClassOriginal) WUHook(@"WCPluginsMgr",@"registerControllerWithTitle:version:controller:",YES,"v",@[@"@",@"@",@"@"],(IMP)RegisteredClass,&registerClassOriginal);
    // Late-loaded registrars are retried through the existing Core install path.
    // Names are exact known settings controllers; no broad runtime/UI enumeration.
    NSDictionary *known=@{@"WCPulseSettingViewController":@"WCPulse",@"WCEhanceViewController":@"WCEhance",@"MiYouSettingViewController":@"MiYou",@"WCRefineRootViewController":@"WCRefine"};
    for(NSString *name in known) if(ControllerClass(name)) {
        BOOL exists; @synchronized(WUPluginHubManager.class) { exists=entries[name]!=nil; }
        if(!exists) [[WUPluginHubManager sharedInstance] registerControllerWithTitle:known[name] version:@"" controller:name];
    }
}
static NSArray *Registry(void) {
    NSMutableDictionary *all;
    @synchronized(WUPluginHubManager.class) { all=[entries mutableCopy]?:[NSMutableDictionary dictionary]; }
    NSDictionary *custom=Options()[@"custom"];
    for(NSString *name in custom) if(!all[name] && all.count<100) all[name]=@{@"controller":name,@"title":custom[name],@"version":@""};
    return [all.allValues copy];
}
@interface WUHubController : UITableViewController
@property(nonatomic,copy) NSArray<NSDictionary *> *rows;
@property(nonatomic,copy) NSArray *registry;
@property(nonatomic) BOOL showHidden;
@property(nonatomic,copy) NSString *groupFilter;
- (void)chooseGroup;
@end
@implementation WUHubController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"插件收纳";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"添加" style:UIBarButtonItemStylePlain target:self action:@selector(add)];
    for(NSString *name in @[WUChanged,HubChanged]) [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:name object:nil];
    WUInstallPluginHub(); [self refresh];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)refresh {
    self.registry=Registry(); NSArray *all=WUHubRows(self.registry,Options(),self.showHidden);
    if(self.groupFilter && ![[all valueForKey:@"group"] containsObject:self.groupFilter]) self.groupFilter=nil;
    NSMutableArray *rows=[NSMutableArray array];
    for(NSDictionary *row in all) if(!self.groupFilter || [row[@"group"] isEqual:self.groupFilter]) [rows addObject:row];
    self.rows=rows;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:self.groupFilter?:@"全部分组" style:UIBarButtonItemStylePlain target:self action:@selector(chooseGroup)];
    self.navigationItem.leftItemsSupplementBackButton=YES;
    [self.tableView reloadData];
}
- (void)chooseGroup {
    if(self.presentedViewController) return;
    NSMutableOrderedSet *groups=[NSMutableOrderedSet orderedSet];
    for(NSDictionary *row in WUHubRows(Registry(),Options(),self.showHidden)) [groups addObject:row[@"group"]];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"选择分组" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak WUHubController *weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"全部分组" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ weak.groupFilter=nil; [weak refresh]; }]];
    for(NSString *g in groups) [a addAction:[UIAlertAction actionWithTitle:g style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ weak.groupFilter=g; [weak refresh]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem=self.navigationItem.leftBarButtonItem;
    [self presentViewController:a animated:YES completion:nil];
}
- (void)notice:(NSString *)text {
    if(self.presentedViewController || !self.viewIfLoaded.window) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"插件收纳" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (BOOL)save:(NSDictionary *)options {
    if(!options || !WUHubValidOptions(options) || !WUSave(@"pluginHub",options)) { [self notice:@"保存失败，原设置保留。"]; return NO; }
    return YES;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s==0?2:self.rows.count; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return s==0?@"控制":@"已注册 / 已发现的设置入口"; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if(s==0) return @"只整理已加载插件的设置入口；不会卸载、注入插件，也不会自动隐藏原入口。受整合总开关控制。";
    return self.rows.count?@"长按入口可改名、分组、前后排序或隐藏。停用后不允许打开；不存在的类只保留元数据，不实例化替代。第三方插件内部行为仍由它自己负责。":@"尚无可收纳入口。可由插件调用本地注册接口，或手动添加已知设置控制器类名；不会扫描聊天或猜测任意类。";
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0;
    if(p.section==0) {
        UISwitch *sw=[UISwitch new]; sw.tag=p.row;
        sw.on=p.row==0?[Options()[@"enabled"] boolValue]:self.showHidden;
        cell.textLabel.text=p.row==0?@"启用插件收纳":@"显示已隐藏入口";
        [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=sw; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else {
        NSDictionary *row=self.rows[p.row]; NSString *name=row[@"controller"]; BOOL available=ControllerClass(name)!=Nil;
        cell.textLabel.text=row[@"title"];
        cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@%@\n%@",row[@"group"],available?@"已加载":@"未加载 / 已移除",[row[@"hidden"] boolValue]?@" · 已隐藏":@"",name];
        cell.accessoryType=available && Enabled()?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;
    }
    return cell;
}
- (void)toggle:(UISwitch *)sw {
    if(sw.tag==1) { self.showHidden=sw.on; [self refresh]; return; }
    NSMutableDictionary *o=[Options() mutableCopy]; o[@"enabled"]=@(sw.on);
    if(![self save:o]) sw.on=!sw.on;
}
- (void)add {
    if(self.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"添加设置入口" message:@"仅填写你确认的已加载插件设置类。打开时运行该插件自己的设置页，不加载新二进制。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"显示名称"; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"Objective-C 控制器类名"; f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *input=a; __weak WUHubController *weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"添加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        WUHubController *v=weak; if(!v.viewIfLoaded.window || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
        NSString *title=[input.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *name=[input.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(!title.length || title.length>80 || !ControllerClass(name)) { dispatch_async(dispatch_get_main_queue(),^{ [v notice:@"名称无效，或类不存在/不是设置控制器。没有添加或实例化任何对象。"]; }); return; }
        NSMutableDictionary *options=[Options() mutableCopy], *custom=[options[@"custom"] mutableCopy]; custom[name]=title; options[@"custom"]=custom;
        [v save:options];
    }]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; if(p.section!=1 || p.row<0 || (NSUInteger)p.row>=self.rows.count) return;
    if(!Enabled()) { [self notice:@"请先启用整合总开关和插件收纳。"]; return; }
    NSString *name=self.rows[p.row][@"controller"]; Class c=ControllerClass(name);
    if(!c || !WUMatches(class_getInstanceMethod(c,@selector(init)),"@",@[])) { [self notice:@"入口未加载或初始化签名不支持。"]; return; }
    if(!self.viewIfLoaded.window || self.presentedViewController || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
    NSUInteger gen=WUContextGeneration(); UIViewController *controller;
    @try {
        @synchronized(WUPluginHubManager.class) { controller=[instances objectForKey:name]; }
        if(!controller) controller=[[c alloc] init];
        if(![controller isKindOfClass:UIViewController.class] || controller==self || controller.parentViewController || controller.presentingViewController || controller.viewIfLoaded.window) { [self notice:@"该设置页已被其他页面持有，未重复打开。"]; return; }
        if(!Enabled() || gen!=WUContextGeneration() || !self.viewIfLoaded.window || self.presentedViewController) return;
        if([controller isKindOfClass:UINavigationController.class]) [self presentViewController:controller animated:YES completion:nil];
        else [self.navigationController pushViewController:controller animated:YES];
    } @catch(NSException *e) { [self notice:@"该插件设置页初始化或导航失败，未重试；原入口保持不变。"]; }
}
- (void)editEntry:(NSDictionary *)row {
    if(self.presentedViewController) return;
    NSString *identifier=row[@"controller"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"入口名称与分组" message:@"这只更改收纳元数据，不更改插件自身配置。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text=row[@"title"]; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text=row[@"group"]; f.placeholder=@"分组名"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *input=a; __weak WUHubController *weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        WUHubController *v=weak; if(!v.viewIfLoaded.window || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
        NSDictionary *o=Options();
        NSDictionary *next=WUHubSetEntry(o,identifier,input.textFields[0].text,input.textFields[1].text,[o[@"hidden"] containsObject:identifier]);
        if(next) [v save:next]; else dispatch_async(dispatch_get_main_queue(),^{ [v notice:@"名称/分组为空、超长或条目数超限，原设置保留。"]; });
    }]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)removeManualEntry:(NSString *)identifier {
    if(self.presentedViewController || !Options()[@"custom"][identifier]) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"移除手动添加的入口？" message:@"只移除此手动登记；名称、分组、隐藏和排序偏好保留。插件自身及原入口不会被删除；如果插件自行注册，该入口仍可能显示。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak WUHubController *weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"移除登记" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        WUHubController *v=weak; if(!v.viewIfLoaded.window || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
        NSMutableDictionary *options=[Options() mutableCopy], *custom=[options[@"custom"] mutableCopy];
        if(!custom[identifier]) return;
        [custom removeObjectForKey:identifier]; options[@"custom"]=custom; [v save:options];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)t contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)p point:(CGPoint)point {
    if(p.section!=1 || p.row<0 || (NSUInteger)p.row>=self.rows.count) return nil;
    NSDictionary *row=self.rows[p.row]; NSString *identifier=row[@"controller"]; __weak WUHubController *weak=self;
    return [UIContextMenuConfiguration configurationWithIdentifier:identifier previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested){
        NSMutableArray *actions=[NSMutableArray array];
        [actions addObject:[UIAction actionWithTitle:@"改名 / 分组" image:nil identifier:nil handler:^(UIAction *a){ if(weak.viewIfLoaded.window) [weak editEntry:row]; }]];
        [actions addObject:[UIAction actionWithTitle:[row[@"hidden"] boolValue]?@"显示入口":@"隐藏入口" image:nil identifier:nil handler:^(UIAction *a){
            if(!weak.viewIfLoaded.window) return;
            NSDictionary *o=Options(); [weak save:WUHubSetEntry(o,identifier,row[@"title"],row[@"group"],![o[@"hidden"] containsObject:identifier])];
        }]];
        for(NSNumber *delta in @[@(-1),@1]) [actions addObject:[UIAction actionWithTitle:delta.integerValue<0?@"前移一位":@"后移一位" image:nil identifier:nil handler:^(UIAction *a){
            if(!weak.viewIfLoaded.window) return;
            NSDictionary *next=WUHubMove(Options(),Registry(),identifier,delta.integerValue); if(next) [weak save:next];
            else [weak notice:@"无法移动：已到边界、入口不可用或排序存储已满；原排序保留。"];
        }]];
        if(Options()[@"custom"][identifier]) {
            UIAction *remove=[UIAction actionWithTitle:@"移除手动登记…" image:nil identifier:nil handler:^(UIAction *a){ if(weak.viewIfLoaded.window) [weak removeManualEntry:identifier]; }];
            remove.attributes=UIMenuElementAttributesDestructive; [actions addObject:remove];
        }
        return [UIMenu menuWithTitle:row[@"title"] children:actions];
    }];
}
@end
void WUShowPluginHub(UIViewController *owner) {
    if(!NSThread.isMainThread || !owner.navigationController || !owner.viewIfLoaded.window || owner.presentedViewController) return;
    [owner.navigationController pushViewController:[[WUHubController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}
