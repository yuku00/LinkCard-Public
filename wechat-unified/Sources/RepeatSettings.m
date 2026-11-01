#import "MessageEntries.h"
#import "RepeatOptions.h"
@interface WURepeatSettings : UITableViewController
@property(nonatomic,copy) NSString *account;
@end
@implementation WURepeatSettings
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"复读标签 · 图标与下载"; self.account=WUCurrentAccount();
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:WUChanged object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)refresh { [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section==0?5:5; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if(section==0) return @"25×25、透明度1、圆角6。使用图片按钮关闭后显示文字；启用主题图标时按当前主题wu_repeat_icon→用户图标→系统复读图标回退。长按下载只导出当前可得原GIF/PNG/JPEG，不写Photos。关闭常规复读只禁用点按发送，长按下载可独立保留。";
    return @"仅47类表情和原有常规复读发送器。宿主长按菜单追加复读、文件复读缺少已核验绑定，保持关闭且不可启用，未冒充完成。不会修改宿主原菜单或另建发送器。用户图标从Files导入并由现有主题渲染/缓存显示；GIF作为按钮可能仅显示首帧，但消息下载保留原GIF。";
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0;
    NSDictionary *options=WUValue(@"repeatOptions")?:WURepeatDefaults();
    if(p.section==0) {
        NSArray *keys=@[@"repeatEmoticon",@"normalRepeat",@"imageButton",@"themeIcon",@"longDownload"];
        cell.textLabel.text=@[@"启用消息复读标签",@"常规方式复读（点按后确认）",@"使用图片按钮",@"优先使用当前主题图标",@"长按标签动作：下载到文件"][p.row];
        NSString *key=keys[p.row]; UISwitch *toggle=[UISwitch new]; toggle.accessibilityIdentifier=key; toggle.accessibilityLabel=cell.textLabel.text;
        toggle.on=[(p.row==0?WUValue(key):options[key]) boolValue]; toggle.enabled=[self.account isEqual:WUCurrentAccount()] && (p.row!=0 || toggle.on || WUMessageAvailable(@"repeatEmoticon"));
        if(!toggle.enabled) cell.detailTextLabel.text=@"账号已变化或当前宿主复读接口不可用。";
        [toggle addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=toggle;
    } else {
        cell.textLabel.text=@[@"从文件导入用户图标",@"恢复系统图标后备",@"仅对表情添加：开启",@"长按宿主菜单添加复读：关闭（待适配）",@"仅对文件生效：关闭（待适配）"][p.row];
        if(p.row<2) { cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; cell.detailTextLabel.text=[options[@"userIcon"] length]?@"已配置用户图标；主题开关开启时主题优先。":@"未配置用户图标"; }
        else { cell.selectionStyle=UITableViewCellSelectionStyleNone; cell.textLabel.textColor=UIColor.secondaryLabelColor; }
    }
    return cell;
}
- (void)failed {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"未保存" message:@"账号变化或配置写盘失败，原配置保留。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)change:(UISwitch *)toggle {
    NSString *key=toggle.accessibilityIdentifier; NSMutableDictionary *next=[(WUValue(@"repeatOptions")?:WURepeatDefaults()) mutableCopy]; next[key]=@(toggle.on);
    BOOL ok=[self.account isEqual:WUCurrentAccount()] && ([key isEqual:@"repeatEmoticon"]?WUSave(key,@(toggle.on)):WUSave(@"repeatOptions",next));
    if(!ok) { [self refresh]; [self failed]; }
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)p {
    [table deselectRowAtIndexPath:p animated:YES]; if(p.section!=1 || p.row>1 || ![self.account isEqual:WUCurrentAccount()]) return;
    if(p.row==0) { WUChooseRepeatIcon(self); return; }
    NSMutableDictionary *next=[(WUValue(@"repeatOptions")?:WURepeatDefaults()) mutableCopy]; next[@"userIcon"]=@"";
    if(!WUSave(@"repeatOptions",next)) [self failed];
}
@end
void WUShowRepeatSettings(UIViewController *owner) {
    WURepeatSettings *settings=[[WURepeatSettings alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [owner.navigationController pushViewController:settings animated:YES];
}
