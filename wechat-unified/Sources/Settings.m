#import "WUNeoSettings.h"
#import "WU.h"
#import "WUMiniAds.h"
#import "WUDiagnostics.h"
#import "WUArticleImage.h"
#import "WUDictation.h"
#import "ThemeCatalog.h"
#import "WUNative.h"
#import "MessageEntries.h"
void WUShowSurfaceEditor(UIViewController *owner, NSString *role);
NSString *WUSurfaceTitle(NSString *role);
@interface WUWords : UIViewController
@property(nonatomic,strong) UITextView *editor;
@end
@implementation WUWords
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"朋友圈屏蔽词"; WUNeoPreparePage(self);
    self.editor=[UITextView new]; self.editor.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor; self.editor.layer.cornerRadius=18; self.editor.textContainerInset=UIEdgeInsetsMake(18,16,18,16); self.editor.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; self.editor.adjustsFontForContentSizeCategory=YES;
    self.editor.text=WUValue(@"words") ?: @""; self.editor.accessibilityLabel=@"每行一个字面屏蔽词";
    UILabel *hint=[UILabel new]; hint.numberOfLines=0; hint.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; hint.text=@"每行一个字面词（不是正则），单词最多128字符，总计2048字符。设备级词表，不保存朋友圈内容。";
    hint.adjustsFontForContentSizeCategory=YES; hint.textColor=UIColor.secondaryLabelColor;
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
@interface WUSettings : UITableViewController <UISearchResultsUpdating>
@property(nonatomic,strong) NSArray<NSArray<NSString *> *> *rows;
@property(nonatomic,strong) NSArray<NSArray<NSIndexPath *> *> *searchRows;
@property(nonatomic,strong) UIStackView *overview;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UISegmentedControl *categories;
@end
@implementation WUSettings
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"微信整合 · 0.3.1"; WUNeoPrepareTable(self);
    self.rows=@[@[@"enabled",@"启用已实现功能"],@[@"articleImage",@"公众号单图 → 表情编辑（手动确认）"],@[@"voiceProgress",@"语音真实播放进度（本地）"],@[@"voiceRealDuration",@"语音：显示PCM实测时长"],@[@"voiceCarry",@"语音：分秒格式"],@[@"voiceCountdown",@"语音：倒数显示"],@[@"voiceWaveform",@"语音：真实PCM采样波形"],@[@"voiceAlways",@"语音：未播放常显波形"],@[@"voicePulse",@"语音：播放脉冲"],@[@"voiceSeek",@"语音：拖动松手定位"],@[@"ads",@"公众号列表去广告"],@[@"officialRecoFlow",@"看一看 · 推荐流过滤"],@[@"officialRecCard",@"看一看 · 推荐卡过滤"],@[@"momentsAds",@"朋友圈广告有效性过滤"],@[@"miniSplashAds",@"小程序非激励开屏广告过滤"],@[@"miniBannerAds",@"WA当前JSC · Banner展示过滤"],@[@"miniInterstitialAds",@"WA当前JSC · 插屏展示过滤"],@[@"keywords",@"朋友圈字面关键词屏蔽"],@[@"inputBorder",@"输入框描边"],@[WUDictationHideKey,@"隐藏语音转述图标"],@[WUDictationGuardKey,@"语音转述防误触"],@[@"inputPulse",@"输入呼吸灯 · 仅正在编辑"],@[@"hideHomeSearch",@"隐藏首页搜索表头（已识别布局）"],@[@"textBubbleSurface",@"文本消息气泡颜色与圆角"],@[@"fileSurface",@"文件消息背景卡片美化"],@[@"emoticonSurface",@"表情消息背景卡片美化"],@[@"noticeBorder",@"聊天系统通知描边"],@[@"separators",@"首页列表隐藏分割线"],@[@"convenientMoments",@"半屏朋友圈 · 聊天输入 rp"],@[@"chatSearch",@"聊天页头当前会话搜索"],@[@"callbackConfirm",@"通话记录回拨前确认"],@[@"antiRevoke",@"保留收到的被撤回消息（本地提示，兼容版本）"],@[@"multiRevoke",@"多选撤回自身消息（不删除）"],@[@"enhancedLinks",@"所选消息增强链接识别（手动工具）"],@[@"repeatEmoticon",@"表情标签 · 常规复读 / 长按文件下载"],@[@"mergeGroup",@"群聊相邻头像合并显示"],@[@"mergePrivate",@"私聊相邻头像合并显示"],@[@"mergeBottom",@"合并头像置底"],@[@"redReminder",@"红包前台提醒（部分定位）"],@[@"themes",@"本地多格式主题 / 独立气泡"],@[@"sunMoon",@"设置页日月开关外观"],@[@"searchSurface",@"搜索栏圆角柔和背景"],@[@"referSurface",@"引用卡片共享美化"],@[@"referMessageSurface",@"文本消息内引用卡片独立覆盖"],@[@"textPreviewSurface",@"聊天文本预览底部工具栏美化"],@[@"hostPopupSurface",@"微信纯文字提示背景（限定页面）"],@[@"quickReplySurface",@"微信顶部快速回复横幅美化"],@[@"plusSurface",@"首页右上角加号菜单美化（暂不可用）"],@[@"toastSurface",@"宿主Toast圆角背景"],@[@"timeSurface",@"聊天时间标签胶囊背景"],@[@"swipeSurface",@"首页左滑菜单圆角卡片"],@[@"chatSendSurface",@"聊天发送按钮美化"],@[@"chatAttachmentSurface",@"聊天附件按钮美化"],@[@"cardDirect",@"小店与卡包 · 直接进入卡包（实验）"],@[@"emoticonContentCorner",@"聊天表情本体圆角"]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    UISearchController *search=[[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater=self; search.obscuresBackgroundDuringPresentation=NO;
    search.searchBar.placeholder=@"搜索插件功能和本地工具";
    // Style only this plugin-owned search field; navigation continues to size and clip it.
    search.searchBar.searchBarStyle=UISearchBarStyleMinimal;
    search.searchBar.tintColor=WUNeoAccentColor();
    search.searchBar.searchTextField.backgroundColor=UIColor.tertiarySystemFillColor;
    search.searchBar.searchTextField.layer.cornerRadius=12;
    search.searchBar.searchTextField.clipsToBounds=YES;
    self.navigationItem.searchController=search; self.navigationItem.hidesSearchBarWhenScrolling=NO;
    self.definesPresentationContext=YES;
    self.tableView.backgroundColor=UIColor.systemGroupedBackgroundColor;
    self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=64;
    self.tableView.cellLayoutMarginsFollowReadableWidth=YES;
    self.tableView.separatorInset=UIEdgeInsetsMake(0,16,0,16);
    self.tableView.tintColor=UIColor.systemGreenColor;
    [self buildOverview];
    self.edgesForExtendedLayout=UIRectEdgeNone;
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:WUChanged object:nil];
}
- (void)buildOverview {
    UILabel *title=[UILabel new]; title.text=@"微信整合"; title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2]; title.adjustsFontForContentSizeCategory=YES;
    self.statusLabel=[UILabel new]; self.statusLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; self.statusLabel.adjustsFontForContentSizeCategory=YES; self.statusLabel.numberOfLines=0; self.statusLabel.textColor=UIColor.secondaryLabelColor;
    UILabel *hint=[UILabel new]; hint.text=@"按分类浏览或搜索功能；不可用的项目会说明原因。"; hint.numberOfLines=0; hint.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; hint.adjustsFontForContentSizeCategory=YES; hint.textColor=UIColor.secondaryLabelColor;
    UIStackView *card=[[UIStackView alloc] initWithArrangedSubviews:@[title,self.statusLabel,hint]]; card.axis=UILayoutConstraintAxisVertical; card.spacing=8; card.layoutMargins=UIEdgeInsetsMake(18,18,18,18); card.layoutMarginsRelativeArrangement=YES; card.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor; card.layer.cornerRadius=18; card.clipsToBounds=YES;
    self.categories=[[UISegmentedControl alloc] initWithItems:@[@"全部",@"功能",@"外观",@"工具"]]; self.categories.selectedSegmentIndex=0; self.categories.selectedSegmentTintColor=UIColor.systemGreenColor; self.categories.accessibilityLabel=@"设置分类"; [self.categories addTarget:self action:@selector(categoryChanged:) forControlEvents:UIControlEventValueChanged];
    self.overview=[[UIStackView alloc] initWithArrangedSubviews:@[card,self.categories]]; self.overview.axis=UILayoutConstraintAxisVertical; self.overview.spacing=14; self.overview.layoutMargins=UIEdgeInsetsMake(12,20,8,20); self.overview.layoutMarginsRelativeArrangement=YES;
    self.tableView.tableHeaderView=self.overview; [self updateOverview];
}
- (void)updateOverview { self.statusLabel.text=[WUValue(@"enabled") boolValue]?@"已启用 · 各功能仍可单独设置":@"已暂停 · 配置保留，可在常用中启用"; }
- (void)categoryChanged:(UISegmentedControl *)sender { [self.tableView reloadData]; }
- (BOOL)showsSection:(NSInteger)section {
    NSInteger category=self.categories.selectedSegmentIndex;
    return category==0 || (category==1 && (section==0 || section==1 || section==2 || section==3 || section==5)) || (category==2 && (section==4 || section==6)) || (category==3 && section>=7);
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; WUStyleSettingSwitches(self);
    CGFloat width=CGRectGetWidth(self.tableView.bounds);
    if(width>0) { CGSize size=[self.overview systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel]; CGRect frame=self.overview.frame; if(fabs(frame.size.width-width)>0.5 || fabs(frame.size.height-size.height)>0.5) { frame.size=CGSizeMake(width,size.height); self.overview.frame=frame; self.tableView.tableHeaderView=self.overview; } }
}
- (void)refresh { [self updateOverview]; [self.tableView reloadData]; [self.view setNeedsLayout]; }
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
// Ranges follow the existing row order so keys, defaults and handlers remain unchanged.
- (NSRange)featureRangeForSection:(NSInteger)section {
    static const NSRange ranges[] = {{0,2},{2,8},{10,8},{18,4},{22,6},{28,11},{39,16}};
    return ranges[section];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 9; }
- (NSInteger)originalRowCountForSection:(NSInteger)s { return s<7?[self featureRangeForSection:s].length:(s==7?7:1); }
- (BOOL)isSurfacePath:(NSIndexPath *)p { return p.section<7 && [WUSurfaceRoles() containsObject:self.rows[[self featureRangeForSection:p.section].location+p.row][0]]; }
- (NSArray<NSIndexPath *> *)visiblePathsForSection:(NSInteger)section {
    NSMutableArray *paths=[NSMutableArray array];
    for(NSInteger row=0;row<[self originalRowCountForSection:section];row++) {
        NSIndexPath *p=[NSIndexPath indexPathForRow:row inSection:section];
        if(![self isSurfacePath:p]) [paths addObject:p];
    }
    return paths;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { if(![self showsSection:s]) return 0; return self.searchRows ? self.searchRows[s].count : [self visiblePathsForSection:s].count; }
- (NSIndexPath *)originalPath:(NSIndexPath *)path { return self.searchRows ? self.searchRows[path.section][path.row] : [self visiblePathsForSection:path.section][path.row]; }
- (NSString *)titleForOriginalPath:(NSIndexPath *)p {
    if(p.section<7) return self.rows[[self featureRangeForSection:p.section].location+p.row][1];
    if(p.section==8) return @"查看接口检测（不含聊天数据）";
    return @[@"编辑朋友圈屏蔽词",@"识别链接 / 外部浏览器打开",@"导入和管理本地主题 / 气泡",@"账号表情分组 / 聊天工具栏",@"朋友圈缓存 / 收藏 / 安全清理",@"宿主行为 / 版本控制",@"复读标签 / 主题及用户图标 / 文件下载"][p.row];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query=[searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!query.length) { self.searchRows=nil; self.tableView.backgroundView=nil; [self.tableView reloadData]; return; }
    self.categories.selectedSegmentIndex=0;
    NSMutableArray *sections=[NSMutableArray array];
    for(NSInteger section=0;section<9;section++) {
        NSMutableArray *matches=[NSMutableArray array];
        for(NSInteger row=0;row<[self originalRowCountForSection:section];row++) {
            NSIndexPath *path=[NSIndexPath indexPathForRow:row inSection:section];
            NSString *surfaceTitle=[self isSurfacePath:path] ? WUSurfaceTitle(self.rows[[self featureRangeForSection:section].location+row][0]) : nil;
            if([[self titleForOriginalPath:path] localizedCaseInsensitiveContainsString:query] || [surfaceTitle localizedCaseInsensitiveContainsString:query]) [matches addObject:path];
        }
        [sections addObject:matches];
    }
    self.searchRows=sections;
    NSUInteger count=0; for(NSArray *matches in sections) count+=matches.count;
    UILabel *empty=[UILabel new]; empty.text=@"没有找到相关设置"; empty.textAlignment=NSTextAlignmentCenter; empty.textColor=UIColor.secondaryLabelColor; empty.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; empty.adjustsFontForContentSizeCategory=YES;
    self.tableView.backgroundView=count?nil:empty; [self.tableView reloadData];
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { if(![self showsSection:s] || (self.searchRows && !self.searchRows[s].count)) return nil; return @[@"常用",@"语音播放",@"内容过滤",@"输入与转述",@"消息与首页外观",@"聊天功能",@"主题与界面细节",@"本地工具",@"宿主适配状态"][s]; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if(self.searchRows || ![self showsSection:s]) return nil;
    if(s==6) return @"只显示有执行路径的开关；灰色表示接口、签名或安全条件尚未核验。消息动作在聊天页，执行前确认并重验上下文。头像双击的拍一拍前确认见宿主行为页，不拦截同步发送返回值。复读图标/长按文件下载见本地工具；宿主长按菜单复读、文件复读及红包跨会话定位尚未完成。链接只接手动所选消息，不自动改写气泡。";
    if(s==7) return @"不采集历史、不扫描聊天数据库、不发送消息。链接可选内置Safari组件或系统默认浏览器；不承诺强制外部Safari或绕过封禁。";
    if(s==8) return @"目标 iOS 16.6 / 微信暂按 8.0.70。签名匹配≠功能已验收。尚无真机验证，完整未完成清单见源码 STATUS.md。无 AI、无 ActionBar、无系统 Dock 修改、无奖励伪报。";
    return nil;
}
- (BOOL)available:(NSString *)key {
    if([key isEqual:@"cardDirect"]) return WUCardDirectAvailable();
    if([key isEqual:@"plusSurface"]) return NO;
    if([key isEqual:@"articleImage"]) return WUArticleImageAvailable();
    if([key isEqual:WUDictationHideKey] || [key isEqual:WUDictationGuardKey]) return WUDictationAvailable(key);
    if([key isEqual:@"inputPulse"]) return WUInputPulseAvailable();
    if([key isEqual:@"hideHomeSearch"]) return WUHomeSearchAvailable();
    if([key isEqual:@"textPreviewSurface"]) return WUTextPreviewSurfaceAvailable();
    if([key isEqual:@"hostPopupSurface"]) return WUHostPopupSurfaceAvailable();
    if([key isEqual:@"quickReplySurface"]) return WUQuickReplySurfaceAvailable();
    if([@[@"textBubbleSurface",@"fileSurface",@"emoticonSurface"] containsObject:key]) return WUCardSurfaceAvailable(key);
    if([@[@"chatSendSurface",@"chatAttachmentSurface"] containsObject:key]) return WUChatButtonSurfaceAvailable(key);
    if([key hasPrefix:@"voice"]) return WUVoiceAvailable(key);
    if([@[@"officialRecoFlow",@"officialRecCard",@"momentsAds",@"miniSplashAds",@"miniBannerAds",@"miniInterstitialAds"] containsObject:key]) return WUAdsAvailable(key);
    if([key isEqual:@"enabled"] || [key isEqual:@"sunMoon"]) return YES;
    NSDictionary *map=@{@"ads":@"BrandTL",@"keywords":@"WCFacade",@"inputBorder":@"MMGrowTextView",@"noticeBorder":@"SystemMessageCellView",@"separators":@"NewMainFrameViewController",@"themes":@"MMThemeManager",@"searchSurface":@"WCSearchBar",@"referSurface":@"MMInputMsgReferView",@"referMessageSurface":@"MMInputMsgReferView",@"plusSurface":@"MainFrameActionFloatView",@"toastSurface":@"MMToastView",@"timeSurface":@"ChatTimeCellView",@"swipeSurface":@"NewMainFrameCell",@"chatSendSurface":@"MMInputToolView",@"chatAttachmentSurface":@"MMInputToolView"};
    if(!map[key]) return WUMessageAvailable(key);
    for(NSString *line in WUHookStatus()) if([line containsString:map[key]] && [line hasSuffix:@"— installed"]) return YES;
    return NO;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    p=[self originalPath:p];
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory=YES;
    cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory=YES;
    cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    cell.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    if(p.section<7) {
        NSArray<NSString *> *sectionSymbols=@[@"switch.2",@"waveform",@"line.3.horizontal.decrease.circle",@"keyboard",@"rectangle.and.pencil.and.ellipsis",@"bubble.left.and.bubble.right",@"paintpalette"];
        cell.imageView.image=[UIImage systemImageNamed:sectionSymbols[p.section]];
        cell.imageView.tintColor=UIColor.systemGreenColor;
    }
    if(p.section<7) {
        NSUInteger row=[self featureRangeForSection:p.section].location+p.row;
        NSString *key=self.rows[row][0]; cell.textLabel.text=[self titleForOriginalPath:p];
        if([self isSurfacePath:p]) { cell.detailTextLabel.text=@"在逐项界面样式中设置"; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return WUNeoCell(cell,nil); }
        UISwitch *sw=[UISwitch new]; sw.accessibilityIdentifier=key; sw.accessibilityLabel=cell.textLabel.text;
        sw.on=WUValue(key)?[WUValue(key) boolValue]:([key hasPrefix:@"voice"] && ![@[@"voiceProgress",@"voiceCountdown"] containsObject:key]); sw.enabled=[self available:key] || sw.on;
        if([key hasPrefix:@"voice"]) cell.detailTextLabel.text=@"仅在兼容接口和气泡留有安全空间时显示；单条不满足条件则保持微信原样。支持关闭总开关。";
        if([key isEqual:@"articleImage"]) cell.detailTextLabel.text=@"仅微信已打开的mp.weixin.qq.com文章：实际长按一张已加载图片，在原菜单或12秒导航按钮选择，再确认来源与预览。只支持可核验未缩放布局的静态PNG/JPEG；GIF/APNG、iframe、未知布局拒绝。联网只在你确认后请求一张，无Cookie/账号凭据，不代表已添加表情。";
        if([key isEqual:@"enhancedLinks"]) cell.detailTextLabel.text=@"兼容版本在含可识别网址的单条消息长按菜单显示“识别链接”；也可在账号工具栏使用多选入口。需选择网址并确认域名与浏览器；签名或上下文不匹配时保留原菜单。";
        if([key isEqual:@"hostPopupSurface"]) cell.detailTextLabel.text=@"仅已核验主页/聊天页的 WeToast 非阻塞纯文字提示 backgroundView；不修改支付、授权、MMTips、系统弹窗。首次出现匹配提示后重开设置；字体仅对背景内实际文字生效。";
        if([key isEqual:@"quickReplySurface"]) cell.detailTextLabel.text=@"仅微信内 QuickReply 横幅内容视图，不修改 iOS 通知或系统权限/支付弹窗；需先出现匹配横幅后重开设置。";
        if([key isEqual:@"textPreviewSurface"]) cell.detailTextLabel.text=@"仅识别文本消息所属预览的底部工具栏，不修改系统或支付弹窗；首次需打开匹配预览再重开设置。";
        if([key isEqual:@"referMessageSurface"]) cell.detailTextLabel.text=@"仅核验为文本消息内 msgReplyView 时覆盖共享引用样式；关闭后回到共享样式或宿主原样。其他引用类型不保证覆盖。";
        if([key isEqual:@"inputPulse"]) cell.detailTextLabel.text=@"仅可见聊天输入正在编辑时动画；关闭、离窗、后台及减少动态时取消，不操作键盘焦点。";
        if([key isEqual:@"textBubbleSurface"]) cell.detailTextLabel.text=@"仅已确认的文本消息背景；接收与发送使用同一颜色，启用后原气泡图片被圆角纯色替代（无原尾巴/纹理），关闭恢复。先查看文本消息后重开设置。";
        if([@[@"fileSurface",@"emoticonSurface"] containsObject:key]) cell.detailTextLabel.text=@"仅已确认消息背景UIImageView，不改媒体、动画、下载、点击或文字。首次需查看对应消息后重开设置。";
        if([key isEqual:@"hideHomeSearch"]) cell.detailTextLabel.text=@"仅NewMainFrame真实纯搜索表头；混合或未知布局不隐藏。首次需访问首页后重开设置，关闭恢复原表头和高度。";
        if([key isEqual:WUDictationHideKey]) cell.detailTextLabel.text=@"仅隐藏聊天输入框所属语音转述图标；关闭恢复宿主状态，不修改系统键盘听写。需先打开聊天观察布局。";
        if([key isEqual:WUDictationGuardKey]) cell.detailTextLabel.text=@"未聚焦时，图标内短于0.35秒的单点按仅额外聚焦，再使用语音转述；无确认弹窗，不重放发送。取消、拖出或多触点不额外聚焦。";
        if([@[@"miniBannerAds",@"miniInterstitialAds"] containsObject:key]) cell.detailTextLabel.text=[@"默认关；仅匹配协议的当前WA JSC对象。展示被禁用时Promise以本地错误拒绝，不伪报奖励；同一对象本地拒绝8次后原路显示，广告可能出现。创建/加载仍可能联网；不覆盖WebView、其他引擎或全部小程序。关闭后下次show立即原路，无需下一次native事件；自有属性惰性恢复，已恢复旧对象不重接，重新启用须桥事件后新建对象。 " stringByAppendingString:WUMiniAdsStatus()];
        if([key isEqual:@"officialRecoFlow"]) cell.detailTextLabel.text=@"默认关闭；开启后请求隐藏看一看推荐流，会影响推荐内容，并非仅过滤广告。关闭时透传宿主原行为；效果取决于宿主接口。";
        if([key isEqual:@"officialRecCard"]) cell.detailTextLabel.text=@"默认关闭；开启后请求隐藏看一看推荐卡，会影响推荐内容，并非仅过滤广告。关闭时透传宿主原行为；效果取决于宿主接口。";
        if([key isEqual:@"cardDirect"]) cell.detailTextLabel.text=WUCardDirectAvailable()?@"实验功能：仅匹配“小店与卡包”的兼容路径；实际跳转仍需真机验证。":@"暂不可用：宿主卡包路由或入口方法缺失、签名不匹配或挂钩失败；将保留微信原行为。";
        if(!sw.enabled) cell.detailTextLabel.text=cell.detailTextLabel.text.length ? [cell.detailTextLabel.text stringByAppendingString:@" 尚未观察到可核验的宿主接口/布局；不会启用空开关。"] : @"尚未观察到可核验的宿主接口/布局；不会启用空开关";
        if([key isEqual:@"plusSurface"]) cell.detailTextLabel.text=@"暂不可用：为避免首页白屏已暂停；旧开关可关闭，样式配置保留。";
        [sw addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=sw; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else { cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; cell.textLabel.text=[self titleForOriginalPath:p]; }
    if(p.section>=7) {
        NSArray<NSString *> *symbols=@[@"text.alignleft",@"link",@"paintpalette",@"face.smiling",@"tray.full",@"slider.horizontal.3",@"arrow.2.squarepath"];
        NSString *symbol=p.section==8?@"checkmark.shield":symbols[p.row];
        cell.imageView.image=[UIImage systemImageNamed:symbol];
        cell.imageView.tintColor=UIColor.systemTealColor;
    }
    return WUNeoCell(cell,nil);
}
- (void)alert:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"微信整合" message:message preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)change:(UISwitch *)sender {
    NSString *key=sender.accessibilityIdentifier;
    if(([key isEqual:@"plusSurface"] || ([key hasPrefix:@"voice"] && !WUVoiceAvailable(key))) && sender.on) { sender.on=NO; return; }
    if(!WUSave(key,@(sender.on))) { sender.on=[WUValue(key) boolValue]; [self alert:@"保存失败，原配置保留。请检查可用空间；未以开关动画冒充保存成功。"]; }
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; p=[self originalPath:p];
    if([self isSurfacePath:p]) { WUShowSurfaceEditor(self,self.rows[[self featureRangeForSection:p.section].location+p.row][0]); return; }
    if(p.section<7) return;
    if(p.section==8) { WUShowDiagnostics(self); return; }
    if(p.row==6) { WUShowRepeatSettings(self); return; }
    if(p.row==5) { WUShowNativeSettings(self); return; }
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
    nav.modalPresentationStyle=UIModalPresentationFullScreen;
    nav.navigationBar.prefersLargeTitles=NO;
    nav.navigationBar.translucent=NO;
    UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor=UIColor.systemBackgroundColor;
    nav.navigationBar.standardAppearance=appearance;
    nav.navigationBar.scrollEdgeAppearance=appearance;
    nav.navigationBar.compactAppearance=appearance;
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
static void EnsureSettingsEntry(UIViewController *v) {
    WUEntry *entry=objc_getAssociatedObject(v,&entryKey);
    if(!entry) { entry=[WUEntry new]; entry.owner=v; entry.button=[[UIBarButtonItem alloc] initWithTitle:@"整合" style:UIBarButtonItemStylePlain target:entry action:@selector(open)]; entry.button.accessibilityLabel=@"微信整合设置"; objc_setAssociatedObject(v,&entryKey,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NSMutableArray *items=[v.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    if(![items containsObject:entry.button]) { [items addObject:entry.button]; v.navigationItem.rightBarButtonItems=items; }
}
static void Appeared(UIViewController *v,SEL s,BOOL animated) {
    ((void(*)(id,SEL,BOOL))settingsAppear)(v,s,animated);
    EnsureSettingsEntry(v);
    @try { WUEnsureSettingsListRow(v); } @catch(NSException *e) {}
}
static IMP settingLayout;
static void SettingsLayout(UIViewController *v,SEL s) { ((void(*)(id,SEL))settingLayout)(v,s); WUStyleSettingSwitches(v); if(v.view.window) EnsureSettingsEntry(v); }
void WUInstallSettings(void) { WUHook(@"NewSettingViewController",@"viewDidLayoutSubviews",NO,"v",@[],(IMP)SettingsLayout,&settingLayout); WUHook(@"NewSettingViewController",@"viewDidAppear:",NO,"v",@[[NSString stringWithUTF8String:@encode(BOOL)]],(IMP)Appeared,&settingsAppear); }
