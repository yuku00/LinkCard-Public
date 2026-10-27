// Explicit, bounded, in-memory snapshot. No hook recorder, filesystem or networking.
static BOOL FPBridgeCaptured;
static BOOL FPBridgeBusy;
static NSArray<NSString *> *FPBridgeMethods(id object) {
    NSMutableArray *out=[NSMutableArray new];
    for(Class cls=[object class];cls && cls!=NSObject.class && out.count<96;cls=class_getSuperclass(cls)) {
        unsigned count=0; Method *methods=class_copyMethodList(cls,&count);
        for(unsigned i=0;i<count && out.count<96;i++) {
            NSString *name=NSStringFromSelector(method_getName(methods[i]));
            NSString *lower=name.lowercaseString;
            BOOL relevant=NO;
            for(NSString *part in @[@"select",@"node",@"location",@"url",@"provider",@"itemidentifier"]) if([lower containsString:part]) relevant=YES;
            if(relevant) [out addObject:[NSString stringWithFormat:@"%@ %@ %s",NSStringFromClass(cls),name,method_getTypeEncoding(methods[i])]];
        }
        free(methods);
    }
    return out;
}
static NSUInteger FPBridgeObject(id object, NSMutableArray *objects, NSMutableArray *records) {
    if(!object) return 0;
    NSUInteger index=[objects indexOfObjectIdenticalTo:object]; if(index!=NSNotFound) return index+1;
    if(objects.count>=32) return 0;
    [objects addObject:object]; NSUInteger identity=objects.count;
    [records addObject:@{@"id":@(identity),@"class":NSStringFromClass([object class]),@"methods":FPBridgeMethods(object)}];
    return identity;
}
static void FPBridgeViews(UIView *v, NSMutableArray *out, Class cls) {
    if([v isKindOfClass:cls]) [out addObject:v];
    for(UIView *child in v.subviews) FPBridgeViews(child,out,cls);
}
static NSString *FPBridgeSnapshot(FPDualContainer *container) {
    NSMutableArray *objects=[NSMutableArray new], *records=[NSMutableArray new], *panes=[NSMutableArray new];
    for(FPBrowserPane *pane in container.panes) {
        id full=Get(pane.nativeSplit,@"fullDocumentManagerViewController");
        id current=Get(full,@"currentItemCollectionViewController");
        id hierarchy=Get(full,@"hierarchyController");
        // Public dump: readonly lastLocation -> DOCConcreteLocation.node; ABI checked by Get.
        id location=Get(hierarchy,@"lastLocation");
        id directory=[location isKindOfClass:NSClassFromString(@"DOCConcreteLocation")] ? Get(location,@"node") : nil;
        NSMutableDictionary *record=[@{@"controller":@(FPBridgeObject(current,objects,records)),@"hierarchy":@(FPBridgeObject(hierarchy,objects,records)),@"lastLocation":@(FPBridgeObject(location,objects,records)),@"directoryNode":@(FPBridgeObject(directory,objects,records)),@"directoryURLGetterInvoked":@NO} mutableCopy];
        NSMutableArray *collections=[NSMutableArray new], *selection=[NSMutableArray new];
        if(InExperiment(current) && [current isViewLoaded]) FPBridgeViews([current view],collections,UICollectionView.class);
        NSUInteger count=0,missing=0;
        for(UICollectionView *cv in collections) {
            if(cv.delegate!=current) continue;
            record[@"dataSource"]=@(FPBridgeObject(cv.dataSource,objects,records));
            NSArray *paths=cv.indexPathsForSelectedItems; count+=paths.count;
            for(NSIndexPath *path in paths) {
                if(selection.count>=16) break;
                UICollectionViewCell *cell=[cv cellForItemAtIndexPath:path];
                NSMutableArray *thumbs=[NSMutableArray new];
                Class cls=NSClassFromString(@"DOCThumbnailFittingImageView");
                if(cell && cls) FPBridgeViews(cell.contentView,thumbs,cls);
                if(!thumbs.count) { missing++; continue; }
                for(UIView *thumb in thumbs) {
                    // Both readonly getters are evidenced on this exact native class.
                    id node=Get(thumb,@"node"), url=Get(thumb,@"url");
                    [selection addObject:@{@"thumbnail":@(FPBridgeObject(thumb,objects,records)),@"node":@(FPBridgeObject(node,objects,records)),@"URLObjectAvailable":@([url isKindOfClass:NSURL.class]),@"fileURL":@([url isKindOfClass:NSURL.class] && [url isFileURL])}];
                    if(selection.count>=16) break;
                }
            }
        }
        record[@"selectedCount"]=@(count); record[@"offscreenOrUnsupportedCount"]=@(missing); record[@"selection"]=selection;
        [panes addObject:record];
    }
    NSDictionary *result=@{@"schema":@"files-dualpane-bridge-0.6.0",@"scope":@"single explicit snapshot; no values, paths, addresses or URL strings; URL booleans do not prove permission/readability",@"panes":panes,@"objects":records};
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}
@interface FPBridgeReport : UIViewController
@property(nonatomic,copy) NSString *text;
@end
@implementation FPBridgeReport
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"匿名桥接报告";
    UITextView *textView=[[UITextView alloc] initWithFrame:self.view.bounds];
    textView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    textView.editable=NO; textView.selectable=YES; textView.text=self.text;
    textView.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    [self.view addSubview:textView];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"返回双栏" style:UIBarButtonItemStylePlain target:self action:@selector(done)];
    self.navigationItem.rightBarButtonItems=@[
        [[UIBarButtonItem alloc] initWithTitle:@"分享" style:UIBarButtonItemStylePlain target:self action:@selector(shareReport:)],
        [[UIBarButtonItem alloc] initWithTitle:@"复制" style:UIBarButtonItemStylePlain target:self action:@selector(copyReport)]];
}
- (void)done { [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }
- (void)copyReport { UIPasteboard.generalPasteboard.string=self.text; }
- (void)shareReport:(UIBarButtonItem *)sender {
    if(self.presentedViewController || !self.viewIfLoaded.window) return;
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[self.text] applicationActivities:nil];
    share.popoverPresentationController.barButtonItem=sender;
    [self presentViewController:share animated:YES completion:nil];
}
@end
static void FPBridgeFailure(FPDualContainer *container) {
    FPBridgeBusy=NO;
    container.navigationItem.prompt=@"采集失败，未消耗次数；双栏位置和选择保留";
    UIViewController *host=container;
    while(host.presentedViewController) host=host.presentedViewController;
    if(!host.viewIfLoaded.window || host.isBeingDismissed) return;
    UIAlertController *error=[UIAlertController alertControllerWithTitle:@"采集失败" message:@"未生成报告，未消耗采集次数。双栏状态保留，可稍后重试。" preferredStyle:UIAlertControllerStyleAlert];
    [error addAction:[UIAlertAction actionWithTitle:@"返回" style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:error animated:YES completion:nil];
}
// UIKit owns the action alert dismissal. Never dismiss its presenting container.
// Retain both objects across the transition; only sample once the alert is off-window.
static void FPBridgeAfterAlert(FPDualContainer *container, UIAlertController *alert, NSUInteger remaining) {
    UIViewController *host=container;
    if(alert.viewIfLoaded.window || alert.presentingViewController || host.presentedViewController || host.transitionCoordinator) {
        if(!remaining) { FPBridgeFailure(container); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/20),dispatch_get_main_queue(),^{ FPBridgeAfterAlert(container,alert,remaining-1); });
        return;
    }
    if(!host.viewIfLoaded.window || container.closing || host.isBeingDismissed || host.navigationController.isBeingDismissed) { FPBridgeFailure(container); return; }
    @try {
        NSString *text=FPBridgeSnapshot(container);
        if(!text.length) { FPBridgeFailure(container); return; }
        FPBridgeReport *report=[FPBridgeReport new]; report.text=text;
        UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:report];
        navigation.modalPresentationStyle=UIModalPresentationFormSheet;
        [host presentViewController:navigation animated:YES completion:^{
            FPBridgeBusy=NO;
            if(navigation.presentingViewController && navigation.viewIfLoaded.window) {
                FPBridgeCaptured=YES;
                container.navigationItem.rightBarButtonItem.enabled=NO;
            } else FPBridgeFailure(container);
        }];
    } @catch(NSException *exception) {
        // Exception reasons may contain private values; never export them.
        FPBridgeFailure(container);
    }
}
static void FPOfferBridgeCapture(FPDualContainer *container) {
    if(FPBridgeCaptured || FPBridgeBusy || container.presentedViewController || !container.viewIfLoaded.window) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"仅一次定向采集：补跨栏桥" message:@"只导出类/selector/签名、匿名关系和 URL 对象是否存在的布尔值；不读文件，不输出名称、路径、URL、账号或内容。不自动联网/保存/复制。报告成功展示后本进程不可重复；失败不消耗次数。" preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert=alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"尚未准备好" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"采集并由我选择分享" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        if(FPBridgeCaptured || FPBridgeBusy) return;
        FPBridgeBusy=YES;
        UIAlertController *confirmation=weakAlert;
        dispatch_async(dispatch_get_main_queue(),^{ FPBridgeAfterAlert(container,confirmation,60); });
    }]];
    [container presentViewController:alert animated:YES completion:nil];
}
