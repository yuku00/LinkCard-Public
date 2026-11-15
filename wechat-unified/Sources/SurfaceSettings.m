#import "WUNeoSettings.h"
#import "WU.h"
#import "ThemeCatalog.h"
#import "ThemePrimitives.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>
static NSDictionary *RoleTitles(void) { return @{@"inputBorder":@"聊天输入框",@"noticeBorder":@"聊天系统通知",@"searchSurface":@"搜索栏",@"referSurface":@"引用卡片（原共享样式）",@"referMessageSurface":@"文本消息内引用卡片覆盖",@"textPreviewSurface":@"聊天文本预览底部工具栏",@"hostPopupSurface":@"微信纯文字提示背景（限定页面）",@"quickReplySurface":@"微信顶部快速回复横幅",@"plusSurface":@"首页右上加号菜单（暂停）",@"toastSurface":@"宿主Toast",@"timeSurface":@"聊天时间标签",@"swipeSurface":@"首页左滑菜单",@"textBubbleSurface":@"文本消息气泡",@"fileSurface":@"文件消息背景",@"emoticonSurface":@"表情消息背景",@"emoticonContentCorner":@"聊天表情本体圆角",@"chatSendSurface":@"聊天发送按钮",@"chatAttachmentSurface":@"聊天附件按钮"}; }
@interface WUSurfaceEditor : UITableViewController <UIColorPickerViewControllerDelegate>
@property(nonatomic,copy) NSString *role;
@property(nonatomic,strong) NSArray *fields;
@property(nonatomic,copy) NSString *colorKey;
@property(nonatomic,weak) UIColorPickerViewController *colorPicker;
@property(nonatomic,strong) UILabel *lightPreview;
@property(nonatomic,strong) UILabel *darkPreview;
- (BOOL)saveStyle:(NSDictionary *)style;
- (void)refreshPreview;
@end
@implementation WUSurfaceEditor
- (void)viewDidLoad { [super viewDidLoad]; WUNeoPrepareTable(self); self.title=RoleTitles()[self.role]; self.fields=@[@[@"radius",@"圆角 (0–80pt)"],@[@"borderWidth",@"描边尺寸 (0–8pt)"],@[@"opacity",@"背景视图透明度 (0–1)"],@[@"fontSize",@"字体尺寸 (8–48pt)"],@[@"fontWeight",@"系统字体粗细 (-1–1)"],@[@"fontName",@"已安装字体 PostScript 名"],@[@"background",@"浅色背景"],@[@"backgroundDark",@"深色背景"],@[@"text",@"浅色文字"],@[@"textDark",@"深色文字"],@[@"tint",@"浅色图标"],@[@"tintDark",@"深色图标"],@[@"border",@"浅色描边"],@[@"borderDark",@"深色描边"]]; if([@[@"textBubbleSurface",@"fileSurface",@"emoticonSurface"] containsObject:self.role]) self.fields=[@[@[@"widthScale",@"背景宽度比例 (0.7–1.3)"],@[@"heightScale",@"背景高度比例 (0.7–1.3)"]] arrayByAddingObjectsFromArray:self.fields]; if([self.role isEqual:@"emoticonContentCorner"]) self.fields=@[@[@"radius",@"表情本体圆角 (0–80pt，默认12)"]]; [self installPreview]; }
- (void)installPreview {
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,320,160)];
    UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisHorizontal; stack.spacing=12; stack.distribution=UIStackViewDistributionFillEqually; stack.translatesAutoresizingMaskIntoConstraints=NO;
    self.lightPreview=[UILabel new]; self.darkPreview=[UILabel new];
    for(UILabel *label in @[self.lightPreview,self.darkPreview]) { label.textAlignment=NSTextAlignmentCenter; label.numberOfLines=3; label.adjustsFontForContentSizeCategory=YES; [stack addArrangedSubview:label]; }
    self.lightPreview.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;
    self.darkPreview.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    [header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],[stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-16]]];
    self.tableView.tableHeaderView=header; [self refreshPreview];
}
- (void)refreshPreview {
    NSDictionary *style=WUSurfaceStyle(self.role);
    for(UILabel *label in @[self.lightPreview,self.darkPreview]) {
        BOOL dark=label==self.darkPreview; UITraitCollection *traits=[UITraitCollection traitCollectionWithUserInterfaceStyle:dark?UIUserInterfaceStyleDark:UIUserInterfaceStyleLight];
        label.text=dark?@"深色样式示意\n文字效果预览":@"浅色样式示意\n文字效果预览";
        label.backgroundColor=WUSurfaceColor(self.role,@"background",traits,dark?[UIColor colorWithWhite:0.16 alpha:1]:UIColor.whiteColor);
        label.textColor=WUSurfaceColor(self.role,@"text",traits,dark?UIColor.whiteColor:UIColor.blackColor);
        label.tintColor=WUSurfaceColor(self.role,@"tint",traits,UIColor.systemBlueColor);
        label.layer.cornerRadius=style[@"radius"]?[style[@"radius"] doubleValue]:12; label.clipsToBounds=YES;
        label.layer.borderWidth=[style[@"borderWidth"] doubleValue]; label.layer.borderColor=WUSurfaceColor(self.role,@"border",traits,UIColor.separatorColor).CGColor;
        label.alpha=style[@"opacity"]?[style[@"opacity"] doubleValue]:1;
        CGFloat w=style[@"widthScale"]?[style[@"widthScale"] doubleValue]:1, h=style[@"heightScale"]?[style[@"heightScale"] doubleValue]:1;
        label.transform=CGAffineTransformMakeScale(w,h);
        CGFloat size=style[@"fontSize"]?[style[@"fontSize"] doubleValue]:17;
        UIFont *font=[style[@"fontName"] length]?[UIFont fontWithName:style[@"fontName"] size:size]:nil;
        label.font=[[UIFontMetrics defaultMetrics] scaledFontForFont:(font?:[UIFont systemFontOfSize:size weight:[style[@"fontWeight"] doubleValue]]) compatibleWithTraitCollection:label.traitCollection];
        label.accessibilityLabel=dark?@"深色样式示意，不代表微信实际布局":@"浅色样式示意，不代表微信实际布局";
    }
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refreshPreview]; [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 3; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s==1?self.fields.count:1; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if([self.role isEqual:@"emoticonContentCorner"]) return s==0?@"默认关闭，同时受总开关控制。":(s==1?@"仅修改聊天中匹配视图链的表情本体显示层；不修改图片、动画或发送。预览为示意，实际效果及触摸和播放尚未真机验证。":@"重置只清除本项圆角参数，不改变开关。");
    if([self.role isEqual:@"emoticonSurface"] && s==1) return @"本项只调整消息背景，不对表情本体裁圆角，不覆盖表情面板；本体圆角另有独立设置。宽高比例仅缩放非交互背景，不改变触控或微信布局。预览为示意。";
    if(s==0) return @"同时受总开关控制。";
    if(s==1) return [@[@"textBubbleSurface",@"fileSurface",@"emoticonSurface"] containsObject:self.role] ? @"宽高比例仅缩放已识别的非交互消息背景，不改变文字、表情、触控区域或微信布局；可能与内容不完全贴合。留空恢复默认。预览为示意。" : @"留空恢复默认；深色未设置时跟随浅色。部分项目不含文字，字体设置不会生效。该项目暂不支持宽高调整。";
    return @"重置只清除本项样式，不改变开关或主题。";
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil]; c.textLabel.numberOfLines=0;
    if(p.section==0) { c.textLabel.text=@"启用本项美化"; UISwitch *s=[UISwitch new]; s.on=[WUValue(self.role) boolValue]; if([self.role isEqual:@"plusSurface"]) s.enabled=s.on; [s addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; c.accessoryView=s; }
    else if(p.section==2) c.textLabel.text=@"重置本项样式";
    else { NSArray *field=self.fields[p.row]; NSString *key=field[0]; c.textLabel.text=field[1]; c.detailTextLabel.text=[WUSurfaceStyle(self.role)[key] description]?:@"默认";
        if(![@[@"radius",@"borderWidth",@"opacity",@"fontSize",@"fontWeight",@"fontName",@"widthScale",@"heightScale"] containsObject:key]) { UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:@"选色" forState:UIControlStateNormal]; button.frame=CGRectMake(0,0,52,44); button.tag=p.row; button.accessibilityLabel=[field[1] stringByAppendingString:@"选色"]; [button addTarget:self action:@selector(colorButton:) forControlEvents:UIControlEventTouchUpInside]; c.accessoryView=button; }
    } return WUNeoCell(c,@"slider.horizontal.3");
}
- (void)error:(NSString *)text { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"未保存" message:text preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)toggle:(UISwitch *)s { if([self.role isEqual:@"plusSurface"] && s.on) { s.on=NO; return; } if(!WUSave(self.role,@(s.on))) { s.on=[WUValue(self.role) boolValue]; [self error:@"业务开关保存失败"]; } else if([self.role isEqual:@"plusSurface"]) s.enabled=NO; }
- (BOOL)saveStyle:(NSDictionary *)style {
    id old=WUValue(@"surfaceStyles"); if(old && !WUValidSurfaceStyles(old)) { [self error:@"原样式数据无效，未作更改。"]; return NO; } NSMutableDictionary *all=[(old?:@{}) mutableCopy];
    if(style.count) all[self.role]=style; else [all removeObjectForKey:self.role];
    if(!WUValidSurfaceStyles(all)||!WUSave(@"surfaceStyles",all)) { [self error:@"数值/颜色无效或文件保存失败，原设置保留。"]; return NO; }
    [self refreshPreview]; [self.tableView reloadData]; return YES;
}
- (void)colorButton:(UIButton *)sender {
    if(sender.tag<0 || (NSUInteger)sender.tag>=self.fields.count) return;
    NSArray *field=self.fields[(NSUInteger)sender.tag]; [self chooseColor:field[0] title:field[1]];
}
- (void)chooseColor:(NSString *)key title:(NSString *)title {
    if(self.presentedViewController) return;
    UIColorPickerViewController *picker=[UIColorPickerViewController new]; picker.delegate=self; picker.supportsAlpha=YES; picker.title=title;
    double rgba[4]; NSString *raw=WUSurfaceStyle(self.role)[key];
    if([raw isKindOfClass:NSString.class] && WUParseRGBA(raw.UTF8String,rgba)) picker.selectedColor=[UIColor colorWithRed:rgba[0] green:rgba[1] blue:rgba[2] alpha:rgba[3]];
    else { BOOL dark=[key hasSuffix:@"Dark"]; NSString *base=dark?[key substringToIndex:key.length-4]:key; picker.selectedColor=WUSurfaceColor(self.role,base,[UITraitCollection traitCollectionWithUserInterfaceStyle:dark?UIUserInterfaceStyleDark:UIUserInterfaceStyleLight],UIColor.systemTealColor); }
    self.colorKey=key; self.colorPicker=picker;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    if(picker!=self.colorPicker || !self.colorKey.length) return;
    NSString *key=self.colorKey; self.colorKey=nil; self.colorPicker=nil;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || !self.view.window) return;
    CGFloat r=0,g=0,b=0,a=0;
    if(![picker.selectedColor getRed:&r green:&g blue:&b alpha:&a]) return;
    NSString *hex=[NSString stringWithFormat:@"#%02X%02X%02X%02X",(unsigned)lround(MAX(0,MIN(1,r))*255),(unsigned)lround(MAX(0,MIN(1,g))*255),(unsigned)lround(MAX(0,MIN(1,b))*255),(unsigned)lround(MAX(0,MIN(1,a))*255)];
    __weak typeof(self) weak=self;
    [picker dismissViewControllerAnimated:YES completion:^{ WUSurfaceEditor *owner=weak; if(!owner || !owner.view.window || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return; NSMutableDictionary *style=[WUSurfaceStyle(owner.role) mutableCopy]; style[key]=hex; [owner saveStyle:style]; }];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; if(p.section==0) return;
    if(p.section==2) {
        UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"重置本项样式？" message:@"只清除当前项目的颜色、圆角和字体等样式；不修改开关或其他项目。" preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){ [self saveStyle:@{}]; }]];
        [self presentViewController:confirm animated:YES completion:nil]; return;
    }
    NSArray *field=self.fields[p.row]; NSString *key=field[0]; BOOL numeric=[@[@"radius",@"borderWidth",@"opacity",@"fontSize",@"fontWeight",@"widthScale",@"heightScale"] containsObject:key];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:field[1] message:@"留空恢复默认值" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text=[WUSurfaceStyle(self.role)[key] description]; f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.placeholder=numeric?@"输入数值":([key isEqual:@"fontName"]?@"例如 HelveticaNeue":@"#RRGGBB 或 #RRGGBBAA"); if(numeric && ![key isEqual:@"fontWeight"]) f.keyboardType=UIKeyboardTypeDecimalPad; }];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ NSString *text=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; NSMutableDictionary *style=[WUSurfaceStyle(self.role) mutableCopy];
        if(!text.length) [style removeObjectForKey:key]; else if(numeric) { NSScanner *scanner=[NSScanner scannerWithString:text]; double n; if(![scanner scanDouble:&n]||!scanner.isAtEnd) { [self error:@"请输入完整数值"]; return; } style[key]=@(n); } else { if([key isEqual:@"fontName"]&&![UIFont fontWithName:text size:17]) { [self error:@"该字体未安装，请使用已安装字体的PostScript名称"]; return; } style[key]=text; } [self saveStyle:style];
    }]]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
@end
@interface WUSurfaceSettings : UITableViewController @end
@implementation WUSurfaceSettings
- (void)viewDidLoad { [super viewDidLoad]; WUNeoPrepareTable(self); self.title=@"逐项界面样式"; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return WUSurfaceRoles().count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p { UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; c.textLabel.text=RoleTitles()[WUSurfaceRoles()[p.row]]; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return WUNeoCell(c,@"paintpalette"); }
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p { [t deselectRowAtIndexPath:p animated:YES]; WUSurfaceEditor *v=[[WUSurfaceEditor alloc] initWithStyle:UITableViewStyleInsetGrouped]; v.role=WUSurfaceRoles()[p.row]; [self.navigationController pushViewController:v animated:YES]; }
@end
NSString *WUSurfaceTitle(NSString *role) { return RoleTitles()[role]; }
void WUShowSurfaceEditor(UIViewController *owner, NSString *role) { if(![WUSurfaceRoles() containsObject:role] || !owner.navigationController) return; WUSurfaceEditor *v=[[WUSurfaceEditor alloc] initWithStyle:UITableViewStyleInsetGrouped]; v.role=role; [owner.navigationController pushViewController:v animated:YES]; }
void WUShowSurfaceSettings(UIViewController *owner) { WUSurfaceSettings *v=[[WUSurfaceSettings alloc] initWithStyle:UITableViewStyleInsetGrouped]; if(owner.navigationController) [owner.navigationController pushViewController:v animated:YES]; }
