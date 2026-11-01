#import "WU.h"
#import "MomentsCacheLogic.h"
#import "DraftMediaLogic.h"
#import <ImageIO/ImageIO.h>
static NSURL *Root(NSString *leaf) { return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject.URLByResolvingSymlinksInPath URLByAppendingPathComponent:[@"WeChatUnified/MomentsCache/" stringByAppendingString:leaf] isDirectory:YES].URLByStandardizingPath; }
static dispatch_queue_t IO(void) { static dispatch_queue_t q; static dispatch_once_t once; dispatch_once(&once,^{ q=dispatch_queue_create("org.wechatunified.moments-cache.io",DISPATCH_QUEUE_SERIAL); }); return q; }
// Accessed only on IO(); a lease keeps its index references alive until decoding/viewing ends.
static NSMutableDictionary *leases;
static NSSet *Leased(NSString *account) { NSMutableSet *ids=[NSMutableSet set]; for(NSArray *value in leases.allValues) if([value[0] isEqual:account]) [ids addObject:value[1]]; return ids; }
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
static NSString *lastError, *lastErrorAccount;
static void SetError(NSString *account, NSError *error) { lastErrorAccount=[account copy]; lastError=error.localizedDescription; }
static NSMutableSet *pending;
// Called only for host-provided entries. No fetch, no timeline mutation, no missing-page inference.
void WUMomentsCacheObserveHost(id item) {
    if(!NSThread.isMainThread || ![item isKindOfClass:NSClassFromString(@"WCDataItem")]) return;
    if(!PublicItem(item) || !WUMatches(class_getInstanceMethod([item class],NSSelectorFromString(@"contentDesc")),"@",@[])) return;
    NSString *a=WUCurrentAccount(); NSUInteger g=WUContextGeneration();
    NSString *user=Object(item,@"username"); if(![user isKindOfClass:NSString.class] || !Allowed(a,user,g)) return;
    user=[user copy]; a=[a copy];
    NSDictionary *n=WUMCacheNormalize(Tid(item),user,Object(item,@"contentDesc")); if(!n) return;
    if(!pending) pending=[NSMutableSet set]; NSArray *key=@[a,@(g),user,n[@"tid"]]; if(pending.count>=32 || [pending containsObject:key]) return;
    NSMutableArray *sources=[NSMutableArray array]; id media=Object(item,@"mediaList");
    if([media isKindOfClass:NSArray.class] && [media count]<=9) for(id m in media) {
        id path=Object(m,@"pathForExistData"); if(![path isKindOfClass:NSString.class] || ![path isAbsolutePath]) continue;
        // Main thread freezes only a path value, never retains a host media/model object.
        [sources addObject:[NSURL fileURLWithPath:[path copy]]];
    }
    [pending addObject:key]; NSArray *snapshot=[sources copy];
    dispatch_async(IO(),^{ @autoreleasepool {
        NSError *error=nil; NSMutableArray *images=[NSMutableArray array];
        for(NSURL *url in snapshot) {
            NSData *data=WUDraftMediaReadSource(url,8*1024*1024);
            CGImageSourceRef source=data?CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL):NULL;
            NSDictionary *props=source?CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)):nil;
            uint64_t w=[props[(__bridge id)kCGImagePropertyPixelWidth] unsignedLongLongValue], h=[props[(__bridge id)kCGImagePropertyPixelHeight] unsignedLongLongValue];
            BOOL ok=source && CGImageSourceGetCount(source)==1 && w && h && w<=16000000 && h<=16000000 && w*h<=16000000 && CGImageSourceGetStatus(source)==kCGImageStatusComplete;
            CGImageRef check=ok?CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@1200}):NULL;
            if(source) CFRelease(source); if(check) CGImageRelease(check);
            if(!ok || !check) { error=[NSError errorWithDomain:@"WUMomentsCache" code:2 userInfo:@{NSLocalizedDescriptionKey:@"图片源消失、无效或超限；旧缓存保留，未提交"}]; break; }
            [images addObject:data];
        }
        __block BOOL current=NO;
        // Refresh host identity on main before taking any storage lock; commit uses atomic generation only.
        dispatch_sync(dispatch_get_main_queue(),^{ current=Allowed(a,user,g); });
        if(current && !error) WUMCacheStore(Root(@"Text"),Root(@"Media"),a,n,images,NSDate.date.timeIntervalSince1970,^BOOL{ return g==WUContextGenerationSnapshot(); },&error);
        dispatch_async(dispatch_get_main_queue(),^{ [pending removeObject:key]; if(Current(a,g) && error) SetError(a,error); });
    }});
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
static BOOL Available(void) {
    if(!homepageData) return NO; Class c=NSClassFromString(@"WCDataItem");
    for(NSString *name in @[@"username",@"contentDesc"]) if(!WUMatches(class_getInstanceMethod(c,NSSelectorFromString(name)),"@",@[])) return NO;
    Method tid=class_getInstanceMethod(c,NSSelectorFromString(@"tid")); if(!WUMatches(tid,"@",@[]) && !WUMatches(tid,"Q",@[])) return NO;
    for(NSString *name in @[@"isPrivate",@"exceedsVisibleTimeRange"]) { Method m=class_getInstanceMethod(c,NSSelectorFromString(name)); if(!WUMatches(m,"B",@[]) && !WUMatches(m,"c",@[])) return NO; }
    return YES;
}
static void Notice(UIViewController *v, NSString *s) { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"朋友圈本地缓存" message:s preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [v presentViewController:a animated:YES completion:nil]; }
@interface WUMCacheBrowser : UITableViewController
@property(nonatomic,copy) NSString *account;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,strong) NSArray *rows;
@property(nonatomic,strong) id backgroundObserver;
@property(nonatomic) BOOL loading;
@property(nonatomic) BOOL cleaning;
- (BOOL)current;
- (void)reload;
@end
@interface WUMCacheDetail : UIViewController
@property(nonatomic,weak) WUMCacheBrowser *browser;
@property(nonatomic,strong) NSDictionary *row;
@property(nonatomic,copy) NSString *lease;
@end
@implementation WUMCacheDetail
- (void)dealloc { NSString *token=self.lease; if(token) dispatch_async(IO(),^{ [leases removeObjectForKey:token]; }); }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; if(self.isMovingFromParentViewController || !self.navigationController) { NSString *token=self.lease; self.lease=nil; if(token) dispatch_async(IO(),^{ [leases removeObjectForKey:token]; }); } }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"曾见内容 · 非服务器当前内容"; self.view.backgroundColor=UIColor.systemBackgroundColor;
    if(![self.browser current]) return;
    UIScrollView *scroll=[UIScrollView new]; scroll.frame=self.view.bounds; scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:scroll];
    UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=12; stack.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]]];
    UILabel *text=[UILabel new]; text.numberOfLines=0; text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; text.text=[NSString stringWithFormat:@"%@\n\n%@\n\n曾见内容，不证明真实删除；无法恢复未收到内容。评论保存/合并未实现。",self.row[@"username"],self.row[@"text"]]; [stack addArrangedSubview:text];
    NSString *account=[self.browser.account copy], *uuid=self.row[@"id"], *token=NSUUID.UUID.UUIDString; NSUInteger generation=self.browser.generation; self.lease=token;
    __weak WUMCacheDetail *weak=self;
    dispatch_async(IO(),^{ @autoreleasepool {
        if(!leases) leases=[NSMutableDictionary dictionary]; leases[token]=@[account,uuid];
        NSError *error=nil; NSMutableArray *images=[NSMutableArray array]; NSArray *media=WUDraftMediaLoad(Root(@"Media"),account,&error);
        for(NSDictionary *r in media) if([r[@"id"] isEqual:uuid]) {
            NSArray *urls=WUDraftMediaURLs(Root(@"Media"),account,r,&error);
            for(NSURL *u in urls) {
                NSData *data=WUDraftMediaReadSource(u,8*1024*1024);
                CGImageSourceRef source=data?CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL):NULL; if(!source) continue;
                CGImageRef image=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@1200,(__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES}); CFRelease(source); if(!image) continue;
                [images addObject:[UIImage imageWithCGImage:image]]; CGImageRelease(image);
            }
        }
        dispatch_async(dispatch_get_main_queue(),^{
            WUMCacheDetail *v=weak; if(!v || !Current(account,generation) || ![v.lease isEqual:token]) return;
            for(UIImage *image in images) { UIImageView *view=[[UIImageView alloc] initWithImage:image]; view.contentMode=UIViewContentModeScaleAspectFit; [view.heightAnchor constraintEqualToConstant:280].active=YES; [stack addArrangedSubview:view]; }
            if(!images.count) { UILabel *hint=[UILabel new]; hint.numberOfLines=0; hint.text=error.localizedDescription?:@"无已校验本地图片。未下载、未复制的视频/媒体不声称可恢复。"; [stack addArrangedSubview:hint]; }
        });
    }});
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:[self.row[@"favorite"] boolValue]?@"取消收藏":@"收藏" style:UIBarButtonItemStylePlain target:self action:@selector(favorite)];
}
- (void)favorite {
    if(![self.browser current] || !self.navigationItem.rightBarButtonItem.enabled) return;
    self.navigationItem.rightBarButtonItem.enabled=NO; NSString *account=[self.browser.account copy], *uuid=self.row[@"id"]; NSUInteger generation=self.browser.generation; __weak WUMCacheDetail *weak=self;
    dispatch_async(IO(),^{
        NSError *error=nil; BOOL ok=WUMCacheFavoriteChecked(Root(@"Text"),account,uuid,^BOOL{ return generation==WUContextGenerationSnapshot(); },&error);
        dispatch_async(dispatch_get_main_queue(),^{ WUMCacheDetail *v=weak; if(!v || !Current(account,generation)) return; v.navigationItem.rightBarButtonItem.enabled=YES; if(!ok) { Notice(v,error.localizedDescription); return; } [v.browser reload]; [v.navigationController popViewControllerAnimated:YES]; });
    });
}
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
- (void)reload {
    if(![self current]) { self.rows=@[]; [self.tableView reloadData]; return; }
    if(self.loading) return; self.loading=YES; NSString *account=[self.account copy]; NSUInteger generation=self.generation; __weak WUMCacheBrowser *weak=self;
    dispatch_async(IO(),^{
        NSError *error=nil; NSArray *rows=WUMCacheLoad(Root(@"Text"),account,&error);
        dispatch_async(dispatch_get_main_queue(),^{ WUMCacheBrowser *v=weak; if(!v) return; v.loading=NO; if(!Current(account,generation)) { if([v current]) [v reload]; return; } v.rows=rows?:@[]; if(error) SetError(account,error); [v.tableView reloadData]; });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s==0?1:self.rows.count; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s { if(s!=0) return nil; return [NSString stringWithFormat:@"仅缓存手动访问时宿主已提供的条目。曾见内容≠服务器当前内容，不判定真实删除。上限200条/正文索引1MiB；图片最多9张、每张8MiB、账号媒体512MiB。评论/视频保存未实现。清理仅回收本模块无引用且无浏览租约的自有图片；串行复制在途时不会清理。%@",[lastErrorAccount isEqual:self.account]?(lastError?:@""):@""]; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; c.textLabel.numberOfLines=2; c.detailTextLabel.numberOfLines=2;
    if(p.section==0) { c.textLabel.text=@"按保留天数安全清理（保留收藏）"; NSDictionary *o=Options(self.account); c.detailTextLabel.text=[NSString stringWithFormat:@"缓存%@ · 监控%lu人 · 保留%@天",[o[@"enabled"] boolValue]?@"开启":@"关闭",(unsigned long)[o[@"monitor"] count],o[@"days"]]; }
    else { NSDictionary *r=self.rows[p.row]; c.textLabel.text=[NSString stringWithFormat:@"%@%@",[r[@"favorite"] boolValue]?@"★ ":@"",r[@"username"]]; c.detailTextLabel.text=[@"曾见内容 · " stringByAppendingString:r[@"text"]]; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; } if(p.section==0 && !Available()) c.detailTextLabel.text=[c.detailTextLabel.text stringByAppendingString:@" · 宿主接口不可用"];
    return c;
}
- (void)configure {
    if(![self current]) return; NSDictionary *o=Options(self.account);
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"本账号缓存设置" message:@"仅监控列表中的账号标识（逗号分隔，排除优先）；不自动抓联系人。总开关须开启；配置/后台返回后请退出重开联系人朋友圈。关闭仅停止采集，已有缓存可浏览。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"监控账号，以逗号分隔"; f.text=[o[@"monitor"] componentsJoinedByString:@","]; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"排除账号，以逗号分隔"; f.text=[o[@"exclude"] componentsJoinedByString:@","]; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"保留天数 1–3650"; f.keyboardType=UIKeyboardTypeNumberPad; f.text=[o[@"days"] stringValue]; }];
    __weak WUMCacheBrowser *weak=self;
    for(NSNumber *enabled in @[@YES,@NO]) [a addAction:[UIAlertAction actionWithTitle:enabled.boolValue?@"保存并启用":@"保存并关闭" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        WUMCacheBrowser *v=weak; if(![v current]) return;
        if(enabled.boolValue && !Available()) { Notice(v,@"本宿主缺少已核验的主页/条目接口，未启用；原动态不受影响。已有缓存仍可浏览。"); return; }
        NSMutableDictionary *next=[o mutableCopy]; next[@"enabled"]=enabled;
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
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"清理本账号过期缓存及无引用图片？" message:@"收藏保留。先提交索引和可重试回收计划，再删除本模块自有无引用文件；共享索引引用和浏览租约保留。不会删除宿主或草稿文件，坏索引禁止回收。" preferredStyle:UIAlertControllerStyleAlert];
    __weak WUMCacheBrowser *weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"清理本地缓存" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        WUMCacheBrowser *v=weak; if(![v current] || v.cleaning) return; v.cleaning=YES;
        NSString *account=[v.account copy]; NSUInteger generation=v.generation, days=[Options(account)[@"days"] unsignedIntegerValue];
        dispatch_async(IO(),^{
            NSError *error=nil;
            NSDictionary *result=WUMCacheReclaim(Root(@"Text"),Root(@"Media"),account,days,NSDate.date.timeIntervalSince1970,Leased(account),^BOOL{ return generation==WUContextGenerationSnapshot(); },&error);
            dispatch_async(dispatch_get_main_queue(),^{
                WUMCacheBrowser *owner=weak; if(!owner) return; owner.cleaning=NO; if(!Current(account,generation)) return;
                NSString *message=[NSString stringWithFormat:@"已删除自有媒体 %@ 个，解除占用约 %@ 字节（文件已分配块统计，非设备可用空间保证）。%@",result[@"files"]?:@0,result[@"bytes"]?:@0,error?[NSString stringWithFormat:@"部分步骤失败，可重试：%@",error.localizedDescription]:@"收藏、索引共享引用及浏览中资源保留。"];
                Notice(owner,message); [owner reload];
            });
        });
    }]]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
@end
void WUShowMomentsCache(UIViewController *owner) {
    NSString *account=WUCurrentAccount(); if(!account.length || !owner.navigationController) { Notice(owner,@"无法确认账号，不读取缓存"); return; }
    WUMCacheBrowser *v=[[WUMCacheBrowser alloc] initWithStyle:UITableViewStyleInsetGrouped]; v.account=account; v.generation=WUContextGeneration(); [owner.navigationController pushViewController:v animated:YES];
}
