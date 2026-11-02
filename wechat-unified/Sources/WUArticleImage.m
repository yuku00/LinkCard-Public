#import "WUArticleImage.h"
#import "WUArticleImageFetch.h"
#import "WUImageEntry.h"
#import "WU.h"
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "WUArticleImageDOM.inc"
#include <math.h>

// A passive observer: never wins a failure dependency or cancels host touches.
@interface WUArticlePress : UILongPressGestureRecognizer
@property(nonatomic) BOOL nativeTouch;
@property(nonatomic) NSTimeInterval began;
@end
@implementation WUArticlePress
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.nativeTouch=event.type==UIEventTypeTouches && touches.count==1 && touches.anyObject.type==UITouchTypeDirect && touches.anyObject.window==self.view.window;
    self.began=NSProcessInfo.processInfo.systemUptime;
    [super touchesBegan:touches withEvent:event];
}
- (void)reset { [super reset]; self.nativeTouch=NO; self.began=0; }
@end

@interface WUArticlePreview : UIViewController
@property(nonatomic,strong) UIImage *image;
@property(nonatomic,copy) NSString *sourceText;
@property(nonatomic,copy) void (^cancel)(void), (^confirm)(void);
@end
@implementation WUArticlePreview
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.systemBackgroundColor;
    UIImageView *image=[[UIImageView alloc] initWithImage:self.image]; image.contentMode=UIViewContentModeScaleAspectFit; image.accessibilityLabel=@"所选公众号图片预览"; image.isAccessibilityElement=YES;
    UILabel *label=[UILabel new]; label.text=self.sourceText; label.numberOfLines=0; label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; label.adjustsFontForContentSizeCategory=YES;
    UIButton *open=[UIButton buttonWithType:UIButtonTypeSystem]; [open setTitle:@"打开微信表情编辑器" forState:UIControlStateNormal]; [open addTarget:self action:@selector(openEditor) forControlEvents:UIControlEventTouchUpInside];
    UIButton *cancel=[UIButton buttonWithType:UIButtonTypeSystem]; [cancel setTitle:@"取消" forState:UIControlStateNormal]; [cancel addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[image,label,open,cancel]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=12; stack.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:stack];
    UILayoutGuide *g=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:g.topAnchor constant:20],[stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-16],[stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],[image.heightAnchor constraintGreaterThanOrEqualToConstant:80],[open.heightAnchor constraintGreaterThanOrEqualToConstant:44],[cancel.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
    [image setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
}
- (void)close { if(self.cancel) self.cancel(); }
- (void)openEditor { if(self.confirm) self.confirm(); }
@end

static char ArticleKey, ObservationKey;
static NSHashTable *observers;
static BOOL installed;
static NSTimeInterval Now(void) { return NSProcessInfo.processInfo.systemUptime; }
static UIViewController *Owner(WKWebView *web) {
    UIResponder *r=web.nextResponder;
    for(NSUInteger n=0;r && n<64;n++,r=r.nextResponder) if([r isKindOfClass:UIViewController.class]) {
        UIViewController *candidate=(id)r;
        for(NSUInteger depth=0;candidate && depth<16;depth++,candidate=candidate.parentViewController)
            if([candidate.navigationController.viewControllers containsObject:candidate] && candidate.viewIfLoaded && [web isDescendantOfView:candidate.viewIfLoaded]) return candidate;
        return nil;
    }
    return nil;
}
static BOOL Geometry(WKWebView *web) {
    UIScrollView *s=web.scrollView;
    if(!web.window || web.hidden || web.alpha!=1 || !CGRectEqualToRect(web.bounds,(CGRect){CGPointZero,web.bounds.size}) || web.bounds.size.width<1 || web.bounds.size.height<1 || !CGSizeEqualToSize(s.bounds.size,web.bounds.size) || web.pageZoom!=1 || s.zoomScale!=1 || s.zooming || s.dragging || s.decelerating || !UIEdgeInsetsEqualToEdgeInsets(s.adjustedContentInset,UIEdgeInsetsZero) || !UIEdgeInsetsEqualToEdgeInsets(s.contentInset,UIEdgeInsetsZero)) return NO;
    for(UIView *v=web;v;v=v.superview) if(!CGAffineTransformIsIdentity(v.transform) || !CATransform3DIsIdentity(v.layer.transform) || !CATransform3DIsIdentity(v.layer.sublayerTransform) || v.hidden || v.alpha!=1) return NO;
    return isfinite(s.contentOffset.x) && isfinite(s.contentOffset.y) && s.contentOffset.x>=0 && s.contentOffset.y>=0;
}
@interface WUArticleImage : NSObject <UIGestureRecognizerDelegate, UIAdaptivePresentationControllerDelegate>
@property(nonatomic,weak) WKWebView *web;
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,strong) WUArticlePress *press;
@property(nonatomic,strong) UIBarButtonItem *button;
@property(nonatomic,weak) UIContextMenuInteraction *menu;
@property(nonatomic,copy) NSString *menuID, *token, *account, *source;
@property(nonatomic,copy) NSURL *article;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) CGPoint point, offset;
@property(nonatomic) CGRect bounds;
@property(nonatomic) NSTimeInterval deadline;
@property(nonatomic) BOOL watching, selected, chosen, reading, editing, opening, stopped, menuAdded, direct;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) UIViewController *prompt;
@property(nonatomic,strong) NSData *data;
@property(nonatomic,strong) WUArticleImageFetch *fetch;
- (BOOL)current:(BOOL)editing;
- (void)reset;
- (void)dispose;
- (void)choose;
- (void)verify:(NSString *)mode completion:(void (^)(NSDictionary *))completion;
@end
@implementation WUArticleImage
- (BOOL)current:(BOOL)editing {
    WKWebView *web=self.web; UIViewController *owner=self.owner;
    if(self.stopped || !self.token || !web || !owner || !WUEnabled(@"articleImage") || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || ![self.account isEqual:WUCurrentAccount()] || self.generation!=WUContextGeneration() || web.loading || ![web.URL isEqual:self.article] || !WUArticleURL(web.URL) || Owner(web)!=owner || ![owner.navigationController.viewControllers containsObject:owner]) return NO;
    if(editing) return YES; // The confirmed snapshot survives only our own editor push.
    if(Now()>=self.deadline || owner.navigationController.topViewController!=owner || !owner.viewIfLoaded.window || (owner.presentedViewController && owner.presentedViewController!=self.prompt) || !Geometry(web) || !CGPointEqualToPoint(web.scrollView.contentOffset,self.offset) || !CGRectEqualToRect(web.bounds,self.bounds)) return NO;
    return YES;
}
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if(context!=&ObservationKey) { [super observeValueForKeyPath:key ofObject:object change:change context:context]; return; }
    if(!self.token) return;
    BOOL document=object==self.web && ( [key isEqual:@"URL"] || [key isEqual:@"loading"] );
    if(!document && [change[NSKeyValueChangeOldKey] isEqual:change[NSKeyValueChangeNewKey]]) return;
    if(document || (!self.editing && !WUImageEntryOwnsNavigation(self.owner))) [self reset];
}
- (void)watch:(BOOL)on {
    if(self.watching==on) return; self.watching=on;
    for(NSString *key in @[@"URL",@"loading",@"bounds"]) {
        if(on) [self.web addObserver:self forKeyPath:key options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew context:&ObservationKey];
        else [self.web removeObserver:self forKeyPath:key context:&ObservationKey];
    }
    for(NSString *key in @[@"contentOffset",@"zoomScale",@"bounds",@"contentInset"]) {
        if(on) [self.web.scrollView addObserver:self forKeyPath:key options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew context:&ObservationKey];
        else [self.web.scrollView removeObserver:self forKeyPath:key context:&ObservationKey];
    }
}
- (void)removeButton {
    NSMutableArray *items=[self.owner.navigationItem.rightBarButtonItems mutableCopy];
    if(self.button && [items containsObject:self.button]) { [items removeObjectIdenticalTo:self.button]; self.owner.navigationItem.rightBarButtonItems=items; }
    self.button=nil;
}
- (void)reset {
    NSString *oldToken=self.token, *identifier=self.menuID;
    self.token=nil; self.selected=NO; self.chosen=NO; self.reading=NO;
    [self watch:NO]; [self.timer invalidate]; self.timer=nil;
    [self.fetch cancel]; self.fetch=nil; [self removeButton];
    if(identifier && self.menu) [self.menu updateVisibleMenuWithBlock:^UIMenu *(UIMenu *old) {
        NSMutableArray *items=[old.children mutableCopy];
        for(UIMenuElement *item in old.children) if([item isKindOfClass:UIAction.class] && [((UIAction *)item).identifier isEqual:identifier]) [items removeObjectIdenticalTo:item];
        return [old menuByReplacingChildren:items];
    }];
    self.menu=nil; self.menuID=nil; self.menuAdded=NO;
    if(self.editing || self.opening) WUCancelImageDataEditor(self.owner);
    self.editing=NO; self.opening=NO;
    if(self.prompt && self.owner.presentedViewController==self.prompt && !self.prompt.presentedViewController) [self.prompt dismissViewControllerAnimated:NO completion:nil];
    self.prompt=nil; self.data=nil; self.account=nil; self.source=nil; self.article=nil;
    if(oldToken && self.web) [self.web callAsyncJavaScript:ArticleScript arguments:@{@"mode":@"clear",@"token":oldToken} inFrame:nil inContentWorld:[WKContentWorld worldWithName:@"org.wechatunified.article-image"] completionHandler:nil];
}
- (void)dispose {
    [self reset]; self.stopped=YES; [self.web removeGestureRecognizer:self.press]; self.press=nil;
    objc_setAssociatedObject(self.web,&ArticleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController { if(presentationController.presentedViewController==self.prompt) [self reset]; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }
- (void)pressed:(WUArticlePress *)press {
    if(press!=self.press || !press.nativeTouch) return;
    if(press.state==UIGestureRecognizerStateChanged) {
        CGPoint p=[press locationInView:self.web]; if(hypot(p.x-self.point.x,p.y-self.point.y)>6) [self reset]; return;
    }
    if(press.state==UIGestureRecognizerStateCancelled || press.state==UIGestureRecognizerStateFailed) { [self reset]; return; }
    if(press.state!=UIGestureRecognizerStateBegan || Now()-press.began<0.5 || Now()-press.began>3 || !Geometry(self.web) || self.web.loading || !WUArticleURL(self.web.URL) || !WUEnabled(@"articleImage")) return;
    UIViewController *owner=Owner(self.web);
    if(!owner || owner.navigationController.topViewController!=owner || owner.presentedViewController) return;
    for(WUArticleImage *other in observers.allObjects) if(other!=self) [other reset];
    [self reset]; self.owner=owner; self.account=WUCurrentAccount(); if(!self.account.length) return;
    self.token=NSUUID.UUID.UUIDString; self.menuID=[@"org.wechatunified.article." stringByAppendingString:self.token];
    self.generation=WUContextGeneration(); self.article=self.web.URL; self.point=[press locationInView:self.web]; self.offset=self.web.scrollView.contentOffset; self.bounds=self.web.bounds; self.deadline=Now()+12;
    [self watch:YES]; __weak WUArticleImage *weak=self;
    self.timer=[NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer){
        WUArticleImage *op=weak;
        if(![op current:op.editing] || (op.editing && !WUImageEntryOwnsNavigation(op.owner))) [op reset];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self verify:@"select" completion:^(NSDictionary *result){
        WUArticleImage *op=weak; if(!result || !op) return;
        op.source=result[@"source"]; op.direct=[result[@"direct"] boolValue]; op.selected=YES;
        [op offer];
    }];
}
- (void)verify:(NSString *)mode completion:(void (^)(NSDictionary *))completion {
    if(![self current:NO]) { [self reset]; return; }
    NSString *token=self.token; WKWebView *web=self.web;
    NSDictionary *args=@{@"mode":mode,@"token":token,@"article":self.article.absoluteString,@"x":@(self.point.x),@"y":@(self.point.y),@"width":@(self.bounds.size.width),@"height":@(self.bounds.size.height),@"offsetX":@(self.offset.x),@"offsetY":@(self.offset.y)};
    __weak WUArticleImage *weak=self;
    [web callAsyncJavaScript:ArticleScript arguments:args inFrame:nil inContentWorld:[WKContentWorld worldWithName:@"org.wechatunified.article-image"] completionHandler:^(id value,NSError *error){
        WUArticleImage *op=weak;
        if(!op || ![op.token isEqual:token] || op.web!=web) return;
        if(error || ![op current:NO] || ![value isKindOfClass:NSDictionary.class]) { [op reset]; return; }
        NSDictionary *d=value; id source=d[@"source"], direct=d[@"direct"];
        if(![d[@"token"] isEqual:token] || ![d[@"article"] isEqual:op.article.absoluteString] || ![source isKindOfClass:NSString.class] || ![direct isKindOfClass:NSNumber.class] || !([direct boolValue]?[source isEqual:@"embedded"]:WUArticleImageURL([NSURL URLWithString:source],op.article)) || (op.selected && (![source isEqual:op.source] || [direct boolValue]!=op.direct))) { [op reset]; return; }
        completion(d);
    }];
}
- (void)offer {
    if(!self.selected || ![self current:NO]) return;
    NSString *token=self.token; __weak WUArticleImage *weak=self;
    UIAction *action=[UIAction actionWithTitle:@"所选公众号图片 → 表情编辑" image:[UIImage systemImageNamed:@"face.smiling"] identifier:self.menuID handler:^(UIAction *a){
        WUArticleImage *op=weak; if([op.token isEqual:token]) [op choose];
    }];
    // Probe only interactions on the native hit path, not an unknown host delegate.
    UIView *hit=[self.web hitTest:self.point withEvent:nil];
    for(UIView *v=hit;v && [v isDescendantOfView:self.web];v=v.superview) {
        for(id<UIInteraction> candidate in v.interactions) if([candidate isKindOfClass:UIContextMenuInteraction.class]) {
            UIContextMenuInteraction *menu=(id)candidate;
            [menu updateVisibleMenuWithBlock:^UIMenu *(UIMenu *old){
                WUArticleImage *op=weak;
                if(![op.token isEqual:token] || ![op current:NO] || op.menuAdded) return old;
                op.menuAdded=YES; op.menu=menu;
                return [old menuByReplacingChildren:[old.children arrayByAddingObject:action]];
            }];
        }
        if(v==self.web) break;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.25*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        WUArticleImage *op=weak;
        if(![op.token isEqual:token] || ![op current:NO] || op.menuAdded || op.chosen) return;
        op.button=[[UIBarButtonItem alloc] initWithTitle:@"所选图→表情" style:UIBarButtonItemStylePlain target:op action:@selector(choose)];
        op.button.accessibilityLabel=@"所选公众号图片，预览并打开微信表情编辑";
        NSMutableArray *items=[op.owner.navigationItem.rightBarButtonItems mutableCopy]?:[NSMutableArray array];
        [items addObject:op.button]; op.owner.navigationItem.rightBarButtonItems=items;
    });
}
- (void)choose {
    if(!self.selected || self.chosen || ![self current:NO]) return;
    self.chosen=YES; self.deadline=Now()+90; [self removeButton];
    __weak WUArticleImage *weak=self;
    [self verify:@"verify" completion:^(NSDictionary *d){
        WUArticleImage *op=weak; if(!op || ![op current:NO]) return;
        NSString *source=op.direct?@"文章内嵌静态图片":([NSURL URLWithString:op.source].host?:@"");
        NSString *message=[NSString stringWithFormat:@"文章：mp.weixin.qq.com\n图片地址来源：%@\n%@\n仅取所选一张；PNG/JPEG ≤20MiB。GIF/APNG不支持。随后显示预览，再由你确认打开微信编辑器；不代表已添加表情。",source,op.direct?@"确认后读取这张已加载图片的数据，不联网。":@"确认后从所选地址发起无Cookie、无账号凭据的HTTPS请求，最多15秒，仅允许微信图片CDN或文章同源内最多2次重定向。结果可能不是页面缓存或原图；需要登录的图片会失败，不绕过权限。"];
        UIAlertController *prompt=[UIAlertController alertControllerWithTitle:@"读取所选公众号图片？" message:message preferredStyle:UIAlertControllerStyleAlert];
        op.prompt=prompt; NSString *token=op.token;
        [prompt addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ WUArticleImage *live=weak; if([live.token isEqual:token]) [live reset]; }]];
        [prompt addAction:[UIAlertAction actionWithTitle:op.direct?@"读取并预览":@"请求这一张并预览" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            WUArticleImage *live=weak;
            if(![live.token isEqual:token] || live.reading || ![live current:NO]) return;
            live.reading=YES;
            [live dismissOwnPrompt:^{ [weak readSelected]; }];
        }]];
        [op.owner presentViewController:prompt animated:YES completion:nil];
    }];
}
- (void)dismissOwnPrompt:(void (^)(void))next {
    NSString *token=self.token;
    UIViewController *prompt=self.prompt;
    if(self.owner.presentedViewController==prompt && prompt && !prompt.presentedViewController) {
        [prompt dismissViewControllerAnimated:YES completion:^{
            if(![self.token isEqual:token] || self.prompt!=prompt) return;
            self.prompt=nil; if([self current:NO]) next(); else [self reset];
        }];
    } else if(!self.owner.presentedViewController) { self.prompt=nil; if([self current:NO]) next(); else [self reset]; }
    else [self reset];
}
- (void)failure {
    [self removeButton];
    if(![self current:NO]) { [self reset]; return; }
    [self.fetch cancel]; self.fetch=nil; self.data=nil;
    UIAlertController *prompt=[UIAlertController alertControllerWithTitle:@"未打开表情编辑" message:@"所选图片无法安全读取、不是完整静态PNG/JPEG、超出20MiB/像素限制，或请求被拒绝。GIF/APNG不支持，不会静默取首帧。没有自动重试或添加操作。" preferredStyle:UIAlertControllerStyleAlert];
    self.prompt=prompt; NSString *token=self.token; __weak WUArticleImage *weak=self;
    [prompt addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ WUArticleImage *op=weak; if([op.token isEqual:token]) [op reset]; }]];
    [self.owner presentViewController:prompt animated:YES completion:nil];
}
- (void)readSelected {
    if(!self.chosen || !self.reading || ![self current:NO]) return;
    self.button=[[UIBarButtonItem alloc] initWithTitle:@"取消所选图" style:UIBarButtonItemStylePlain target:self action:@selector(reset)];
    self.button.accessibilityLabel=@"取消读取所选公众号图片";
    NSMutableArray *items=[self.owner.navigationItem.rightBarButtonItems mutableCopy]?:[NSMutableArray array];
    [items addObject:self.button]; self.owner.navigationItem.rightBarButtonItems=items;
    __weak WUArticleImage *weak=self;
    [self verify:@"read" completion:^(NSDictionary *d){
        WUArticleImage *op=weak; if(!op || ![op current:NO]) return;
        if(op.direct) {
            NSString *encoded=[d[@"bytes"] isKindOfClass:NSString.class]?d[@"bytes"]:nil;
            NSRange comma=[encoded rangeOfString:@","];
            BOOL type=[encoded hasPrefix:@"data:image/png;base64,"] || [encoded hasPrefix:@"data:image/jpeg;base64,"];
            NSData *data=(type && encoded.length<=27962080 && comma.location!=NSNotFound)?[[NSData alloc] initWithBase64EncodedString:[encoded substringFromIndex:comma.location+1] options:0]:nil;
            [op prepareData:data]; return;
        }
        NSString *token=op.token; op.fetch=[WUArticleImageFetch new];
        BOOL started=[op.fetch startURL:[NSURL URLWithString:op.source] article:op.article confirmed:op.reading current:^BOOL { WUArticleImage *live=weak; return [live.token isEqual:token] && [live current:NO]; } completion:^(NSData *data){
            WUArticleImage *live=weak; if([live.token isEqual:token] && [live current:NO]) { live.fetch=nil; [live prepareData:data]; }
        }];
        if(!started) [op failure];
    }];
}
- (void)prepareData:(NSData *)data {
    if(!data.length || data.length>20*1024*1024) { [self failure]; return; }
    NSString *token=self.token; __weak WUArticleImage *weak=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        BOOL valid=WUImageEntryValidateData(data);
        dispatch_async(dispatch_get_main_queue(),^{
            WUArticleImage *op=weak;
            if(![op.token isEqual:token] || ![op current:NO]) return;
            if(!valid) { [op failure]; return; }
            [op verify:@"verify" completion:^(NSDictionary *d){ [weak previewData:data]; }];
        });
    });
}
- (void)previewData:(NSData *)data {
    [self removeButton];
    if(![self current:NO] || self.owner.presentedViewController) { [self reset]; return; }
    UIImage *image=[UIImage imageWithData:data];
    if(!image || image.images.count) { [self failure]; return; }
    self.data=data; WUArticlePreview *preview=[WUArticlePreview new]; preview.image=image;
    NSString *host=self.direct?@"文章内嵌数据":[NSURL URLWithString:self.source].host;
    preview.sourceText=[NSString stringWithFormat:@"所选公众号图片\n文章：mp.weixin.qq.com\n图片地址来源：%@\n%@\n仅将这张静图交给微信原生编辑器，仍需在微信页面确认或取消；打开页面不等于已添加。",host,self.direct?@"已加载内嵌图片的原始数据。":@"按所选地址重新请求，可能不是页面缓存或原图。"];
    self.prompt=preview; preview.modalPresentationStyle=UIModalPresentationOverFullScreen;
    NSString *token=self.token; __weak WUArticleImage *weak=self;
    preview.cancel=^{ WUArticleImage *op=weak; if([op.token isEqual:token]) [op reset]; };
    preview.confirm=^{
        WUArticleImage *op=weak;
        if(![op.token isEqual:token] || op.opening || op.editing || ![op current:NO]) return;
        [op verify:@"verify" completion:^(NSDictionary *d){
            WUArticleImage *live=weak; if(!live || live.opening) return;
            live.opening=YES;
            [live dismissOwnPrompt:^{
                WUArticleImage *entry=weak; if(![entry.token isEqual:token]) return;
                [entry verify:@"verify" completion:^(NSDictionary *confirmed){
                    WUArticleImage *liveEntry=weak; if(![liveEntry.token isEqual:token]) return;
                    BOOL opened=WUOpenConfirmedImageDataEditor(liveEntry.owner,liveEntry.data,^BOOL(BOOL editing){
                        WUArticleImage *valid=weak; return [valid.token isEqual:token] && [valid current:editing];
                    });
                    liveEntry.opening=NO; liveEntry.editing=opened; liveEntry.data=nil;
                    if(!opened) [liveEntry reset];
                }];
            }];
        }];
    };
    [self.owner presentViewController:preview animated:YES completion:nil];
    preview.presentationController.delegate=self;
}
- (void)dealloc { [self watch:NO]; [self.timer invalidate]; [self.fetch cancel]; }
@end

static IMP originalLayout;
static void ArticleLayout(WKWebView *web, SEL selector) {
    ((void(*)(id,SEL))originalLayout)(web,selector);
    WUArticleImage *op=objc_getAssociatedObject(web,&ArticleKey);
    if(!WUEnabled(@"articleImage") || !WUArticleURL(web.URL) || !web.window || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) {
        // A push to our native editor may remove the article view from the window.
        if(op && !(op.editing || op.opening)) [op dispose];
        return;
    }
    if(op) return;
    UIViewController *owner=Owner(web);
    if(!owner || owner.navigationController.topViewController!=owner || owner.presentedViewController) return;
    op=[WUArticleImage new]; op.web=web; op.owner=owner;
    WUArticlePress *press=[[WUArticlePress alloc] initWithTarget:op action:@selector(pressed:)];
    press.minimumPressDuration=0.55; press.allowableMovement=6; press.numberOfTouchesRequired=1;
    press.cancelsTouchesInView=NO; press.delaysTouchesBegan=NO; press.delaysTouchesEnded=NO; press.delegate=op;
    op.press=press; [web addGestureRecognizer:press];
    objc_setAssociatedObject(web,&ArticleKey,op,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [observers addObject:op];
}
BOOL WUArticleImageAvailable(void) { return installed; }
void WUInstallArticleImage(void) {
    static dispatch_once_t once; dispatch_once(&once,^{
        observers=[NSHashTable weakObjectsHashTable];
        for(NSString *name in @[WUChanged,UIApplicationWillResignActiveNotification]) [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            for(WUArticleImage *op in observers.allObjects) [op dispose];
        }];
    });
    if(!installed) installed=WUHook(@"WKWebView",@"layoutSubviews",NO,"v",@[],(IMP)ArticleLayout,&originalLayout);
}
