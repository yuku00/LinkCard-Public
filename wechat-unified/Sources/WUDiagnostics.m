#import "WUDiagnostics.h"
#import "WU.h"
#import <objc/runtime.h>
#import <stdlib.h>
#import "WUCandidateManifest.inc"

@interface WUDiagnosticsLock : NSObject @end
@implementation WUDiagnosticsLock @end
static WUDiagnosticRing WUEvents;
void WURecordDiagnosticEvent(WUDiagnosticEvent event) {
    @synchronized (WUDiagnosticsLock.class) { WUDiagnosticRingAdd(&WUEvents,event); }
}
void WURecordAccountDiagnosticEvent(WUDiagnosticEvent event) {
    if(event<WUDiagAccountCenterClass || event>=WUDiagEventEnd) return;
    static WUDiagnosticRate rates[WUDiagEventEnd];
    @synchronized (WUDiagnosticsLock.class) {
        if(WUDiagnosticRateAllow(&rates[event],NSProcessInfo.processInfo.systemUptime)) WUDiagnosticRingAdd(&WUEvents,event);
    }
}
static NSArray<NSString *> *WUEventSnapshot(void) {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names=@[@"", @"入口：所选消息", @"入口：手动输入", @"拒绝：无账号上下文", @"拒绝：流程无法开始", @"拒绝：没有可用候选", @"拒绝：目标校验失败", @"请求弹窗：输入框", @"请求弹窗：候选选择", @"请求弹窗：目标确认", @"转换拒绝：状态无效或正在转换", @"转换开始", @"转换完成", @"转换中止：流程已结束或上下文失效", @"展示拒绝：上下文或弹窗状态无效", @"展示异常", @"请求：内置 Safari", @"请求：系统打开", @"系统打开 completion：已接受", @"系统打开 completion：未接受", @"拒绝：链接功能未启用", @"拒绝：选择数量或类型无效", @"拒绝：账号或会话上下文不可核验", @"拒绝：消息不可核验或超限", @"链接流程结束", @"账号链：服务中心类缺失", @"账号链：默认中心签名不匹配", @"账号链：默认中心为空", @"账号链：联系人管理器类缺失", @"账号链：服务获取签名不匹配", @"账号链：联系人管理器为空", @"账号链：自身联系人签名不匹配", @"账号链：自身联系人为空", @"账号链：账号字段签名不匹配", @"账号链：账号字段无效或为空", @"账号链：调用异常", @"账号链：MMContext 类缺失", @"账号链：activeUserContext 签名不匹配", @"账号链：activeUserContext 为空", @"账号链：currentContext 签名不匹配", @"账号链：currentContext 为空", @"账号链：上下文 getService: 签名不匹配", @"账号链：上下文联系人管理器为空", @"账号链：旧中心类缺失", @"账号链：旧中心 defaultCenter 签名不匹配", @"账号链：旧中心为空", @"账号链：旧中心 getService: 签名不匹配", @"账号链：旧中心联系人管理器为空", @"账号链：宿主服务调用异常"]; });
    NSMutableArray *out=[NSMutableArray array];
    @synchronized (WUDiagnosticsLock.class) {
        for(size_t i=0;i<WUEvents.count;i++) [out addObject:names[WUEvents.values[(WUEvents.start+i)%WU_DIAGNOSTIC_CAPACITY]]];
    }
    return [out copy];
}

@interface WUDiagnostics : UITableViewController <UISearchResultsUpdating>
@property(nonatomic,strong) NSArray<NSString *> *hooks;
@property(nonatomic,strong) NSArray<NSString *> *events;
@property(nonatomic,strong) NSArray<NSString *> *results;
@property(nonatomic,strong) NSArray<NSString *> *visibleHooks;
@property(nonatomic,strong) UISearchController *search;
@property(atomic,assign) NSUInteger generation;
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic,strong) NSArray<NSString *> *candidateResults;
@property(nonatomic,assign) BOOL collecting;
@property(atomic,assign) NSUInteger collectGeneration;
@property(nonatomic,copy) NSString *candidateReport;
@end

static NSString *WUDescribeMethod(Class cls, SEL sel, BOOL meta) {
    if(!cls) return @"未知（类未加载）";
    Method method=meta?class_getClassMethod(cls,sel):class_getInstanceMethod(cls,sel);
    if(!method) return @"当前未发现";
    const char *encoding=method_getTypeEncoding(method);
    return [NSString stringWithFormat:@"存在，类型编码 %@",encoding?[NSString stringWithUTF8String:encoding]:@"未知"];
}

@implementation WUDiagnostics
- (void)collectCandidates {
    if(self.collecting) return;
    UIAlertController *notice=[UIAlertController alertControllerWithTitle:@"批量采集候选接口" message:@"仅检查项目源码、既有逆向和缺口证据中的已知类与方法，包含暂缓功能的只读诊断，绝不启用这些功能。记录类名、方法名、方法类型编码、来源与现有安装记录；类名可能暴露其他插件。不读取对象实例、账号、消息、网址或凭证，不调用宿主业务，不自动分享。缺失不代表永久不可用。" preferredStyle:UIAlertControllerStyleAlert];
    [notice addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [notice addAction:[UIAlertAction actionWithTitle:@"开始只读采集" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self beginCandidateCollection]; }]];
    [self presentViewController:notice animated:YES completion:nil];
}
- (void)beginCandidateCollection {
    if(self.collecting) return;
    NSDictionary *manifest=[NSJSONSerialization JSONObjectWithData:[[NSString stringWithUTF8String:WUCandidateJSON] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    NSArray *items=manifest[@"candidates"];
    if(![items isKindOfClass:NSArray.class]) { self.candidateResults=@[@"清单解析失败"]; [self.tableView reloadData]; return; }
    self.collecting=YES; self.candidateReport=nil; self.candidateResults=@[];
    NSUInteger generation=++self.collectGeneration;
    NSArray *hooks=[WUHookStatus() copy];
    NSString *environment=[self environment];
    [self.tableView reloadData];
    dispatch_async(self.queue, ^{
        NSMutableArray<NSString *> *lines=[NSMutableArray array];
        __block NSUInteger index=0;
        __weak WUDiagnostics *weakSelf=self;
        __block void (^batch)(void);
        batch=^{
            WUDiagnostics *owner=weakSelf;
            if(!owner || generation!=owner.collectGeneration) { batch=nil; return; }
            @autoreleasepool {
                NSUInteger end=MIN(index+50,items.count);
                for(;index<end;index++) {
                    NSDictionary *item=items[index]; NSString *name=item[@"class"], *selector=item[@"selector"], *kind=item[@"kind"];
                    NSString *status;
                    if(!name.length) status=@"未关联类：实例/类方法存在性和类型未知";
                    else {
                        Class cls=objc_lookUpClass(name.UTF8String);
                        if(!selector.length) status=cls?@"类已加载":@"类当前未发现（可能尚未加载）";
                        else {
                            SEL sel=sel_registerName(selector.UTF8String);
                            status=[NSString stringWithFormat:@"实例方法：%@；类方法：%@",WUDescribeMethod(cls,sel,NO),WUDescribeMethod(cls,sel,YES)];
                        }
                    }
                    NSMutableArray *records=[NSMutableArray array];
                    if(name.length && selector.length) for(NSString *record in hooks) {
                        NSString *a=[NSString stringWithFormat:@"-%@ %@ — ",name,selector];
                        NSString *b=[NSString stringWithFormat:@"+%@ %@ — ",name,selector];
                        if([record hasPrefix:a] || [record hasPrefix:b]) [records addObject:record];
                    }
                    [lines addObject:[NSString stringWithFormat:@"%@ %@ %@\n%@\n安装记录：%@\n来源：%@",name.length?name:@"未关联类",selector.length?selector:@"（类候选）",kind,status,records.count?[records componentsJoinedByString:@"；"]:@"未知（无记录）",[item[@"sources"] componentsJoinedByString:@"；"]]];
                }
            }
            if(index<items.count) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_MSEC),owner.queue,batch); return; }
            NSArray *finished=[lines copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                WUDiagnostics *strong=weakSelf; if(!strong || generation!=strong.collectGeneration) return;
                strong.collecting=NO; strong.candidateResults=finished;
                strong.candidateReport=[NSString stringWithFormat:@"微信整合候选接口报告\n清单 schema %@ / %@\n%@\n共 %lu 项；快照只反映采集时已加载运行时。当前未发现不代表永久不可用，继承方法也会显示；存在不代表签名兼容或功能正常。安装记录仅为最近记录，不验证当前实现。未关联方法未猜测所属类。\n待定：原图专用交付和确认生命周期、GIF正式入库结果、朋友圈可见单元绑定及伪赞完成回调、完整共同群及入群时间、激励广告奖励流程等缺少已确认接口；未按功能名猜测。参考 requirements.md、reverse-repository-send.md、reverse-voice-state.md、REMAINING.md 和两个 GAP 文档。伪集赞等用户暂缓项仅作只读诊断，绝不启用。\n\n%@",manifest[@"schema"],manifest[@"generator"],environment,(unsigned long)finished.count,[finished componentsJoinedByString:@"\n\n"]];
                [strong.tableView reloadData];
            });
            batch=nil;
        };
        batch();
    });
}
- (void)shareCandidates:(UIBarButtonItem *)sender {
    if(!self.candidateReport) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"暂无候选报告" message:@"请先点击批量采集并等待完成。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; return;
    }
    NSString *report=[self.candidateReport copy];
    UIAlertController *warning=[UIAlertController alertControllerWithTitle:@"手动分享候选报告？" message:@"报告包含类名、方法名和类型编码，类名可能暴露其他插件的存在。请先检查报告，仅在你选择分享方式后发送。不会自动上传。" preferredStyle:UIAlertControllerStyleAlert];
    [warning addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [warning addAction:[UIAlertAction actionWithTitle:@"选择分享方式" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:@[report] applicationActivities:nil];
        sheet.popoverPresentationController.barButtonItem=sender; [self presentViewController:sheet animated:YES completion:nil];
    }]];
    [self presentViewController:warning animated:YES completion:nil];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.events=WUEventSnapshot(); [self.tableView reloadData]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"本地接口与诊断";
    self.hooks=WUHookStatus(); self.visibleHooks=self.hooks; self.events=WUEventSnapshot(); self.results=@[];
    self.queue=dispatch_queue_create("org.wechatunified.diagnostics", DISPATCH_QUEUE_SERIAL);
    self.search=[[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater=self; self.search.obscuresBackgroundDuringPresentation=NO;
    self.search.searchBar.placeholder=@"搜索类名、selector 或安装状态";
    self.navigationItem.searchController=self.search; self.definesPresentationContext=YES;
    self.navigationItem.rightBarButtonItems=@[
        [[UIBarButtonItem alloc] initWithTitle:@"分享候选报告" style:UIBarButtonItemStylePlain target:self action:@selector(shareCandidates:)],
        [[UIBarButtonItem alloc] initWithTitle:@"批量采集" style:UIBarButtonItemStylePlain target:self action:@selector(collectCandidates)],
        [[UIBarButtonItem alloc] initWithTitle:@"分享摘要" style:UIBarButtonItemStylePlain target:self action:@selector(shareSummary:)]
    ];
    self.candidateResults=@[];
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=50;
}
- (NSString *)environment {
    NSString *version=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if(![version isKindOfClass:NSString.class] || version.length>40) version=@"未知";
    return [NSString stringWithFormat:@"宿主版本：%@\niOS：%@\n插件：当前页面已加载；安装来源未知\n应用签名：未验证\n账号状态：未知（不读取账号）",version,UIDevice.currentDevice.systemVersion];
}
- (void)shareSummary:(UIBarButtonItem *)sender {
    NSString *body=[NSString stringWithFormat:@"微信整合本地诊断摘要\n%@\n\nHook 最近安装记录（非实时完整性校验）：\n%@\n\n当前页面可见的链接与账号链诊断事件（按记录顺序）：\n%@\n\n不额外附带搜索词或运行时搜索结果；Hook 名称本身可能包含搜索词；缺失或签名不匹配不等于故障原因。",[self environment],self.hooks.count?[self.hooks componentsJoinedByString:@"\n"]:@"无记录（可能被启动保护阻止）", self.events.count?[self.events componentsJoinedByString:@"\n"]:@"无事件"];
    UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:@[body] applicationActivities:nil];
    sheet.popoverPresentationController.barButtonItem=sender;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *q=[controller.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSUInteger generation=++self.generation;
    NSMutableArray *filtered=[NSMutableArray array];
    for(NSString *line in self.hooks) if(!q.length || [line rangeOfString:q options:NSCaseInsensitiveSearch].location!=NSNotFound) [filtered addObject:line];
    self.visibleHooks=filtered; self.results=@[];
    if(q.length<2 || q.length>80) { self.results=@[]; [self.tableView reloadData]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        if(generation!=self.generation) return;
        dispatch_async(self.queue, ^{
            @autoreleasepool {
                NSMutableArray<NSString *> *matches=[NSMutableArray array];
                unsigned count=0; Class *classes=objc_copyClassList(&count);
                unsigned limit=MIN(count,2000u);
                for(unsigned i=0;i<limit && matches.count<100 && generation==self.generation;i++) {
                    Class c=classes[i]; const char *name=class_getName(c); if(!name) continue;
                    NSString *className=[NSString stringWithUTF8String:name]; if(!className) continue;
                    if([className rangeOfString:q options:NSCaseInsensitiveSearch].location!=NSNotFound)
                        [matches addObject:[@"类 " stringByAppendingString:className]];
                    for(int meta=0;meta<2 && matches.count<100;meta++) {
                        unsigned n=0; Method *methods=class_copyMethodList(meta?object_getClass(c):c,&n);
                        for(unsigned j=0;j<MIN(n,100u) && matches.count<100;j++) {
                            const char *raw=sel_getName(method_getName(methods[j]));
                            NSString *selector=raw?[NSString stringWithUTF8String:raw]:nil;
                            if(selector && [selector rangeOfString:q options:NSCaseInsensitiveSearch].location!=NSNotFound)
                                [matches addObject:[NSString stringWithFormat:@"%@[%@ %@]",meta?@"+":@"-",className,selector]];
                        }
                        free(methods);
                    }
                }
                free(classes);
                dispatch_async(dispatch_get_main_queue(), ^{ if(generation==self.generation) { self.results=matches; [self.tableView reloadData]; } });
            }
        });
    });
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(section==0) return 1;
    if(section==1) return self.visibleHooks.count?:1;
    if(section==2) return self.events.count?:1;
    if(section==3) return self.results.count?:1;
    return self.candidateResults.count?:1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"环境（本地只读）",@"Hook 最近安装记录",@"链接与账号链诊断事件（进入页面时快照）",@"运行时搜索结果",@"批量候选（缺失与未知）"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if(section==1) return @"installed 仅表示最近一次安装记录，不证明当前未被覆盖或功能正常；签名指方法类型，不是应用签名。";
    if(section==2) return @"仅内存，最多128条，重启消失；不记录网址、搜索词、正文或账号，不自动上传。事件为进程级，切号不清空且可能跨流程交错；同一账号链失败事件最多每5秒记录一次。";
    if(section==3) return @"点击单条结果可手动选择分享；类名和方法名可能敏感。输入 2–80 字符；后台搜索最多前 2000 个已加载类、每类每种方法前 100 个，最多显示 100 条，仅列本类声明的方法，不保证完整。查询和结果仅在内存中，不写日志、不上传；分享仅由你手动操作。";
    if(section==4) return @"来源为静态候选及手工证据；未关联或未加载为未知，不代表永久不可用。暂缓功能仅诊断，绝不启用；报告只在明确分享时交给系统分享面板。";
    return @"不读取消息、联系人、账号或凭证；不能据此判定卡死原因。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.numberOfLines=0; cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.textLabel.adjustsFontForContentSizeCategory=YES; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    if(indexPath.section==0) cell.textLabel.text=[self environment];
    else if(indexPath.section==1) cell.textLabel.text=self.visibleHooks.count?self.visibleHooks[indexPath.row]:@"无匹配记录";
    else if(indexPath.section==2) cell.textLabel.text=self.events.count?self.events[indexPath.row]:@"无事件";
    else if(indexPath.section==3) { cell.textLabel.text=self.results.count?self.results[indexPath.row]:@"输入关键词；无结果不代表接口不存在"; if(self.results.count) cell.selectionStyle=UITableViewCellSelectionStyleDefault; }
    else cell.textLabel.text=self.candidateResults.count?self.candidateResults[indexPath.row]:(self.collecting?@"后台分批采集中…":@"点击批量采集，查看候选及缺失");
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.section!=3 || (NSUInteger)indexPath.row>=self.results.count) return;
    NSString *selected=[self.results[indexPath.row] copy];
    UIAlertController *warning=[UIAlertController alertControllerWithTitle:@"分享此条接口结果？" message:@"类名和方法名可能包含敏感的应用内部信息；仅分享你选择的这一条，结果本身可能包含搜索词。" preferredStyle:UIAlertControllerStyleAlert];
    [warning addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [warning addAction:[UIAlertAction actionWithTitle:@"选择分享方式" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:@[selected] applicationActivities:nil];
        sheet.popoverPresentationController.sourceView=self.view;
        sheet.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
        [self presentViewController:sheet animated:YES completion:nil];
    }]];
    [self presentViewController:warning animated:YES completion:nil];
}
@end

void WUShowDiagnostics(UIViewController *owner) {
    [owner.navigationController pushViewController:[[WUDiagnostics alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}
