#import "WU.h"
#import "ThemeArchive.h"
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
static NSCache *images;
static NSMapTable<UIImage *,id> *originals;
static void RestoreImageViews(UIView *v) {
    if([v isKindOfClass:UIImageView.class]) { UIImageView *iv=(UIImageView *)v; id old=[originals objectForKey:iv.image]; if(old) iv.image=old==NSNull.null?nil:old; }
    if([v isKindOfClass:UIButton.class]) { UIButton *b=(UIButton *)v; for(NSNumber *n in @[@(UIControlStateNormal),@(UIControlStateHighlighted),@(UIControlStateSelected),@(UIControlStateDisabled)]) { UIControlState s=n.unsignedIntegerValue; id old=[originals objectForKey:[b imageForState:s]]; if(old) [b setImage:old==NSNull.null?nil:old forState:s]; old=[originals objectForKey:[b backgroundImageForState:s]]; if(old) [b setBackgroundImage:old==NSNull.null?nil:old forState:s]; } }
    for(UIView *c in v.subviews) RestoreImageViews(c);
}
static void RestoreVisibleImages(void) {
    NSCAssert(NSThread.isMainThread,@"View restoration on main thread");
    @synchronized(images) { for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) if([scene isKindOfClass:UIWindowScene.class]) for(UIWindow *w in ((UIWindowScene *)scene).windows) RestoreImageViews(w); [originals removeAllObjects]; }
}
static NSDictionary *themeIndex,*bubbleIndex;
static NSString *Root(void) {
    NSString *base=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"WeChatUnified"];
    struct stat st; if(lstat(base.fileSystemRepresentation,&st)||!S_ISDIR(st.st_mode)) return nil;
    NSString *p=[base stringByAppendingPathComponent:@"Themes"]; mkdir(p.fileSystemRepresentation,0700);
    if(lstat(p.fileSystemRepresentation,&st)||!S_ISDIR(st.st_mode)) return nil; return p;
}
static BOOL PackID(NSString *s) { return [s isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:s]!=nil; }
static NSString *PackPath(NSString *s) { if(!PackID(s)) return nil; NSString *root=Root(); if(!root) return nil; NSString *p=[root stringByAppendingPathComponent:s]; struct stat st; return !lstat(p.fileSystemRepresentation,&st)&&S_ISDIR(st.st_mode)?p:nil; }
static NSData *ReadFile(NSString *p,NSUInteger limit) {
    int fd=open(p.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW); if(fd<0) return nil;
    struct stat st; if(fstat(fd,&st)||!S_ISREG(st.st_mode)||st.st_size<0||(uint64_t)st.st_size>limit) { close(fd); return nil; }
    NSMutableData *d=[NSMutableData dataWithLength:(NSUInteger)st.st_size]; NSUInteger n=0;
    while(n<d.length) { ssize_t r=read(fd,(char *)d.mutableBytes+n,d.length-n); if(r<=0) break; n+=r; } close(fd); return n==d.length?d:nil;
}
static NSDictionary *Index(NSString *selected) {
    NSString *p=PackPath(selected); if(!p) return @{}; NSMutableDictionary *out=[NSMutableDictionary dictionary];
    for(NSString *f in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:p error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
        if(![f.pathExtension.lowercaseString isEqual:@"png"]) continue;
        NSString *key=WUThemeKey(f); NSMutableArray *a=out[key]; if(!a) out[key]=a=[NSMutableArray array]; [a addObject:[p stringByAppendingPathComponent:f]];
    } return out;
}
static void Reload(void) { @synchronized(images) { [images removeAllObjects]; themeIndex=WUEnabled(@"themes")?Index(WUValue(@"themePack")):@{}; bubbleIndex=WUEnabled(@"themes")?Index(WUValue(@"bubblePack")):@{}; } }
static BOOL ValidPNG(NSData *d) {
    static const unsigned char sig[]={137,80,78,71,13,10,26,10}; if(d.length<24||d.length>8*1024*1024||memcmp(d.bytes,sig,8)) return NO;
    CGImageSourceRef src=CGImageSourceCreateWithData((__bridge CFDataRef)d,NULL); if(!src) return NO;
    NSDictionary *p=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src,0,NULL));
    NSUInteger w=[p[(id)kCGImagePropertyPixelWidth] unsignedIntegerValue],h=[p[(id)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    BOOL valid=w>0&&h>0&&w<=4096&&h<=4096&&w*h<=8*1024*1024;
    CGImageRef im=valid?CGImageSourceCreateImageAtIndex(src,0,NULL):NULL; valid=im!=NULL; if(im) CGImageRelease(im); CFRelease(src); return valid;
}
static NSString *Import(NSURL *url,NSString **failure) {
    BOOL scoped=[url startAccessingSecurityScopedResource]; NSData *d=ReadFile(url.path,32*1024*1024); if(scoped) [url stopAccessingSecurityScopedResource];
    NSError *e=nil; NSDictionary *files=nil;
    if([url.pathExtension.lowercaseString isEqual:@"zip"]) files=WUReadThemeZIP(d,&e);
    else if([url.pathExtension.lowercaseString isEqual:@"png"] && d) files=@{url.lastPathComponent:d};
    if(!files) { *failure=e.localizedDescription?:@"只支持本地PNG或ZIP（最大32MB）"; return nil; }
    NSMutableDictionary *png=[NSMutableDictionary dictionary]; NSUInteger unsupported=0;
    for(NSString *name in files) {
        if(![name.pathExtension.lowercaseString isEqual:@"png"]) { unsupported++; continue; }
        NSString *f=name.lastPathComponent.precomposedStringWithCanonicalMapping.lowercaseString;
        if([f hasPrefix:@"."] || png[f] || !ValidPNG(files[name])) { *failure=@"PNG无效、像素超限或同名资源冲突；未导入"; return nil; } png[f]=files[name];
    }
    if(!png.count) { *failure=@"没有可用PNG；SVG/CAR/XML/CSS当前不可用"; return nil; }
    NSString *root=Root(); if(!root) { *failure=@"自有资源目录不可用"; return nil; }
    NSString *uuid=NSUUID.UUID.UUIDString, *stage=[root stringByAppendingPathComponent:[@".pending-" stringByAppendingString:uuid]],*dest=[root stringByAppendingPathComponent:uuid];
    if(mkdir(stage.fileSystemRepresentation,0700)) { *failure=@"无法创建导入事务"; return nil; }
    BOOL ok=YES;
    for(NSString *f in png) if(![png[f] writeToURL:[NSURL fileURLWithPath:[stage stringByAppendingPathComponent:f]] options:NSDataWritingAtomic error:&e]) { ok=NO; break; }
    NSDictionary *meta=@{@"name":url.lastPathComponent.stringByDeletingPathExtension,@"png":@(png.count),@"unsupported":@(unsupported)};
    NSData *metadata=[NSJSONSerialization dataWithJSONObject:meta options:0 error:NULL];
    if(ok) ok=[metadata writeToURL:[NSURL fileURLWithPath:[stage stringByAppendingPathComponent:@"manifest.json"]] options:NSDataWritingAtomic error:&e];
    if(ok) ok=[NSFileManager.defaultManager moveItemAtPath:stage toPath:dest error:&e];
    if(!ok) { [NSFileManager.defaultManager removeItemAtPath:stage error:NULL]; *failure=e.localizedDescription?:@"导入失败"; return nil; } return uuid;
}
static CGFloat FileScale(NSString *s) { NSString *n=s.lastPathComponent.stringByDeletingPathExtension; return [n hasSuffix:@"@3x"]?3:([n hasSuffix:@"@2x"]?2:1); }
static UIImage *Replacement(NSString *name,UIImage *original,UITraitCollection *traits) {
    if(![name isKindOfClass:NSString.class] || !WUEnabled(@"themes")) return nil;
    NSString *key=WUThemeKey(name); BOOL dark=traits.userInterfaceStyle==UIUserInterfaceStyleDark; CGFloat scale=traits.displayScale?:UIScreen.mainScreen.scale;
    CGSize size=original.size; if(!isfinite(size.width)||!isfinite(size.height)||size.width>4096||size.height>4096||size.width*size.height*scale*scale>8*1024*1024) return nil;
    @synchronized(images) {
        BOOL independent=PackID(WUValue(@"bubblePack")); NSDictionary *idx=WUThemeBubble(key)&&independent?bubbleIndex:themeIndex;
        // Exact names win for explicitly suffixed requests. Only known _dark fallback is synthesized.
        NSArray *paths=dark&&!([key hasSuffix:@"_dark"])?idx[[key stringByAppendingString:@"_dark"]]:nil; if(!paths) paths=idx[key]; if(!paths.count) return nil;
        NSString *path=nil; CGFloat score=CGFLOAT_MAX;
        for(NSString *p in paths) { CGFloat distance=fabs(FileScale(p)-scale); if(distance<score) { score=distance; path=p; } }
        NSString *cache=[NSString stringWithFormat:@"%@|%d|%.2f|%@|%@|%ld|%ld",path,dark,scale,NSStringFromCGSize(size),NSStringFromUIEdgeInsets(original.capInsets),(long)original.resizingMode,(long)original.renderingMode];
        UIImage *result=[images objectForKey:cache]; if(result) return result;
        NSData *d=ReadFile(path,8*1024*1024); if(!d || !ValidPNG(d)) return nil;
        UIImage *png=[UIImage imageWithData:d scale:FileScale(path)]; if(!png) return nil;
        if(size.width>0&&size.height>0 && !CGSizeEqualToSize(png.size,size)) {
            UIGraphicsImageRendererFormat *fmt=[UIGraphicsImageRendererFormat defaultFormat]; fmt.scale=scale; fmt.opaque=NO;
            png=[[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *c){ [png drawInRect:(CGRect){CGPointZero,size}]; }];
        }
        if(original) { UIEdgeInsets insets=original.capInsets; if(insets.left+insets.right<png.size.width && insets.top+insets.bottom<png.size.height) png=[png resizableImageWithCapInsets:insets resizingMode:original.resizingMode]; png=[png imageWithRenderingMode:original.renderingMode]; }
        id baseline=original?[originals objectForKey:original]:nil; [originals setObject:baseline?:original?:NSNull.null forKey:png];
        [images setObject:png forKey:cache cost:(NSUInteger)(png.size.width*png.size.height*scale*scale*4)]; return png;
    }
}
static IMP namedIMP,warnIMP,bundleIMP,uiNamedIMP,uiBundleIMP;
static _Thread_local NSUInteger resourceDepth;
static UIImage *UINamed(id o,SEL s,NSString *n) { BOOL outer=resourceDepth++==0; @try { UIImage *im=((id(*)(id,SEL,id))uiNamedIMP)(o,s,n); return outer?(Replacement(n,im,UITraitCollection.currentTraitCollection)?:im):im; } @finally { resourceDepth--; } }
static UIImage *UIBundle(id o,SEL s,NSString *n,NSBundle *bundle,UITraitCollection *traits) { BOOL outer=resourceDepth++==0; @try { UIImage *im=((id(*)(id,SEL,id,id,id))uiBundleIMP)(o,s,n,bundle,traits); if(!outer || (bundle && bundle!=NSBundle.mainBundle)) return im; return Replacement(n,im,traits?:UITraitCollection.currentTraitCollection)?:im; } @finally { resourceDepth--; } }
static UIImage *Named(id o,SEL s,NSString *n) { BOOL outer=resourceDepth++==0; @try { UIImage *im=((id(*)(id,SEL,id))namedIMP)(o,s,n); return outer?(Replacement(n,im,UITraitCollection.currentTraitCollection)?:im):im; } @finally { resourceDepth--; } }
static UIImage *Warn(id o,SEL s,NSString *n,BOOL warn) { BOOL outer=resourceDepth++==0; @try { UIImage *im=((id(*)(id,SEL,id,BOOL))warnIMP)(o,s,n,warn); return outer?(Replacement(n,im,UITraitCollection.currentTraitCollection)?:im):im; } @finally { resourceDepth--; } }
static UIImage *Bundle(id o,SEL s,NSString *n,id bundle) { BOOL outer=resourceDepth++==0; @try { UIImage *im=((id(*)(id,SEL,id,id))bundleIMP)(o,s,n,bundle); if(!outer || (bundle && bundle!=NSBundle.mainBundle)) return im; return Replacement(n,im,UITraitCollection.currentTraitCollection)?:im; } @finally { resourceDepth--; } }
void WUInstallThemes(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{ images=[NSCache new]; originals=[NSMapTable weakToStrongObjectsMapTable]; images.totalCostLimit=24*1024*1024; images.countLimit=160; Reload();
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ RestoreVisibleImages(); Reload(); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification *n){ @synchronized(images) { [images removeAllObjects]; } }];
    });
    WUHook(@"UIImage",@"imageNamed:",YES,"@",@[@"@"],(IMP)UINamed,&uiNamedIMP);
    WUHook(@"UIImage",@"imageNamed:inBundle:compatibleWithTraitCollection:",YES,"@",@[@"@",@"@",@"@"],(IMP)UIBundle,&uiBundleIMP);
    WUHook(@"MMThemeManager",@"imageNamed:",NO,"@",@[@"@"],(IMP)Named,&namedIMP);
    WUHook(@"MMThemeManager",@"imageNamed:warnIfNotFound:",NO,"@",@[@"@",[NSString stringWithUTF8String:@encode(BOOL)]],(IMP)Warn,&warnIMP);
    WUHook(@"MMThemeManager",@"imageNamed:inBundle:",NO,"@",@[@"@",@"@"],(IMP)Bundle,&bundleIMP);
}

@interface WUThemes : UITableViewController <UIDocumentPickerDelegate>
@property(nonatomic,strong) NSArray<NSDictionary *> *packs;
@property(nonatomic,assign) BOOL importing;
@end
@implementation WUThemes
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"本地主题 / 气泡"; self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"导入" style:UIBarButtonItemStylePlain target:self action:@selector(pick)]; [self reload]; }
- (void)reload {
    NSMutableArray *a=[NSMutableArray array]; NSString *root=Root();
    for(NSString *s in (root?[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL]:@[])) { NSString *p=PackPath(s); if(!p) continue; NSData *d=ReadFile([p stringByAppendingPathComponent:@"manifest.json"],16384); id m=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil; if(![m isKindOfClass:NSDictionary.class] || ![m[@"name"] isKindOfClass:NSString.class]) continue; NSMutableDictionary *item=[m mutableCopy]; item[@"id"]=s; [a addObject:item]; }
    self.packs=[a sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *x,NSDictionary *y){ return [x[@"name"] localizedStandardCompare:y[@"name"]]; }]; [self.tableView reloadData];
}
- (void)message:(NSString *)text { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"本地资源" message:text preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)pick { if(self.importing) return; UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP,UTTypePNG] asCopy:YES]; p.delegate=self; p.allowsMultipleSelection=NO; [self presentViewController:p animated:YES completion:nil]; }
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if(self.importing||!urls.count) return; self.importing=YES; self.navigationItem.rightBarButtonItem.enabled=NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{ NSString *error=nil; NSString *uuid=Import(urls.firstObject,&error);
        dispatch_async(dispatch_get_main_queue(), ^{ self.importing=NO; self.navigationItem.rightBarButtonItem.enabled=YES; [self reload]; [self message:uuid?@"导入成功；请分别选择主题与气泡。只渲染PNG，其余格式标记不可用。":error]; });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s==0?2:self.packs.count; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return s==0?@"独立选择 / 恢复":@"用户本地资源（按名称排序）"; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s { return s==0?@"主设置中启用本地主题后生效。清除主题不清除独立气泡；气泡留空跟随主题。缺图回宿主原图。已显示页面可能需要重新进入；不强制重载宿主。":@"仅PNG：ZIP≤32MB，≤512项，单图≤8MB/4096边长/800万像素，总解压≤64MB。SVG/CAR/XML/CSS不渲染，未复制到资源库；不接在线仓库。扁平文件名索引，同名冲突拒绝。点击管理；删除只清本插件导入副本。"; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; c.textLabel.numberOfLines=0; c.detailTextLabel.numberOfLines=0;
    if(p.section==0) { c.textLabel.text=p.row==0?@"恢复宿主主题":@"气泡跟随主题"; return c; }
    NSDictionary *m=self.packs[p.row]; NSString *uuid=m[@"id"]; BOOL theme=[WUValue(@"themePack") isEqual:uuid],bubble=[WUValue(@"bubblePack") isEqual:uuid];
    c.textLabel.text=m[@"name"]; c.detailTextLabel.text=[NSString stringWithFormat:@"%@%@ · %@张PNG · %@项格式不可用",theme?@"主题✓ ":@"",bubble?@"气泡✓":@"",m[@"png"],m[@"unsupported"]]; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    NSDictionary *idx=Index(uuid); NSArray *paths=idx[@"cover"]?:idx[@"preview"]?:idx[@"icon"]; NSString *path=paths.firstObject;
    if(path) { NSData *d=ReadFile(path,8*1024*1024); if(d && ValidPNG(d)) { CGImageSourceRef src=CGImageSourceCreateWithData((__bridge CFDataRef)d,NULL); CGImageRef thumb=CGImageSourceCreateThumbnailAtIndex(src,0,(__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(id)kCGImageSourceThumbnailMaxPixelSize:@96}); if(thumb) { c.imageView.image=[UIImage imageWithCGImage:thumb]; CGImageRelease(thumb); } CFRelease(src); } } return c;
}
- (void)select:(NSString *)uuid key:(NSString *)key { if(!WUSave(key,uuid)) [self message:@"保存失败，选择保持不变"]; [self reload]; }
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; if(p.section==0) { [self select:@"" key:p.row==0?@"themePack":@"bubblePack"]; return; }
    NSDictionary *m=self.packs[p.row]; NSString *uuid=m[@"id"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:m[@"name"] message:@"主题与气泡分别选择；独立气泡只用于已证实气泡资源名前缀。未支持完整别名、SVG及色值文件。" preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"应用为主题" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self select:uuid key:@"themePack"]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"应用为独立气泡" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self select:uuid key:@"bubblePack"]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"删除导入副本…" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){ [self confirmDelete:uuid]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; a.popoverPresentationController.sourceView=[t cellForRowAtIndexPath:p]; a.popoverPresentationController.sourceRect=[t cellForRowAtIndexPath:p].bounds; [self presentViewController:a animated:YES completion:nil];
}
- (void)confirmDelete:(NSString *)uuid {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"删除本地副本？" message:@"不删除导入来源或宿主资源；若正在使用，先恢复相应选择。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
        for(NSString *key in @[@"themePack",@"bubblePack"]) if([WUValue(key) isEqual:uuid] && !WUSave(key,@"")) { [self message:@"选择保存失败，未删除资源"]; return; }
        NSString *p=PackPath(uuid); NSError *e=nil; if(p && ![NSFileManager.defaultManager removeItemAtPath:p error:&e]) [self message:e.localizedDescription]; Reload(); [self reload];
    }]]; [self presentViewController:a animated:YES completion:nil];
}
@end
void WUShowThemes(UIViewController *owner) { [owner.navigationController pushViewController:[[WUThemes alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES]; }
