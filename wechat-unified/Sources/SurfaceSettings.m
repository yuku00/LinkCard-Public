#import "WU.h"
#import "ThemeCatalog.h"
static NSDictionary *RoleTitles(void) { return @{@"inputBorder":@"聊天输入框",@"noticeBorder":@"聊天系统通知",@"searchSurface":@"搜索栏",@"referSurface":@"引用卡片（原共享样式）",@"referMessageSurface":@"文本消息内引用卡片覆盖",@"textPreviewSurface":@"聊天文本预览底部工具栏",@"plusSurface":@"首页右上加号菜单",@"toastSurface":@"宿主Toast",@"timeSurface":@"聊天时间标签",@"swipeSurface":@"首页左滑菜单",@"fileSurface":@"文件消息背景",@"emoticonSurface":@"表情消息背景",@"chatSendSurface":@"聊天发送按钮",@"chatAttachmentSurface":@"聊天附件按钮"}; }
@interface WUSurfaceEditor : UITableViewController
@property(nonatomic,copy) NSString *role;
@property(nonatomic,strong) NSArray *fields;
@end
@implementation WUSurfaceEditor
- (void)viewDidLoad { [super viewDidLoad]; self.title=RoleTitles()[self.role]; self.fields=@[@[@"radius",@"圆角 (0–80pt)"],@[@"borderWidth",@"描边尺寸 (0–8pt)"],@[@"opacity",@"背景视图透明度 (0–1)"],@[@"fontSize",@"字体尺寸 (8–48pt)"],@[@"fontWeight",@"系统字体粗细 (-1–1)"],@[@"fontName",@"已安装字体 PostScript 名"],@[@"background",@"浅色背景"],@[@"backgroundDark",@"深色背景"],@[@"text",@"浅色文字"],@[@"textDark",@"深色文字"],@[@"tint",@"浅色图标"],@[@"tintDark",@"深色图标"],@[@"border",@"浅色描边"],@[@"borderDark",@"深色描边"]]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 3; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s==1?self.fields.count:1; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s { return s==0?@"仍受整合总开关控制。仅修改已确认的视图及其中实际文字控件；文件/表情背景没有文字时字体项不生效。":s==1?@"颜色使用 #RGB / #RGBA / #RRGGBB / #RRGGBBAA 或 transparent。留空恢复该项默认。深色未配置跟随浅色；显式设置优先于主题色表。字体不存在时保留原字体，修改字重时使用系统字体。聊天按钮不改点击行为；不修改聊天附件面板或系统键盘。":@"重置只删除本项样式，不删除主题、不修改业务开关。关闭后按逐属性所有权恢复，不覆盖宿主后来修改的值。"; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil]; c.textLabel.numberOfLines=0;
    if(p.section==0) { c.textLabel.text=@"启用本项美化"; UISwitch *s=[UISwitch new]; s.on=[WUValue(self.role) boolValue]; [s addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; c.accessoryView=s; }
    else if(p.section==2) c.textLabel.text=@"重置本项样式";
    else { NSArray *field=self.fields[p.row]; c.textLabel.text=field[1]; c.detailTextLabel.text=[WUSurfaceStyle(self.role)[field[0]] description]?:@"默认"; } return c;
}
- (void)error:(NSString *)text { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"未保存" message:text preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)toggle:(UISwitch *)s { if(!WUSave(self.role,@(s.on))) { s.on=[WUValue(self.role) boolValue]; [self error:@"业务开关保存失败"]; } }
- (BOOL)saveStyle:(NSDictionary *)style {
    id old=WUValue(@"surfaceStyles"); NSMutableDictionary *all=[(WUValidSurfaceStyles(old)?old:@{}) mutableCopy];
    if(style.count) all[self.role]=style; else [all removeObjectForKey:self.role];
    if(!WUValidSurfaceStyles(all)||!WUSave(@"surfaceStyles",all)) { [self error:@"数值/颜色无效或保存失败。需要合并surfaceStyles配置白名单。原设置保留。"]; return NO; }
    [self.tableView reloadData]; return YES;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; if(p.section==0) return;
    if(p.section==2) {
        UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"重置本项样式？" message:@"只清除当前项目的颜色、圆角和字体等样式；不修改开关或其他项目。" preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){ [self saveStyle:@{}]; }]];
        [self presentViewController:confirm animated:YES completion:nil]; return;
    }
    NSArray *field=self.fields[p.row]; NSString *key=field[0]; BOOL numeric=[@[@"radius",@"borderWidth",@"opacity",@"fontSize",@"fontWeight"] containsObject:key];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:field[1] message:@"留空恢复默认值" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text=[WUSurfaceStyle(self.role)[key] description]; f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.placeholder=numeric?@"点值 / 数值":@"#RRGGBBAA"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ NSString *text=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; NSMutableDictionary *style=[WUSurfaceStyle(self.role) mutableCopy];
        if(!text.length) [style removeObjectForKey:key]; else if(numeric) { NSScanner *scanner=[NSScanner scannerWithString:text]; double n; if(![scanner scanDouble:&n]||!scanner.isAtEnd) { [self error:@"请输入完整数值"]; return; } style[key]=@(n); } else { if([key isEqual:@"fontName"]&&![UIFont fontWithName:text size:17]) { [self error:@"该字体未安装，请使用已安装字体的PostScript名称"]; return; } style[key]=text; } [self saveStyle:style];
    }]]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
@end
@interface WUSurfaceSettings : UITableViewController @end
@implementation WUSurfaceSettings
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"逐项界面样式"; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return WUSurfaceRoles().count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p { UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; c.textLabel.text=RoleTitles()[WUSurfaceRoles()[p.row]]; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return c; }
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p { [t deselectRowAtIndexPath:p animated:YES]; WUSurfaceEditor *v=[[WUSurfaceEditor alloc] initWithStyle:UITableViewStyleInsetGrouped]; v.role=WUSurfaceRoles()[p.row]; [self.navigationController pushViewController:v animated:YES]; }
@end
void WUShowSurfaceSettings(UIViewController *owner) { WUSurfaceSettings *v=[[WUSurfaceSettings alloc] initWithStyle:UITableViewStyleInsetGrouped]; if(owner.navigationController) [owner.navigationController pushViewController:v animated:YES]; }
