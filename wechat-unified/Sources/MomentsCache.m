#import "WU.h"
#import "MomentsCacheLogic.h"
#import "DraftMediaLogic.h"
#import <ImageIO/ImageIO.h>
static NSURL *Root(NSString *leaf) { return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:[@"WeChatUnified/MomentsCache/" stringByAppendingString:leaf] isDirectory:YES].URLByResolvingSymlinksInPath; }
static NSDictionary *Options(NSString *a) { return WUAccountOptions(a)[@"momentsCache"]?:@{@"enabled":@NO,@"monitor":@[],@"exclude":@[],@"days":@30}; }
static BOOL Current(NSString *a, NSUInteger g) { return NSThread.isMainThread && a.length && [a isEqual:WUCurrentAccount()] && g==WUContextGeneration() && UIApplication.sharedApplication.applicationState==UIApplicationStateActive; }
static BOOL Allowed(NSString *a, NSString *user, NSUInteger g) { NSDictionary *o=Options(a); return Current(a,g) && [WUValue(@"enabled") boolValue] && [o[@"enabled"] boolValue] && [o[@"monitor"] containsObject:user] && ![o[@"exclude"] containsObject:user]; }
static id Object(id o, NSString *name) { SEL s=NSSelectorFromString(name); if(!WUMatches(class_getInstanceMethod([o class],s),"@",@[])) return nil; @try { return ((id(*)(id,SEL))objc_msgSend)(o,s); } @catch(NSException *e) { return nil; } }
static id Tid(id o) { id t=Object(o,@"tid"); if(t) return t; SEL s=NSSelectorFromString(@"tid"); if(WUMatches(class_getInstanceMethod([o class],s),"Q",@[])) { @try { return @(((unsigned long long(*)(id,SEL))objc_msgSend)(o,s)); } @catch(NSException *e) { return nil; } } return nil; }
static BOOL PublicItem(id item) {
    for(NSString *name in @[@"isPrivate",@"exceedsVisibleTimeRange"]) {
        SEL s=NSSelectorFromString(name); Method m=class_getInstanceMethod([item class],s);
        if(!WUMatches(m,"B",@[]) && !WUMatches(m,"c",@[])) return NO;
        @try { if(((BOOL(*)(id,SEL))objc_msgSend)(item,s)) return NO; } @catch(NSException *e) { return NO; }
    } return YES;
}
static NSString *lastError;
static NSMutableSet *pending;
// Called only for host-provided entries. No fetch, no timeline mutation, no missing-page inference.
void WUMomentsCacheObserveHost(id item) {
    if(!NSThread.isMainThread || ![item isKindOfClass:NSClassFromString(@"WCDataItem")]) return;
    if(!PublicItem(item) || !WUMatches(class_getInstanceMethod([item class],NSSelectorFromString(@"contentDesc")),"@",@[])) return;
    NSString *a=WUCurrentAccount(); NSUInteger g=WUContextGeneration();
    NSString *user=Object(item,@"username"); if(![user isKindOfClass:NSString.class] || !Allowed(a,user,g)) return;
    NSDictionary *n=WUMCacheNormalize(Tid(item),user,Object(item,@"contentDesc")); if(!n) return;
    if(!pending) pending=[NSMutableSet set]; NSArray *key=@[a,@(g),user,n[@"tid"]]; if(pending.count>=32 || [pending containsObject:key]) return;
    NSMutableArray *sources=[NSMutableArray array]; id media=Object(item,@"mediaList");
    if([media isKindOfClass:NSArray.class] && [media count]<=9) for(id m in media) {
        id path=Object(m,@"pathForExistData"); if(![path isKindOfClass:NSString.class] || ![path isAbsolutePath]) continue;
        // Existing local images only; a path is not a promise that the file survives copying.
        NSURL *u=[NSURL fileURLWithPath:path]; NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
        if([attrs[NSFileSize] unsignedLongLongValue]>8*1024*1024) continue;
        CGImageSourceRef image=CGImageSourceCreateWithURL((__bridge CFURLRef)u,NULL); if(image) { if(CGImageSourceGetCount(image)>0) [sources addObject:u]; CFRelease(image); }
    }
    [pending addObject:key];
    dispatch_async(dispatch_get_main_queue(),^{
        [pending removeObject:key]; if(!Allowed(a,user,g)) return;
        NSError *error=nil; NSDictionary *row=WUMCacheObserve(Root(@"Text"),a,n,NSDate.date.timeIntervalSince1970,&error);
        if(!row) { lastError=error.localizedDescription; return; }
        NSArray *old=WUDraftMediaLoad(Root(@"Media"),a,&error);
        if(!old) { lastError=error.localizedDescription; return; }
        BOOL exists=NO; for(NSDictionary *r in old) if([r[@"id"] isEqual:row[@"id"]]) exists=YES;
        if(sources.count && !exists && Allowed(a,user,g) && !WUDraftMediaPut(Root(@"Media"),a,row[@"id"],@"曾见朋友圈图片",@"images",sources,&error)) lastError=error.localizedDescription;
    });
}
static IMP updatedObjects,updatedNumbers,homepageData;
static char bindingKey;
static BOOL Bound(id manager) { NSArray *b=objc_getAssociatedObject(manager,&bindingKey); return b.count==2 && Current(b[0],[b[1] unsignedIntegerValue]); }
static void ObserveItems(id items) { if(!NSThread.isMainThread || ![items isKindOfClass:NSArray.class]) return; NSUInteger count=0; for(id item in items) { if(count++>=200) break; WUMomentsCacheObserveHost(item); } }
static void UpdatedObjects(id o,SEL s,id items,id max,id min,id md5) { ((void(*)(id,SEL,id,id,id,id))updatedObjects)(o,s,items,max,min,md5); @try { if(Bound(o)) ObserveItems(items); } @catch(NSException *e) { /* Host original has already completed. */ } }
static void UpdatedNumbers(id o,SEL s,id items,unsigned long long max,unsigned long long min,id md5) { ((void(*)(id,SEL,id,unsigned long long,unsigned long long,id))updatedNumbers)(o,s,items,max,min,md5); @try { if(Bound(o)) ObserveItems(items); } @catch(NSException *e) { } }
static id HomepageData(id o, SEL s) {
    // A manager is never rebound across account/generation changes; uncertain callbacks are skipped.
    if(NSThread.isMainThread && !objc_getAssociatedObject(o,&bindingKey)) { NSString *a=WUCurrentAccount(); if(a.length) objc_setAssociatedObject(o,&bindingKey,@[a,@(WUContextGeneration())],OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    id result=((id(*)(id,SEL))homepageData)(o,s);
    @try { if(Bound(o)) ObserveItems(result); } @catch(NSException *e) { }
    return result;
}
void WUInstallMomentsCache(void) {
    WUHook(@"WCHomepageMgr",@"getHomepageData",NO,"@",@[],(IMP)HomepageData,&homepageData);
    NSString *s=@"onDataUpdated:maxItemID:minItemID:reqFirstPageMd5:"; Method m=class_getInstanceMethod(NSClassFromString(@"WCHomepageMgr"),NSSelectorFromString(s));
    if(WUMatches(m,"v",@[@"@",@"@",@"@",@"@"])) WUHook(@"WCHomepageMgr",s,NO,"v",@[@"@",@"@",@"@",@"@"],(IMP)UpdatedObjects,&updatedObjects);
    else if(WUMatches(m,"v",@[@"@",@"Q",@"Q",@"@"])) WUHook(@"WCHomepageMgr",s,NO,"v",@[@"@",@"Q",@"Q",@"@"],(IMP)UpdatedNumbers,&updatedNumbers);
}
static void Notice(UIViewController *v, NSString *s) { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"朋友圈本地缓存" message:s preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [v presentViewController:a animated:YES completion:nil]; }
@interface WUMCacheBrowser : UITableViewController
@property(nonatomic,copy) NSString *account;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,strong) NSArray *rows;
@property(nonatomic,strong) id backgroundObserver;
- (BOOL)current;
- (void)reload;
@end
@interface WUMCacheDetail : UIViewController
@property(nonatomic,weak) WUMCacheBrowser *browser;
@property(nonatomic,strong) NSDictionary *row;
@end
@implementation WUMCacheDetail
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"曾见内容 · 非服务器当前内容"; self.view.backgroundColor=UIColor.systemBackgroundColor;
    if(![self.browser current]) return;
    UIScrollView *scroll=[UIScrollView new]; scroll.frame=self.view.bounds; scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:scroll];
    UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=12; stack.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]]];
    UILabel *text=[UILabel new]; text.numberOfLines=0; text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; text.text=[NSString stringWithFormat:@"%@\n\n%@\n\n曾见内容，不证明真实删除；无法恢复未收到内容。评论保存/合并未实现。",self.row[@"username"],self.row[@"text"]]; [stack addArrangedSubview:text];
    NSError *error=nil; NSArray *media=WUDraftMediaLoad(Root(@"Media"),self.browser.account,&error); BOOL shown=NO;
    for(NSDictionary *r in media) if([r[@"id"] isEqual:self.row[@"id"]]) {
        NSArray *urls=WUDraftMediaURLs(Root(@"Media"),self.browser.account,r,&error);
        for(NSURL *u in urls) {
            CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)u,NULL); if(!source) continue;
            CGImageRef image=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@1200,(__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES}); CFRelease(source); if(!image) continue;
            UIImageView *view=[[UIImageView alloc] initWithImage:[UIImage imageWithCGImage:image]]; CGImageRelease(image); view.contentMode=UIViewContentModeScaleAspectFit; [view.heightAnchor constraintEqualToConstant:280].active=YES; [stack addArrangedSubview:view]; shown=YES;
        }
    }
    if(!shown) { UILabel *hint=[UILabel new]; hint.numberOfLines=0; hint.text=error.localizedDescription?:@"无已校验本地图片。未下载、未复制的视频/媒体不声称可恢复。"; [stack addArrangedSubview:hint]; }
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:[self.row[@"favorite"] boolValue]?@"取消收藏":@"收藏" style:UIBarButtonItemStylePlain target:self action:@selector(favorite)];
}
- (void)favorite { if(![self.browser current]) return; NSError *e=nil; if(!WUMCacheFavorite(Root(@"Text"),self.browser.account,self.row[@"id"],&e)) { Notice(self,e.localizedDescription); return; } [self.browser reload]; [self.navigationController popViewControllerAnimated:YES]; }
@end
@implementation WUMCacheBrowser
- (BOOL)current { return Current(self.account,self.generation); }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"朋友圈本地缓存";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"配置" style:UIBarButtonItemStylePlain target:self action:@selector(configure)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(hide) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:WUChanged object:nil];
    [self reload];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)hide { self.rows=@[]; [self.tableView reloadData]; [self.navigationController popToRootViewControllerAnimated:NO]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }
- (void)reload { if(![self current]) { self.rows=@[]; [self.tableView reloadData]; return; } NSError *e=nil; self.rows=WUMCacheLoad(Root(@"Text"),self.account,&e); if(e) lastError=e.localizedDescription; [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s==0?1:self.rows.count; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s { if(s!=0) return nil; return [NSString stringWithFormat:@"仅缓存手动访问时宿主已提供的条目。曾见内容≠服务器当前内容，不判定真实删除。上限200条/正文索引1MiB；图片最多9张、每张8MiB、账号媒体512MiB。评论/视频保存未实现。清理仅自有索引，不回收不可变媒体文件。%@",lastError?:@""]; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; c.textLabel.numberOfLines=2; c.detailTextLabel.numberOfLines=2;
    if(p.section==0) { c.textLabel.text=@"按保留天数安全清理（保留收藏）"; NSDictionary *o=Options(self.account); c.detailTextLabel.text=[NSString stringWithFormat:@"缓存%@ · 监控%lu人 · 保留%@天",[o[@"enabled"] boolValue]?@"开启":@"关闭",(unsigned long)[o[@"monitor"] count],o[@"days"]]; }
    else { NSDictionary *r=self.rows[p.row]; c.textLabel.text=[NSString stringWithFormat:@"%@%@",[r[@"favorite"] boolValue]?@"★ ":@"",r[@"username"]]; c.detailTextLabel.text=[@"曾见内容 · " stringByAppendingString:r[@"text"]]; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; } return c;
}
- (void)configure {
    if(![self current]) return; NSDictionary *o=Options(self.account);
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"本账号缓存设置" message:@"仅监控列表中的账号标识（每行一个，排除优先）；不自动抓取任何联系人。关闭仅停止采集，已有缓存仍可浏览。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"监控账号，以逗号分隔"; f.text=[o[@"monitor"] componentsJoinedByString:@","]; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"排除账号，以逗号分隔"; f.text=[o[@"exclude"] componentsJoinedByString:@","]; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"保留天数 1–3650"; f.keyboardType=UIKeyboardTypeNumberPad; f.text=[o[@"days"] stringValue]; }];
    __weak WUMCacheBrowser *weak=self;
    for(NSNumber *enabled in @[@YES,@NO]) [a addAction:[UIAlertAction actionWithTitle:enabled.boolValue?@"保存并启用":@"保存并关闭" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        WUMCacheBrowser *v=weak; if(![v current]) return; NSMutableDictionary *next=[o mutableCopy]; next[@"enabled"]=enabled;
        for(NSUInteger i=0;i<2;i++) { NSMutableArray *users=[NSMutableArray array]; for(NSString *u in [a.textFields[i].text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",，\n"]]) { NSString *s=[u stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(s.length && ![users containsObject:s]) [users addObject:s]; } next[i==0?@"monitor":@"exclude"]=users; }
        NSString *days=a.textFields[2].text; if(!days.length || [days rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location!=NSNotFound) { Notice(v,@"保留天数无效，未保存"); return; } next[@"days"]=@([days integerValue]);
        if(!WUSaveAccountOption(v.account,@"momentsCache",next)) Notice(v,@"保存失败/配置超限，原配置保留");
        if([v.account isEqual:WUCurrentAccount()]) v.generation=WUContextGeneration(); [v reload];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; if(![self current]) { [self reload]; return; }
    if(p.section==1) { WUMCacheDetail *v=[WUMCacheDetail new]; v.row=self.rows[p.row]; v.browser=self; [self.navigationController pushViewController:v animated:YES]; return; }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"仅清理本账号过期缓存索引？" message:@"收藏保留。不会删除宿主动态、源文件或共享媒体。坏索引禁止清理；不可变文件暂不回收。" preferredStyle:UIAlertControllerStyleAlert];
    __weak WUMCacheBrowser *weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"清理本地索引" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        WUMCacheBrowser *v=weak; if(![v current]) return; NSError *e=nil;
        @synchronized(NSFileManager.defaultManager) {
            NSArray *media=WUDraftMediaLoad(Root(@"Media"),v.account,&e);
            if(!media || !WUMCacheClean(Root(@"Text"),v.account,[Options(v.account)[@"days"] unsignedIntegerValue],NSDate.date.timeIntervalSince1970,&e)) { Notice(v,e.localizedDescription); return; }
            NSArray *kept=WUMCacheLoad(Root(@"Text"),v.account,&e); if(!kept) { Notice(v,e.localizedDescription); return; }
            NSSet *ids=[NSSet setWithArray:[kept valueForKey:@"id"]];
            for(NSDictionary *r in media) if(![ids containsObject:r[@"id"]] && !WUDraftMediaDelete(Root(@"Media"),v.account,r[@"id"],&e)) break;
        }
        if(e) Notice(v,e.localizedDescription); [v reload];
    }]]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
@end
void WUShowMomentsCache(UIViewController *owner) {
    NSString *account=WUCurrentAccount(); if(!account.length || !owner.navigationController) { Notice(owner,@"无法确认账号，不读取缓存"); return; }
    WUMCacheBrowser *v=[[WUMCacheBrowser alloc] initWithStyle:UITableViewStyleInsetGrouped]; v.account=account; v.generation=WUContextGeneration(); [owner.navigationController pushViewController:v animated:YES];
}
