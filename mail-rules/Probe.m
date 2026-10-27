#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import "Metadata.h"

@interface MPBar : UIStackView @end
@implementation MPBar @end
@interface MPViewer : UIViewController
@property(nonatomic,copy) NSString *report;
@end
@implementation MPViewer
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Mail Probe " MP_VERSION;
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    UITextView *text=[[UITextView alloc] initWithFrame:self.view.bounds];
    text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    text.editable=NO; text.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    text.text=self.report; [self.view addSubview:text];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)share {
    UIActivityViewController *a=[[UIActivityViewController alloc] initWithActivityItems:@[self.report] applicationActivities:nil];
    a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
    [self presentViewController:a animated:YES completion:nil];
}
@end

@interface MPEntry : NSObject
@property(nonatomic,strong) NSMapTable *bars;
@property(nonatomic,strong) NSMapTable *ids;
@property(nonatomic,strong) NSMutableArray *stages;
@property(nonatomic,strong) NSMutableDictionary *metadata;
@property(nonatomic,strong) NSMutableSet *observed;
@property(nonatomic) NSUInteger serial;
@property(nonatomic) BOOL busy;
@property(nonatomic,strong) dispatch_queue_t worker;
+ (instancetype)shared;
- (void)install;
@end
@implementation MPEntry
+ (instancetype)shared {
    static MPEntry *entry; static dispatch_once_t once;
    dispatch_once(&once,^{
        entry=[MPEntry new]; entry.bars=[NSMapTable weakToWeakObjectsMapTable];
        entry.ids=[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory];
        entry.stages=[NSMutableArray array]; entry.metadata=[NSMutableDictionary dictionary]; entry.observed=[NSMutableSet set];
        entry.worker=dispatch_queue_create("dev.mailrules.probe.metadata", DISPATCH_QUEUE_SERIAL);
    }); return entry;
}
- (NSString *)objectID:(id)object {
    if(!object) return @"none";
    NSString *identifier=[self.ids objectForKey:object];
    if(!identifier) { identifier=[NSString stringWithFormat:@"o%lu",(unsigned long)++self.serial]; [self.ids setObject:identifier forKey:object]; }
    return identifier;
}
- (NSString *)record:(id)object nodes:(NSMutableDictionary *)nodes names:(NSMutableSet *)names {
    if(!object) return @"none";
    NSString *identifier=[self objectID:object], *name=NSStringFromClass(object_getClass(object));
    nodes[identifier]=@{@"class":name}; [names addObject:name]; return identifier;
}
- (NSDictionary *)snapshot:(UIWindow *)window names:(NSMutableSet *)names {
    NSMutableDictionary *nodes=[NSMutableDictionary dictionary]; NSMutableArray *edges=[NSMutableArray array];
    NSMutableArray *queue=[NSMutableArray arrayWithObject:@[window,@0]];
    NSMutableSet *visited=[NSMutableSet set]; NSUInteger cursor=0, depthSkipped=0, omittedEdges=0;
    // UIKit traversal is bounded; all declarations of every observed/target class remain complete.
    while(cursor<queue.count && visited.count<1800) {
        NSArray *item=queue[cursor++]; id object=item[0]; NSUInteger depth=[item[1] unsignedIntegerValue];
        if([object isKindOfClass:MPBar.class] || [object isKindOfClass:MPViewer.class]) continue;
        NSString *source=[self record:object nodes:nodes names:names]; if([visited containsObject:source]) continue; [visited addObject:source];
        if(depth>=24) { depthSkipped++; continue; }
        void (^link)(id,NSString *,BOOL)=^(id child,NSString *relation,BOOL traverse) {
            if(!child || [child isKindOfClass:MPBar.class] || [child isKindOfClass:MPViewer.class]) return;
            // Edges and queued nodes are bounded too, not just processed nodes.
            if(edges.count>=6000) return;
            NSString *target=[self record:child nodes:nodes names:names];
            [edges addObject:@{@"from":source,@"relation":relation,@"to":target}];
            if(traverse && queue.count<6000) [queue addObject:@[child,@(depth+1)]];
        };
        if([object isKindOfClass:UIWindow.class]) link(((UIWindow *)object).rootViewController,@"rootViewController",YES);
        if([object isKindOfClass:UIViewController.class]) {
            UIViewController *vc=object;
            for(UIViewController *child in vc.childViewControllers) link(child,@"childViewController",YES);
            link(vc.presentedViewController,@"presentedViewController",YES);
            link(vc.parentViewController,@"parentViewController",NO);
            link(vc.viewIfLoaded,@"viewIfLoaded",YES);
        }
        if([object isKindOfClass:UIView.class]) {
            UIView *view=object;
            for(UIView *child in view.subviews) link(child,@"subview",YES);
            link(view.nextResponder,@"nextResponder",[view.nextResponder isKindOfClass:UIViewController.class]);
            for(id<UIInteraction> interaction in view.interactions) link(interaction,@"interaction",NO);
        }
        if([object isKindOfClass:UITableView.class]) { link(((UITableView *)object).dataSource,@"tableDataSource",NO); link(((UITableView *)object).delegate,@"tableDelegate",NO); }
        if([object isKindOfClass:UICollectionView.class]) { link(((UICollectionView *)object).dataSource,@"collectionDataSource",NO); link(((UICollectionView *)object).delegate,@"collectionDelegate",NO); link(((UICollectionView *)object).collectionViewLayout,@"collectionLayout",NO); }
        if(edges.count>=6000) omittedEdges++;
    }
    return @{@"stage":@(self.stages.count+1),@"root": [self objectID:window],@"nodes":nodes,@"edges":edges,@"visited":@(visited.count),@"pending":@(queue.count-cursor),@"depthBoundaryNodes":@(depthSkipped),@"edgeLimitHit":@(omittedEdges>0),@"graphTruncated":@(cursor<queue.count || depthSkipped>0 || omittedEdges>0),@"semanticScope":@"User-selected Mail screen; inbox/thread/menu role not inferred from private values"};
}
- (UIViewController *)host:(UIWindow *)window {
    UIViewController *host=window.rootViewController;
    while(host.presentedViewController && !host.presentedViewController.isBeingDismissed) host=host.presentedViewController;
    if([host isKindOfClass:UINavigationController.class]) {
        UIViewController *top=((UINavigationController *)host).topViewController;
        if([top isKindOfClass:MPViewer.class]) return nil;
    }
    return host;
}
- (void)capture:(UIButton *)button {
    UIWindow *window=button.window;
    if(self.busy || !window.isKeyWindow || self.stages.count>=8 || ![self host:window]) return;
    self.busy=YES; button.enabled=NO; [button setTitle:@"采集中" forState:UIControlStateNormal];
    NSMutableSet *names=[NSMutableSet set]; NSDictionary *stage=[self snapshot:window names:names];
    [self.stages addObject:stage]; [self.observed unionSet:names];
    NSArray *allNames=[self.observed.allObjects sortedArrayUsingSelector:@selector(compare:)];
    // Public UIApplication.delegate is used solely for its class/image, never Mail private getters.
    NSString *appClass=NSStringFromClass(object_getClass(UIApplication.sharedApplication.delegate));
    NSArray *anchors=@[appClass?:@"MailAppController",@"EMMessage",@"ECEmailAddress",@"EFFuture"];
    dispatch_async(self.worker,^{
        NSDictionary *result=MPMetadata(allNames, anchors);
        dispatch_async(dispatch_get_main_queue(),^{
            [self.metadata setDictionary:result];
            self.busy=NO; button.enabled=YES;
            [button setTitle:[NSString stringWithFormat:@"采集 %lu/8",(unsigned long)self.stages.count] forState:UIControlStateNormal];
        });
    });
}
- (void)report:(UIButton *)button {
    if(self.busy) return; UIViewController *host=[self host:button.window]; if(!host || host.isBeingPresented || host.isBeingDismissed) return;
    UIAlertController *panel=[UIAlertController alertControllerWithTitle:@"Mail Probe 0.1.0" message:@"左侧采集按钮只在点击时读取界面关系和接口声明；最多8阶段。按收件箱→更多菜单→取消依次点采集。不必打开正文。仅内存保存，分享由你选择去向。" preferredStyle:UIAlertControllerStyleAlert];
    [panel addAction:[UIAlertAction actionWithTitle:@"查看 / 分享报告" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSDictionary *document=@{@"probe":@"Mail Probe",@"version":MP_VERSION,@"build":@"20G75",@"bundle":@"com.apple.mobilemail",@"stages":self.stages,@"metadata":self.metadata,@"limits":@{@"stages":@8,@"graphNodesVisited":@1800,@"graphDepth":@24,@"graphEdges":@6000},@"evidence":@"Declarations and public UIKit relations only. No Mail actions executed. Category methods are merged by the runtime; original category provenance unavailable. @ / @? encodings do not prove concrete object/block parameter contracts. Repository/query/selection/action declarations do not prove live private-instance ownership. Parent/capability/sender semantics, queue completion and server results remain unverified. No inbox identity inferred. Swift-only declarations unavailable. No private getters, object values, addresses or pointers emitted."};
        NSError *error=nil; NSData *data=[NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
        MPViewer *viewer=[MPViewer new]; viewer.report=data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:@"Report serialization failed; no details logged.";
        [host dismissViewControllerAnimated:YES completion:^{ [host presentViewController:[[UINavigationController alloc] initWithRootViewController:viewer] animated:YES completion:nil]; }];
    }]];
    [panel addAction:[UIAlertAction actionWithTitle:@"清空内存报告" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self.stages removeAllObjects]; [self.metadata removeAllObjects]; [self.observed removeAllObjects]; [self.ids removeAllObjects]; self.serial=0;
        for(UIWindow *w in self.bars) { MPBar *bar=[self.bars objectForKey:w]; UIButton *capture=(UIButton *)bar.arrangedSubviews.firstObject; [capture setTitle:@"采集 0/8" forState:UIControlStateNormal]; }
    }]];
    [panel addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:panel animated:YES completion:nil];
}
- (void)install {
    NSAssert(NSThread.isMainThread,@"Main thread only");
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive) continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(!window.isKeyWindow || window.windowLevel!=UIWindowLevelNormal || window.screen!=UIScreen.mainScreen || !window.rootViewController) continue;
            MPBar *bar=[self.bars objectForKey:window]; if(bar) { [window bringSubviewToFront:bar]; continue; }
            bar=[MPBar new]; bar.axis=UILayoutConstraintAxisHorizontal; bar.spacing=4; bar.distribution=UIStackViewDistributionFillEqually;
            bar.backgroundColor=UIColor.secondarySystemBackgroundColor; bar.layer.cornerRadius=8; bar.translatesAutoresizingMaskIntoConstraints=NO;
            UIButton *capture=[UIButton buttonWithType:UIButtonTypeSystem], *report=[UIButton buttonWithType:UIButtonTypeSystem];
            [capture setTitle:@"采集 0/8" forState:UIControlStateNormal]; capture.accessibilityLabel=@"Mail Probe 显式采集当前界面匿名接口元数据";
            [report setTitle:@"报告" forState:UIControlStateNormal]; report.accessibilityLabel=@"Mail Probe 查看分享或清空内存报告";
            [capture addTarget:self action:@selector(capture:) forControlEvents:UIControlEventTouchUpInside];
            [report addTarget:self action:@selector(report:) forControlEvents:UIControlEventTouchUpInside];
            [bar addArrangedSubview:capture]; [bar addArrangedSubview:report]; [window addSubview:bar]; [self.bars setObject:bar forKey:window];
            [NSLayoutConstraint activateConstraints:@[[bar.leadingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.leadingAnchor constant:8], [bar.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-56], [bar.widthAnchor constraintEqualToConstant:156], [bar.heightAnchor constraintEqualToConstant:44]]];
        }
    }
}
@end

__attribute__((constructor)) static void MPStart(void) {
    @autoreleasepool {
        char build[64]={0}; size_t size=sizeof(build);
        if(sysctlbyname("kern.osversion",build,&size,NULL,0)!=0 || size==0 || size>=sizeof(build)) return;
        if(!MPAllowed(NSBundle.mainBundle.bundleIdentifier,[NSString stringWithUTF8String:build])) return;
        dispatch_async(dispatch_get_main_queue(),^{
            MPEntry *entry=[MPEntry shared];
            for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UISceneDidActivateNotification,UIWindowDidBecomeKeyNotification])
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [entry install]; }];
            [entry install];
        });
    }
}
