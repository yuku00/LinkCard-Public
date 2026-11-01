#import "WU.h"
#import "ThemeArchive.h"
#import "ThemeCatalog.h"
#import "ThemeLibrary.h"
#import "ThemeRendering.h"
#import "ThemePrimitives.h"
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
static NSCache *images,*previews;
static NSMapTable<UIImage *,id> *originals;
static NSMapTable<UIImage *,NSNumber *> *imageEpochs;
static NSUInteger resourceEpoch;
static void RestoreImageViews(UIView *v) {
    if([v isKindOfClass:UIImageView.class]) { UIImageView *iv=(UIImageView *)v; id old=[originals objectForKey:iv.image]; if(old) iv.image=old==NSNull.null?nil:old; }
    if([v isKindOfClass:UIButton.class]) { UIButton *b=(UIButton *)v; for(NSNumber *n in @[@(UIControlStateNormal),@(UIControlStateHighlighted),@(UIControlStateSelected),@(UIControlStateDisabled)]) { UIControlState s=n.unsignedIntegerValue; id old=[originals objectForKey:[b imageForState:s]]; if(old) [b setImage:old==NSNull.null?nil:old forState:s]; old=[originals objectForKey:[b backgroundImageForState:s]]; if(old) [b setBackgroundImage:old==NSNull.null?nil:old forState:s]; } }
    for(UIView *c in v.subviews) RestoreImageViews(c);
}
static void RestoreVisibleImages(void) {
    NSCAssert(NSThread.isMainThread,@"View restoration on main thread");
    @synchronized(images) { for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) if([scene isKindOfClass:UIWindowScene.class]) for(UIWindow *w in ((UIWindowScene *)scene).windows) RestoreImageViews(w); /* Weak keys retain restoration for offscreen views until their images die. */ }
}
static NSDictionary *themeIndex,*bubbleIndex;
static NSString *indexedTheme,*indexedBubble;
static BOOL indexedEnabled;
static BOOL SelectionChanged(void) { return indexedEnabled!=WUEnabled(@"themes")||![indexedTheme isEqual:(WUValue(@"themePack")?:@"")]||![indexedBubble isEqual:(WUValue(@"bubblePack")?:@"")]; }
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
    NSString *path=PackPath(selected); if(!path) return @{};
    NSDictionary *files=WUThemeReadPackFiles(path,NULL); if(!files) return @{};
    NSMutableArray *cars=[NSMutableArray array]; NSMutableDictionary *light=[NSMutableDictionary dictionary],*dark=[NSMutableDictionary dictionary]; NSDictionary *aliases=@{},*catalogAssets=@{};
    for(NSString *f in [[files allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *ext=f.pathExtension.lowercaseString;
        if([ext isEqual:@"car"]) [cars addObject:f];
        if([f.lastPathComponent.lowercaseString isEqual:@"wu-theme.json"]) { NSDictionary *descriptor=WUThemeReadDescriptor(files[f],NULL); aliases=descriptor[@"aliases"]?:@{}; catalogAssets=descriptor[@"catalogAssets"]?:@{}; }
        if([@[@"css",@"xml"] containsObject:ext]) {
            BOOL night=[f.lowercaseString containsString:@"/dark/"]||[f.lowercaseString hasPrefix:@"dark/"]||[f.stringByDeletingPathExtension.lowercaseString hasSuffix:@"_dark"];
            NSDictionary *colors=WUThemeReadColors(files[f],ext,night,NULL); [light addEntriesFromDictionary:colors[@"light"]?:@{}]; [dark addEntriesFromDictionary:colors[@"dark"]?:@{}];
        }
    }
    return @{@"path":path,@"index":WUThemeResourceIndex(files.allKeys),@"aliases":aliases,@"catalogAssets":catalogAssets,@"cars":cars,@"light":light,@"dark":dark};
}
static void Reload(void) { @synchronized(images) { indexedTheme=[(WUValue(@"themePack")?:@"") copy]; indexedBubble=[(WUValue(@"bubblePack")?:@"") copy]; indexedEnabled=WUEnabled(@"themes"); resourceEpoch++; [images removeAllObjects]; [previews removeAllObjects]; WUThemeClearRenderCache(); themeIndex=WUEnabled(@"themes")?Index(WUValue(@"themePack")):@{}; bubbleIndex=WUEnabled(@"themes")?Index(WUValue(@"bubblePack")):@{}; } }
UIColor *WUThemeColor(NSString *token,UITraitCollection *traits) {
    if(!token.length||!WUEnabled(@"themes")) return nil;
    @synchronized(images) { NSString *s=traits.userInterfaceStyle==UIUserInterfaceStyleDark?themeIndex[@"dark"][token]:nil; s=s?:themeIndex[@"light"][token]; double c[4]; return WUParseRGBA(s.UTF8String,c)?[UIColor colorWithRed:c[0] green:c[1] blue:c[2] alpha:c[3]]:nil; }
}
static NSString *Import(NSURL *url,NSString *appendID,BOOL replace,NSString **failure) {
    BOOL scoped=[url startAccessingSecurityScopedResource]; NSData *d=ReadFile(url.path,32*1024*1024); if(scoped) [url stopAccessingSecurityScopedResource];
    NSError *e=nil; NSDictionary *raw=[url.pathExtension.lowercaseString isEqual:@"zip"]?WUReadThemeZIP(d,&e):(d?@{url.lastPathComponent:d}:nil);
    if(!raw) { *failure=e.localizedDescription?:@"无法读取资源，文件须≤32MB"; return nil; }
    NSMutableDictionary *incoming=[NSMutableDictionary dictionary]; NSUInteger resources=0,descriptors=0;
    for(NSString *f in raw) {
        if([f hasPrefix:@"__MACOSX/"]||[f.lastPathComponent isEqual:@".DS_Store"]) continue;
        if(!WUThemeSafePath(f)) { *failure=@"资源包含不安全或隐藏路径"; return nil; }
        BOOL descriptorFile=[f.lastPathComponent.lowercaseString isEqual:@"wu-theme.json"];
        BOOL doc=!descriptorFile&&([@[@"txt",@"md",@"json",@"plist"] containsObject:f.pathExtension.lowercaseString]||[f.lastPathComponent.lowercaseString hasPrefix:@"license"]);
        if(!doc&&!WUThemeValidateResource(f,raw[f],failure)) return nil;
        if([f.lastPathComponent.lowercaseString isEqual:@"wu-theme.json"]) descriptors++; else if(!doc) resources++;
        incoming[f]=raw[f];
    }
    if(descriptors>1||(!resources&&!appendID.length)) { *failure=@"须含可显示资源；只能有一份wu-theme.json"; return nil; }
    NSString *oldPath=appendID.length?PackPath(appendID):nil;
    NSDictionary *old=oldPath?WUThemeReadPackFiles(oldPath,&e):@{};
    if(appendID.length&&!oldPath) { *failure=@"追加目标已经删除"; return nil; }
    NSDictionary *files=old?WUThemeMergeFiles(old,incoming,replace,&e):nil;
    if(!files) { *failure=e.localizedDescription; return nil; }
    descriptors=0; for(NSString *p in files) if([p.lastPathComponent.lowercaseString isEqual:@"wu-theme.json"]) descriptors++;
    if(descriptors>1) { *failure=@"合并后有多份wu-theme.json，请只保留一份别名表"; return nil; }
    // Exercise the actual SVG renderer before committing, not just its selector presence.
    for(NSString *p in incoming) if([p.pathExtension.lowercaseString isEqual:@"svg"]) {
        NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"svg"]];
        if(![incoming[p] writeToFile:tmp atomically:YES]) { *failure=@"SVG预检临时写入失败"; return nil; }
        __block BOOL rendered=NO; void (^render)(void)=^{ rendered=WUThemeRenderFile(tmp,CGSizeMake(64,64),1,UIColor.blackColor)!=nil; };
        if(NSThread.isMainThread) render(); else dispatch_sync(dispatch_get_main_queue(),render);
        [NSFileManager.defaultManager removeItemAtPath:tmp error:NULL]; if(!rendered) { *failure=[@"SVG真实解码失败，未提交：" stringByAppendingString:p]; return nil; }
    }
    NSDictionary *descriptor=@{};
    for(NSString *p in files) if([p.lastPathComponent.lowercaseString isEqual:@"wu-theme.json"]) descriptor=WUThemeReadDescriptor(files[p],&e);
    if(!descriptor) { *failure=e.localizedDescription; return nil; }
    // CAR has no public name enumerator. Verify declared (or common preview) names with the public UIKit decoder.
    for(NSString *p in incoming) if([p.pathExtension.lowercaseString isEqual:@"car"]) {
        NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"car"]];
        if(![incoming[p] writeToFile:tmp atomically:YES]) { *failure=@"CAR预检写入失败"; return nil; }
        NSArray *names=descriptor[@"catalogAssets"][p]?:@[@"cover",@"preview",@"icon",@"chatroom_bubble_text_sender",@"chatroom_bubble_text_receiver"];
        __block BOOL rendered=NO; void (^render)(void)=^{ for(NSString *name in names) { UIImage *im=WUThemeRenderCatalog(tmp,name,[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight]); if(im) { rendered=YES; break; } } WUThemeClearRenderCache(); };
        if(NSThread.isMainThread) render(); else dispatch_sync(dispatch_get_main_queue(),render);
        [NSFileManager.defaultManager removeItemAtPath:tmp error:NULL];
        if(!rendered) { *failure=[NSString stringWithFormat:@"CAR无法渲染已知资源。请在wu-theme.json的catalogAssets[\"%@\"]给出真实asset名称；不提交不可显示的目录。",p]; return nil; }
    }
    NSString *uuid=appendID.length?appendID:NSUUID.UUID.UUIDString;
    NSMutableDictionary *meta=[(oldPath?WUThemePackMetadata(oldPath):@{}) mutableCopy]?:[NSMutableDictionary dictionary];
    if(!meta[@"name"]) meta[@"name"]=url.lastPathComponent.stringByDeletingPathExtension;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970; if(!meta[@"imported"]) meta[@"imported"]=@(now); meta[@"modified"]=@(now);
    NSUInteger bytes=0; for(NSData *data in files.allValues) bytes+=data.length; meta[@"size"]=@(bytes); meta[@"resources"]=@(files.count);
    if(!WUThemeCommitPack(Root(),uuid,files,meta,&e)) { *failure=e.localizedDescription; return nil; } return uuid;
}
static UIImage *Replacement(NSString *name,UIImage *original,UITraitCollection *traits,CGSize requested,UIColor *color) {
    if(![name isKindOfClass:NSString.class]||!WUEnabled(@"themes")) return nil;
    BOOL dark=traits.userInterfaceStyle==UIUserInterfaceStyleDark; CGFloat scale=traits.displayScale?:UIScreen.mainScreen.scale;
    CGSize size=(requested.width>0&&requested.height>0)?requested:original.size;
    if(!isfinite(size.width)||!isfinite(size.height)||size.width<0||size.height<0||size.width>4096||size.height>4096||size.width*size.height*scale*scale>8*1024*1024) return nil;
    @synchronized(images) {
        NSArray *packs=WUThemeBubble(name)&&bubbleIndex.count?@[bubbleIndex,themeIndex?:@{}]:@[themeIndex?:@{}];
        for(NSDictionary *pack in packs) for(NSString *key in WUThemeCandidates(name,dark,pack[@"aliases"])) {
            NSString *relative=WUThemeBestPath(pack[@"index"][key],scale),*path=relative?[pack[@"path"] stringByAppendingPathComponent:relative]:nil;
            NSString *cache=[NSString stringWithFormat:@"%@|%@|%d|%.2f|%@|%@|%@|%ld|%ld|%p",pack[@"path"],key,dark,scale,NSStringFromCGSize(size),[color resolvedColorWithTraitCollection:traits].description,NSStringFromUIEdgeInsets(original.capInsets),(long)original.resizingMode,(long)original.renderingMode,(__bridge void *)original];
            UIImage *result=[images objectForKey:cache]; if(result) return result;
            result=path?WUThemeRenderFile(path,size,scale,[color resolvedColorWithTraitCollection:traits]):nil;
            if(!result) for(NSString *car in pack[@"cars"]) { result=WUThemeRenderCatalog([pack[@"path"] stringByAppendingPathComponent:car],key,traits); if(result) break; }
            if(!result) continue;
            if(size.width>0&&size.height>0&&!CGSizeEqualToSize(size,result.size)) {
                UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat]; format.scale=scale; format.opaque=NO; UIImage *source=result;
                result=[[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *c){ [source drawInRect:(CGRect){CGPointZero,size}]; }];
            }
            if(original) { UIEdgeInsets insets=original.capInsets; if(insets.left+insets.right<result.size.width&&insets.top+insets.bottom<result.size.height) result=[result resizableImageWithCapInsets:insets resizingMode:original.resizingMode]; result=[result imageWithRenderingMode:original.renderingMode]; }
            id baseline=original?[originals objectForKey:original]:nil; [originals setObject:baseline?:original?:NSNull.null forKey:result]; [imageEpochs setObject:@(resourceEpoch) forKey:result];
            [images setObject:result forKey:cache cost:(NSUInteger)(result.size.width*result.size.height*result.scale*result.scale*4)]; return result;
        } return nil;
    }
}

static IMP namedIMP,warnIMP,bundleIMP,uiNamedIMP,uiBundleIMP,svgIMP,imageWindowIMP,buttonWindowIMP;
static UIImage *RestoreStaleImage(UIImage *image) {
    if(!image) return nil;
    @synchronized(images) { NSNumber *epoch=[imageEpochs objectForKey:image]; if(!epoch||epoch.unsignedIntegerValue==resourceEpoch) return image; id old=[originals objectForKey:image]; return old?(old==NSNull.null?nil:old):image; }
}
static void ImageWindow(UIImageView *v,SEL s) { ((void(*)(id,SEL))imageWindowIMP)(v,s); if(v.window) { UIImage *old=v.image,*restored=RestoreStaleImage(old); if(restored!=old) v.image=restored; } }
static void ButtonWindow(UIButton *v,SEL s) {
    ((void(*)(id,SEL))buttonWindowIMP)(v,s); if(!v.window) return;
    for(NSNumber *n in @[@(UIControlStateNormal),@(UIControlStateHighlighted),@(UIControlStateSelected),@(UIControlStateDisabled)]) { UIControlState state=n.unsignedIntegerValue; UIImage *image=[v imageForState:state],*restored=RestoreStaleImage(image); if(restored!=image) [v setImage:restored forState:state]; image=[v backgroundImageForState:state]; restored=RestoreStaleImage(image); if(restored!=image) [v setBackgroundImage:restored forState:state]; }
}
static _Thread_local NSUInteger resourceDepth;
static UIImage *SVGNamed(id o,SEL s,NSString *n,CGSize size,UIColor *color,CGFloat alpha,CGFloat angle,BOOL ignore) {
    BOOL outer=resourceDepth++==0;
    @try { UIImage *original=((id(*)(id,SEL,id,CGSize,id,CGFloat,CGFloat,BOOL))svgIMP)(o,s,n,size,color,alpha,angle,ignore);
        // shortcut: rotation/alpha coordinate contract is not proved; those requests retain the host result.
        if(!outer||alpha!=1||angle!=0) return original;
        return Replacement(n,original,UITraitCollection.currentTraitCollection,size,color)?:original;
    } @finally { resourceDepth--; }
}
static UIImage *UINamed(id o,SEL s,NSString *n) { BOOL outer=resourceDepth++==0; @try { UIImage *im=((id(*)(id,SEL,id))uiNamedIMP)(o,s,n); return outer?(Replacement(n,im,UITraitCollection.currentTraitCollection,CGSizeZero,nil)?:im):im; } @finally { resourceDepth--; } }
static UIImage *UIBundle(id o,SEL s,NSString *n,NSBundle *bundle,UITraitCollection *traits) { BOOL outer=resourceDepth++==0; @try { UIImage *im=((id(*)(id,SEL,id,id,id))uiBundleIMP)(o,s,n,bundle,traits); if(!outer || (bundle && bundle!=NSBundle.mainBundle)) return im; return Replacement(n,im,traits?:UITraitCollection.currentTraitCollection,CGSizeZero,nil)?:im; } @finally { resourceDepth--; } }
static UIImage *Named(id o,SEL s,NSString *n) { BOOL outer=resourceDepth++==0; @try { UIImage *im=((id(*)(id,SEL,id))namedIMP)(o,s,n); return outer?(Replacement(n,im,UITraitCollection.currentTraitCollection,CGSizeZero,nil)?:im):im; } @finally { resourceDepth--; } }
static UIImage *Warn(id o,SEL s,NSString *n,BOOL warn) { BOOL outer=resourceDepth++==0; @try { UIImage *im=((id(*)(id,SEL,id,BOOL))warnIMP)(o,s,n,warn); return outer?(Replacement(n,im,UITraitCollection.currentTraitCollection,CGSizeZero,nil)?:im):im; } @finally { resourceDepth--; } }
static UIImage *Bundle(id o,SEL s,NSString *n,id bundle) { BOOL outer=resourceDepth++==0; @try { UIImage *im=((id(*)(id,SEL,id,id))bundleIMP)(o,s,n,bundle); if(!outer || (bundle && bundle!=NSBundle.mainBundle)) return im; return Replacement(n,im,UITraitCollection.currentTraitCollection,CGSizeZero,nil)?:im; } @finally { resourceDepth--; } }
void WUInstallThemes(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{ images=[NSCache new]; previews=[NSCache new]; previews.countLimit=48; previews.totalCostLimit=12*1024*1024; originals=[NSMapTable weakToStrongObjectsMapTable]; imageEpochs=[NSMapTable weakToStrongObjectsMapTable]; images.totalCostLimit=24*1024*1024; images.countLimit=160; Reload();
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ if(SelectionChanged()) { RestoreVisibleImages(); Reload(); } }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification *n){ @synchronized(images) { [images removeAllObjects]; [previews removeAllObjects]; WUThemeClearRenderCache(); } }];
    });
    WUHook(@"UIImageView",@"didMoveToWindow",NO,"v",@[],(IMP)ImageWindow,&imageWindowIMP);
    WUHook(@"UIButton",@"didMoveToWindow",NO,"v",@[],(IMP)ButtonWindow,&buttonWindowIMP);
    WUHook(@"UIImage",@"imageNamed:",YES,"@",@[@"@"],(IMP)UINamed,&uiNamedIMP);
    WUHook(@"UIImage",@"imageNamed:inBundle:compatibleWithTraitCollection:",YES,"@",@[@"@",@"@",@"@"],(IMP)UIBundle,&uiBundleIMP);
    WUHook(@"MMThemeManager",@"imageNamed:",NO,"@",@[@"@"],(IMP)Named,&namedIMP);
    WUHook(@"MMThemeManager",@"imageNamed:warnIfNotFound:",NO,"@",@[@"@",[NSString stringWithUTF8String:@encode(BOOL)]],(IMP)Warn,&warnIMP);
    WUHook(@"MMThemeManager",@"svgImageNamed:size:color:alpha:angle:ignoreNotFound:",NO,"@",@[@"@",[NSString stringWithUTF8String:@encode(CGSize)],@"@",[NSString stringWithUTF8String:@encode(CGFloat)],[NSString stringWithUTF8String:@encode(CGFloat)],[NSString stringWithUTF8String:@encode(BOOL)]],(IMP)SVGNamed,&svgIMP);
    WUHook(@"MMThemeManager",@"imageNamed:inBundle:",NO,"@",@[@"@",@"@"],(IMP)Bundle,&bundleIMP);
}

@interface WUThemePreview : UIViewController
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic,strong) UISegmentedControl *mode;
@property(nonatomic,strong) UIImageView *picture;
@property(nonatomic,strong) UILabel *detail;
@end
static UIImage *PreviewImage(NSString *identifier,BOOL dark) {
    NSString *cacheKey=[NSString stringWithFormat:@"%@-%d",identifier,dark]; UIImage *cached=[previews objectForKey:cacheKey]; if(cached) return cached;
    NSDictionary *pack=Index(identifier); NSDictionary *idx=pack[@"index"];
    NSMutableArray *names=[@[@"cover",@"preview",@"screenshot",@"icon",@"chatroom_bubble_text_sender"] mutableCopy];
    for(NSArray *assets in [pack[@"catalogAssets"] allValues]) [names addObjectsFromArray:assets];
    for(NSString *k in [[idx allKeys] sortedArrayUsingSelector:@selector(compare:)]) if(WUThemeBubble(k)) [names addObject:k];
    [names addObjectsFromArray:[[idx allKeys] sortedArrayUsingSelector:@selector(compare:)]];
    UITraitCollection *traits=[UITraitCollection traitCollectionWithTraitsFromCollections:@[[UITraitCollection traitCollectionWithUserInterfaceStyle:dark?UIUserInterfaceStyleDark:UIUserInterfaceStyleLight],[UITraitCollection traitCollectionWithDisplayScale:UIScreen.mainScreen.scale]]];
    for(NSString *name in names) for(NSString *key in WUThemeCandidates(name,dark,pack[@"aliases"])) {
        NSString *relative=WUThemeBestPath(idx[key],UIScreen.mainScreen.scale);
        UIImage *im=relative?WUThemeRenderFile([pack[@"path"] stringByAppendingPathComponent:relative],CGSizeZero,UIScreen.mainScreen.scale,dark?UIColor.whiteColor:UIColor.blackColor):nil;
        if(!im) for(NSString *car in pack[@"cars"]) { im=WUThemeRenderCatalog([pack[@"path"] stringByAppendingPathComponent:car],key,traits); if(im) break; }
        if(!im) continue;
        if(im.size.width>320||im.size.height>320) { CGFloat factor=320/MAX(im.size.width,im.size.height); CGSize size=CGSizeMake(im.size.width*factor,im.size.height*factor); UIImage *source=im; im=[[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *c){ [source drawInRect:(CGRect){CGPointZero,size}]; }]; }
        [previews setObject:im forKey:cacheKey cost:(NSUInteger)(im.size.width*im.size.height*im.scale*im.scale*4)]; return im;
    } return nil;
}
@implementation WUThemePreview
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"本地资源预览"; self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.mode=[[UISegmentedControl alloc] initWithItems:@[@"浅色",@"深色"]]; self.mode.selectedSegmentIndex=0; [self.mode addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.picture=[UIImageView new]; self.picture.contentMode=UIViewContentModeScaleAspectFit; self.picture.accessibilityLabel=@"主题封面或代表气泡预览";
    self.detail=[UILabel new]; self.detail.numberOfLines=0; self.detail.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[self.mode,self.picture,self.detail]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=16; stack.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],[self.picture.heightAnchor constraintEqualToConstant:280]]]; [self refresh];
}
- (void)refresh {
    BOOL dark=self.mode.selectedSegmentIndex==1; NSDictionary *pack=Index(self.identifier); self.picture.backgroundColor=dark?UIColor.blackColor:UIColor.whiteColor; self.picture.image=PreviewImage(self.identifier,dark);
    NSMutableDictionary *palette=[pack[@"light"] mutableCopy]?:[NSMutableDictionary dictionary]; if(dark) [palette addEntriesFromDictionary:pack[@"dark"]?:@{}];
    double rgba[4]; NSString *background=palette[@"bg-1"]?:palette[@"bg-0"],*foreground=palette[@"fg-0"];
    self.detail.backgroundColor=UIColor.clearColor; self.detail.textColor=UIColor.labelColor;
    if(WUParseRGBA(background.UTF8String,rgba)) { UIColor *c=[UIColor colorWithRed:rgba[0] green:rgba[1] blue:rgba[2] alpha:rgba[3]]; self.picture.backgroundColor=c; self.detail.backgroundColor=c; }
    if(WUParseRGBA(foreground.UTF8String,rgba)) self.detail.textColor=[UIColor colorWithRed:rgba[0] green:rgba[1] blue:rgba[2] alpha:rgba[3]];
    self.detail.text=[NSString stringWithFormat:@"%@\n色表：%@\nCAR：%@。预览不是宿主聊天效果验收；无封面时可在目标资源命中时显示。",self.picture.image?@"真实本地资源渲染":@"未找到封面/代表气泡",palette.count?palette.description:@"无",@([pack[@"cars"] count])];
}
@end
@interface WUThemes : UITableViewController <UIDocumentPickerDelegate>
@property(nonatomic,strong) NSArray<NSDictionary *> *packs;
@property(nonatomic,assign) BOOL importing;
@property(nonatomic,copy) NSString *appendID;
@property(nonatomic,assign) BOOL replace;
@end
@implementation WUThemes
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"本地主题 / 气泡";
    self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc] initWithTitle:@"导入" style:UIBarButtonItemStylePlain target:self action:@selector(pickNew)],[[UIBarButtonItem alloc] initWithTitle:@"排序" style:UIBarButtonItemStylePlain target:self action:@selector(order)]]; [self reload];
}
- (NSDictionary *)options { id value=WUValue(@"themeOptions"); return WUValidThemeOptions(value)?value:@{}; }
- (void)reload {
    NSMutableArray *a=[NSMutableArray array]; NSString *root=Root();
    for(NSString *s in (root?[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL]:@[])) { NSString *p=PackPath(s); if(!p) continue; NSDictionary *m=WUThemePackMetadata(p); if(!m) continue; NSMutableDictionary *item=[m mutableCopy]; item[@"id"]=s; [a addObject:item]; }
    self.packs=WUThemeSortedPacks(a,[self options]); [self.tableView reloadData];
}
- (void)message:(NSString *)text { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"本地资源" message:text?:@"操作失败，原数据保留" preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)showMenu:(UIAlertController *)a { a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems.firstObject; [self presentViewController:a animated:YES completion:nil]; }
- (BOOL)saveOptions:(NSDictionary *)options { if(!WUSave(@"themeOptions",options)) { [self message:@"设置保存失败；请确认已合并themeOptions配置接线"]; return NO; } [self reload]; return YES; }
- (void)order {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"置顶优先；其余排序" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary *labels=@{@"name":@"名称",@"imported":@"导入时间",@"modified":@"修改时间",@"size":@"资源大小"};
    for(NSString *key in @[@"name",@"imported",@"modified",@"size"]) [a addAction:[UIAlertAction actionWithTitle:labels[key] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ NSMutableDictionary *o=[[self options] mutableCopy]; o[@"sort"]=key; [self saveOptions:o]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"切换升序 / 降序" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ NSMutableDictionary *o=[[self options] mutableCopy]; o[@"ascending"]=@(!(o[@"ascending"]?[o[@"ascending"] boolValue]:YES)); [self saveOptions:o]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"切换预览卡片 / 紧凑列表" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ NSMutableDictionary *o=[[self options] mutableCopy]; o[@"cards"]=@(![o[@"cards"] boolValue]); [self saveOptions:o]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self showMenu:a];
}
- (void)busy:(BOOL)busy { self.importing=busy; self.tableView.userInteractionEnabled=!busy; for(UIBarButtonItem *b in self.navigationItem.rightBarButtonItems) b.enabled=!busy; }
- (void)pickNew { self.appendID=nil; self.replace=NO; [self pick]; }
- (void)pick {
    if(self.importing) return;
    NSMutableArray *types=[NSMutableArray arrayWithObjects:UTTypeZIP,UTTypePNG,UTTypeJPEG,UTTypeSVG,UTTypeXML,UTTypeJSON,nil];
    for(NSString *ext in @[@"car",@"css",@"heic",@"webp"]) { UTType *type=[UTType typeWithFilenameExtension:ext]; if(type) [types addObject:type]; }
    UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES]; p.delegate=self; p.allowsMultipleSelection=NO; [self presentViewController:p animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if(self.importing||!urls.count) return; [self busy:YES]; NSString *target=self.appendID; BOOL replace=self.replace;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{ NSString *error=nil; NSString *uuid=Import(urls.firstObject,target,replace,&error);
        dispatch_async(dispatch_get_main_queue(), ^{ [self busy:NO]; if(uuid) { RestoreVisibleImages(); Reload(); [NSNotificationCenter.defaultCenter postNotificationName:WUChanged object:nil]; } [self reload]; [self message:uuid?@"导入已提交；相对目录保留。请分别选择主题与气泡。追加仅合并文件，未列文件不会删除。":error]; });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s==0?3:self.packs.count; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return s==0?@"独立选择 / 恢复 / 样式":@"本地资源 · 置顶优先"; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s { return s==0?@"主题与气泡独立；气泡留空跟随主题；缺项回退主题再回宿主。关闭立即恢复已记录的图片和视图。切换或追加资源后，已显示的宿主页面可能需重新进入；不强制重载宿主。":@"目录保持原样。ZIP≤32MB / 解包≤64MB / 单文件≤8MB / ≤510资源。SVG需WCSVGImage真实解码；CAR经系统Assets.car加载；CSS/XML仅已列WeUI字面色值，实际应用到已开启的明确视图。无在线服务。"; }
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)p { return p.section==1&&[[self options][@"cards"] boolValue]?148:UITableViewAutomaticDimension; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    if(p.section==0) { cell.textLabel.text=@[@"清除主题选择",@"气泡跟随主题",@"逐项圆角 / 颜色 / 字体 / 尺寸"][p.row]; return cell; }
    NSDictionary *pack=self.packs[p.row]; NSString *uuid=pack[@"id"]; BOOL pin=[[self options][@"pinned"] containsObject:uuid];
    cell.textLabel.text=[NSString stringWithFormat:@"%@%@",pin?@"📌 ":@"",pack[@"name"]];
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@%@ · %@项 · %.1f MB",[WUValue(@"themePack") isEqual:uuid]?@"主题 ":@"",[WUValue(@"bubblePack") isEqual:uuid]?@"独立气泡 ":@"",pack[@"resources"]?:pack[@"png"]?:@0,[pack[@"size"] doubleValue]/1024/1024];
    if([[self options][@"cards"] boolValue]) { cell.imageView.image=PreviewImage(uuid,self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark); cell.imageView.contentMode=UIViewContentModeScaleAspectFit; } return cell;
}
- (void)select:(NSString *)uuid key:(NSString *)key { if(!WUSave(key,uuid)) [self message:@"选择未保存，旧配置保留"]; else [self reload]; }
- (void)exportPack:(NSDictionary *)pack {
    [self busy:YES]; NSString *path=PackPath(pack[@"id"]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{ NSError *error=nil; NSDictionary *files=WUThemeReadPackFiles(path,&error); NSData *zip=files?WUWriteThemeZIP(files,&error):nil;
        NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"wu-export-" stringByAppendingString:NSUUID.UUID.UUIDString]],*file=[folder stringByAppendingPathComponent:@"theme.zip"];
        BOOL ok=zip&&[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]&&[zip writeToFile:file options:NSDataWritingAtomic error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ [self busy:NO]; if(!ok) { [NSFileManager.defaultManager removeItemAtPath:folder error:NULL]; [self message:error.localizedDescription]; return; }
            UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:file]] applicationActivities:nil]; share.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems.firstObject;
            share.completionWithItemsHandler=^(UIActivityType type,BOOL completed,NSArray *items,NSError *e){ [NSFileManager.defaultManager removeItemAtPath:folder error:NULL]; };
            [self presentViewController:share animated:YES completion:nil];
        });
    });
}
- (void)deletePack:(NSDictionary *)pack {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"删除此本地资源包？" message:@"不影响任何聊天数据。已选角色会清空。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
        for(NSString *key in @[@"themePack",@"bubblePack"]) if([WUValue(key) isEqual:pack[@"id"]]&&!WUSave(key,@"")) { [self message:@"清除选择失败，未删除资源包"]; return; }
        NSString *path=PackPath(pack[@"id"]); NSError *e=nil; if(path&&![NSFileManager.defaultManager removeItemAtPath:path error:&e]) { [self message:e.localizedDescription]; return; }
        RestoreVisibleImages(); Reload(); [self reload];
    }]]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)rename:(NSDictionary *)pack {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"资源包名称" message:@"仅改显示名，UUID与相对资源路径不变" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text=pack[@"name"]; }];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ NSString *name=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!name.length||name.length>100) { [self message:@"名称须为1–100字符"]; return; }
        NSError *e=nil; NSString *p=PackPath(pack[@"id"]); NSMutableDictionary *meta=[WUThemePackMetadata(p) mutableCopy]; meta[@"name"]=name; meta[@"modified"]=@(NSDate.date.timeIntervalSince1970); NSDictionary *files=WUThemeReadPackFiles(p,&e); if(!files||!WUThemeCommitPack(Root(),pack[@"id"],files,meta,&e)) [self message:e.localizedDescription]; else [self reload];
    }]]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES]; if(self.importing) return;
    if(p.section==0) { if(p.row==2) WUShowSurfaceSettings(self); else [self select:@"" key:p.row==0?@"themePack":@"bubblePack"]; return; }
    NSDictionary *pack=self.packs[p.row]; NSString *uuid=pack[@"id"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:pack[@"name"] message:@"资源追加按相对路径匹配；默认不同内容冲突则整批取消，替换须明确选择。" preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"预览浅色 / 深色" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ WUThemePreview *v=[WUThemePreview new]; v.identifier=uuid; [self.navigationController pushViewController:v animated:YES]; }]];
    for(NSArray *item in @[@[@"设为主题",@"themePack"],@[@"设为独立气泡",@"bubblePack"]]) [a addAction:[UIAlertAction actionWithTitle:item[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self select:uuid key:item[1]]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"置顶 / 取消置顶" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ NSMutableDictionary *o=[[self options] mutableCopy]; NSMutableArray *pins=[o[@"pinned"] mutableCopy]?:[NSMutableArray array]; if([pins containsObject:uuid]) [pins removeObject:uuid]; else [pins insertObject:uuid atIndex:0]; o[@"pinned"]=pins; [self saveOptions:o]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"重命名" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self rename:pack]; }]];
    for(NSNumber *replace in @[@NO,@YES]) [a addAction:[UIAlertAction actionWithTitle:replace.boolValue?@"追加并替换同路径文件…":@"追加资源（冲突取消）…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ self.appendID=uuid; self.replace=replace.boolValue; [self pick]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"导出ZIP / 存储到文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self exportPack:pack]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){ [self deletePack:pack]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self showMenu:a];
}
@end
void WUShowThemes(UIViewController *owner) { WUThemes *v=[[WUThemes alloc] initWithStyle:UITableViewStyleInsetGrouped]; if(owner.navigationController) [owner.navigationController pushViewController:v animated:YES]; else [owner presentViewController:[[UINavigationController alloc] initWithRootViewController:v] animated:YES completion:nil]; }
