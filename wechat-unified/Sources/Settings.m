#import "WU.h"
@interface WUWords : UIViewController
@property(nonatomic,strong) UITextView *editor;
@end
@implementation WUWords
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"朋友圈屏蔽词"; self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.editor=[UITextView new]; self.editor.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; self.editor.adjustsFontForContentSizeCategory=YES;
    self.editor.text=WUValue(@"words") ?: @""; self.editor.accessibilityLabel=@"每行一个字面屏蔽词";
    UILabel *hint=[UILabel new]; hint.numberOfLines=0; hint.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; hint.text=@"每行一个字面词（不是正则），单词最多128字符，总计2048字符。设备级词表，不保存朋友圈内容。";
    hint.translatesAutoresizingMaskIntoConstraints=NO; self.editor.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:hint]; [self.view addSubview:self.editor];
    UILayoutGuide *g=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[hint.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],[hint.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],[hint.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],[self.editor.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:12],[self.editor.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],[self.editor.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],[self.editor.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor]]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
}
- (void)save {
    NSString *words=self.editor.text ?: @""; BOOL valid=words.length<=2048;
    for(NSString *word in [words componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) if(word.length>128) valid=NO;
    if(valid && WUSave(@"words",words)) { [self.navigationController popViewControllerAnimated:YES]; return; }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"未保存" message:@"词表超限或文件写入失败，原配置未更改。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
@end
@interface WUSettings : UITableViewController
@property(nonatomic,strong) NSArray<NSArray<NSString *> *> *rows;
@end
@implementation WUSettings
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"微信整合 · 0.3.1";
    self.rows=@[@[@"enabled",@"启用已实现功能"],@[@"voiceProgress",@"语音真实播放进度（本地）"],@[@"voiceRealDuration",@"语音：显示PCM实测时长"],@[@"voiceCarry",@"语音：分秒格式"],@[@"voiceCountdown",@"语音：倒数显示"],@[@"voiceWaveform",@"语音：真实PCM采样波形"],@[@"voiceAlways",@"语音：未播放常显波形"],@[@"voicePulse",@"语音：播放脉冲"],@[@"voiceSeek",@"语音：拖动松手定位"],@[@"ads",@"公众号列表去广告"],@[@"momentsAds",@"朋友圈广告有效性过滤"],@[@"miniSplashAds",@"小程序非激励开屏广告过滤"],@[@"keywords",@"朋友圈字面关键词屏蔽"],@[@"inputBorder",@"输入框描边"],@[@"inputPulse",@"输入呼吸灯 · 仅正在编辑"],@[@"hideHomeSearch",@"隐藏首页搜索表头（已识别布局）"],@[@"fileSurface",@"文件消息背景卡片美化"],@[@"emoticonSurface",@"表情消息背景卡片美化"],@[@"noticeBorder",@"聊天系统通知描边"],@[@"separators",@"首页列表隐藏分割线"],@[@"convenientMoments",@"半屏朋友圈 · 聊天输入 rp"],@[@"chatSearch",@"聊天页头当前会话搜索"],@[@"callbackConfirm",@"通话记录回拨前确认"],@[@"antiRevoke",@"保留收到的被撤回消息（无提示插入）"],@[@"multiRevoke",@"多选撤回自身消息（不删除）"],@[@"repeatEmoticon",@"表情标签 · 常规复读（部分）"],@[@"mergeGroup",@"群聊相邻头像合并显示"],@[@"mergePrivate",@"私聊相邻头像合并显示"],@[@"mergeBottom",@"合并头像置底"],@[@"redReminder",@"红包前台提醒（部分定位）"],@[@"themes",@"本地PNG主题 / 独立气泡"],@[@"sunMoon",@"设置页日月开关外观"],@[@"searchSurface",@"搜索栏圆角柔和背景"],@[@"referSurface",@"消息引用卡片美化"],@[@"plusSurface",@"首页右上角加号菜单美化"],@[@"toastSurface",@"宿主Toast圆角背景"],@[@"timeSurface",@"聊天时间标签胶囊背景"],@[@"swipeSurface",@"首页左滑菜单圆角卡片"]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    self.tableView.backgroundColor=UIColor.systemGroupedBackgroundColor;
    self.navigationController.navigationBar.prefersLargeTitles=YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:WUChanged object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; WUStyleSettingSwitches(self); }
- (void)refresh { [self.tableView reloadData]; [self.view setNeedsLayout]; }
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 3; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s==0?self.rows.count:(s==1?5:1); }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return @[@"本期实现（默认关闭，先小范围测试）",@"本地工具",@"宿主适配状态"][s]; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if(s==0) return @"只显示有执行路径的开关；灰色表示当前宿主缺接口/签名。消息动作在聊天页，执行前确认并重验上下文。拍一拍同步BOOL协议尚未安全适配，没有伪开关。复读长按下载/主题图标及红包跨会话定位尚未完成。";
    if(s==1) return @"不采集历史、不扫描聊天数据库、不发送消息。外部打开使用系统默认浏览器；不承诺绕过封禁。";
    return @"目标 iOS 16.6 / 微信暂按 8.0.70。签名匹配≠功能已验收。尚无真机验证，完整未完成清单见源码 STATUS.md。无 AI、无 ActionBar、无系统 Dock 修改、无奖励伪报。";
}
- (BOOL)available:(NSString *)key {
    if([key isEqual:@"inputPulse"]) return WUInputPulseAvailable();
    if([key isEqual:@"hideHomeSearch"]) return WUHomeSearchAvailable();
    if([@[@"fileSurface",@"emoticonSurface"] containsObject:key]) return WUCardSurfaceAvailable(key);
    if([key hasPrefix:@"voice"]) return WUVoiceAvailable(key);
    if([@[@"momentsAds",@"miniSplashAds"] containsObject:key]) return WUAdsAvailable(key);
    if([key isEqual:@"enabled"] || [key isEqual:@"sunMoon"]) return YES;
    NSDictionary *map=@{@"ads":@"BrandTL",@"keywords":@"WCFacade",@"inputBorder":@"MMGrowTextView",@"noticeBorder":@"SystemMessageCellView",@"separators":@"NewMainFrameViewController",@"themes":@"MMThemeManager",@"searchSurface":@"WCSearchBar",@"referSurface":@"MMInputMsgReferView",@"plusSurface":@"MainFrameActionFloatView",@"toastSurface":@"MMToastView",@"timeSurface":@"ChatTimeCellView",@"swipeSurface":@"NewMainFrameCell"};
    if(!map[key]) return WUMessageAvailable(key);
    for(NSString *line in WUHookStatus()) if([line containsString:map[key]] && [line hasSuffix:@"— installed"]) return YES;
    return NO;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0;
    if(p.section==0) {
        NSString *key=self.rows[p.row][0]; cell.textLabel.text=self.rows[p.row][1];
        UISwitch *sw=[UISwitch new]; sw.accessibilityIdentifier=key; sw.accessibilityLabel=cell.textLabel.text;
        sw.on=WUValue(key)?[WUValue(key) boolValue]:([key hasPrefix:@"voice"] && ![@[@"voiceProgress",@"voiceCountdown"] containsObject:key]); sw.enabled=[self available:key] || sw.on;
        if([key hasPrefix:@"voice"]) cell.detailTextLabel.text=@"主功能默认关，倒数默认关。WAV/CAF/M4A以系统PCM实测；SILK/AMR未适配，不显示假波形或假时长。仅正在播放且解码成功时可定位。";
        if([key isEqual:@"inputPulse"]) cell.detailTextLabel.text=@"仅可见聊天输入正在编辑时动画；关闭、离窗、后台及减少动态时取消，不操作键盘焦点。";
        if([@[@"fileSurface",@"emoticonSurface"] containsObject:key]) cell.detailTextLabel.text=@"仅已确认消息背景UIImageView，不改媒体、动画、下载、点击或文字。首次需查看对应消息后重开设置。";
        if([key isEqual:@"hideHomeSearch"]) cell.detailTextLabel.text=@"仅NewMainFrame真实纯搜索表头；混合或未知布局不隐藏。首次需访问首页后重开设置，关闭恢复原表头和高度。";
        if(!sw.enabled) cell.detailTextLabel.text=@"尚未观察到可核验的宿主接口/布局；不会启用空开关";
        [sw addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=sw; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else { cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; cell.textLabel.text=p.section==2?@"查看接口检测（不含聊天数据）":(p.row==0?@"编辑朋友圈屏蔽词":(p.row==1?@"识别链接 / 外部浏览器打开":(p.row==2?@"导入和管理本地主题 / 气泡":@"账号表情分组 / 聊天工具栏"))); }
    if(p.section==1 && p.row==4) cell.textLabel.text=@"朋友圈缓存 / 收藏 / 安全清理";
    return cell;
}
- (void)alert:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"微信整合" message:message preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)change:(UISwitch *)sender {
    NSString *key=sender.accessibilityIdentifier;
    if(!WUSave(key,@(sender.on))) { sender.on=[WUValue(key) boolValue]; [self alert:@"保存失败，原配置保留。请检查可用空间；未以开关动画冒充保存成功。"]; }
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; if(p.section==0) return;
    if(p.section==2) { [self alert:[WUHookStatus() componentsJoinedByString:@"\n"]]; return; }
    if(p.row==4) { WUShowMomentsCache(self); return; }
    if(p.row==3) { WUShowGroups(self); return; }
    if(p.row==2) { WUShowThemes(self); return; }
    if(p.row==1) { WUShowLinks(self); return; }
    [self.navigationController pushViewController:[WUWords new] animated:YES];
}
@end
void WUShowSettings(UIViewController *owner) {
    if(owner.presentedViewController) return;
    WUSettings *s=[[WUSettings alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:s];
    [owner presentViewController:nav animated:YES completion:nil];
}
@interface WUEntry : NSObject
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,strong) UIBarButtonItem *button;
- (void)open;
@end
@implementation WUEntry
- (void)open { if(self.owner.view.window) WUShowSettings(self.owner); }
@end
static IMP settingsAppear;
static char entryKey;
static void Appeared(UIViewController *v,SEL s,BOOL animated) {
    ((void(*)(id,SEL,BOOL))settingsAppear)(v,s,animated);
    WUEntry *entry=objc_getAssociatedObject(v,&entryKey);
    if(!entry) { entry=[WUEntry new]; entry.owner=v; entry.button=[[UIBarButtonItem alloc] initWithTitle:@"整合" style:UIBarButtonItemStylePlain target:entry action:@selector(open)]; entry.button.accessibilityLabel=@"微信整合设置"; objc_setAssociatedObject(v,&entryKey,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NSMutableArray *items=[v.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    if(![items containsObject:entry.button]) { [items addObject:entry.button]; v.navigationItem.rightBarButtonItems=items; }
}
static IMP settingLayout;
static void SettingsLayout(UIViewController *v,SEL s) { ((void(*)(id,SEL))settingLayout)(v,s); WUStyleSettingSwitches(v); }
void WUInstallSettings(void) { WUHook(@"NewSettingViewController",@"viewDidLayoutSubviews",NO,"v",@[],(IMP)SettingsLayout,&settingLayout); WUHook(@"NewSettingViewController",@"viewDidAppear:",NO,"v",@[[NSString stringWithUTF8String:@encode(BOOL)]],(IMP)Appeared,&settingsAppear); }
