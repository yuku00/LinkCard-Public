#import "WUNative.h"
@interface WUNativeSettings : UITableViewController @end
@implementation WUNativeSettings
- (NSArray *)rows { return @[
 @[@"hotDisable",@"禁用微信热更新",@"拦截已匹配补丁加载入口；不删补丁文件。已加载补丁需重启。"],
 @[@"hotCompat",@"强兼热更新 · 暂未开放",@"泛恢复会遗留旧original或抢占第三方链。缺可验证的补丁写入适配，本场景关闭；不影响禁用热更新。"],
 @[@"jailbreak",@"禁用越狱检测",@"仅已匹配的JailBreakHelper返回；不修改系统版本或支付鉴权。"],
 @[@"clientReport",@"禁用加好友检测报告",@"阻止已匹配本地客户端检查/报告入口；不替代好友验证，不保证服务器接受。"],
 @[@"liveEnvironment",@"禁用录屏 / 通话 / VPN检测",@"仅SecDataReportUtil的三个检测；不全局伪造录屏、通话或网络状态。"],
 @[@"safeMode",@"禁止微信进入安全模式",@"须先接入独立启动守卫；首次开启下次启动生效。连续两次启动未完成则不装整合Hook，保留微信原恢复路径。"],
 @[@"keepKeyboard",@"播放语音保持键盘",@"只保护语音气泡触摸处理的同步收起动作。不抢回焦点，主动收起、切会话与停用照常。"],
 @[@"patConfirm",@"拍一拍前确认",@"头像双击发送前确认；取消不发送，切号、复用、切会话后确认失效。不覆盖未证明的其他入口。"],
 @[@"gameChoice",@"骰子 / 猜拳选择",@"当前聊天发出前选择，取消不发送；只用于非金钱娱乐，不保证对端最终效果。"],
 @[@"homeFinder",@"禁用首页视频号",@"未开放：已有线索属于个人资料入口，不能替代真实首页入口。"],
 @[@"rewardFast",@"快速观看激励广告",@"未开放：只恢复到激励MBAD实验开关，缺播放与奖励完成契约；不会伪报已发奖。"]]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"宿主行为 / 版本控制";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"启动保护复位" style:UIBarButtonItemStylePlain target:self action:@selector(resetGuard)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:WUChanged object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)refresh { [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [self rows].count; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    return @"全部默认关闭，受整合总开关控制。灰色项没有可启用执行链；已保存的开关随时允许关闭。接口匹配与合成测试不等于目标微信验收。";
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    NSArray *row=[self rows][p.row]; NSString *key=row[0];
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=row[1]; cell.detailTextLabel.text=row[2];
    cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0;
    UISwitch *sw=[UISwitch new]; sw.accessibilityIdentifier=key; sw.accessibilityLabel=row[1];
    id options=WUValue(@"native"); sw.on=WUNativeValidOptions(options) && [options[key] boolValue];
    sw.enabled=WUNativeAvailable(key) || sw.on;
    [sw addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView=sw; cell.selectionStyle=UITableViewCellSelectionStyleNone; return cell;
}
- (void)resetGuard {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"关闭整合并复位启动保护？" message:WUNativeGuardStatus() preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert=a;
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"关闭并复位" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        BOOL ok=WUNativeResetGuard();
        [weakAlert dismissViewControllerAnimated:NO completion:^{
            UIAlertController *result=[UIAlertController alertControllerWithTitle:ok?@"已复位":@"未复位" message:ok?WUNativeGuardStatus():@"守卫尚未接入，或持久保存失败。保持原恢复路径，不恢复Hook。" preferredStyle:UIAlertControllerStyleAlert];
            [result addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:result animated:YES completion:nil];
        }];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)change:(UISwitch *)sw {
    if(WUNativeSave(sw.accessibilityIdentifier,sw.on)) return;
    [self refresh];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"未更改" message:@"接口或启动守卫未就绪、当前功能未开放，或持久保存失败。原配置保持不变。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
void WUShowNativeSettings(UIViewController *owner) {
    if(!owner.navigationController) return;
    [owner.navigationController pushViewController:[[WUNativeSettings alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}
