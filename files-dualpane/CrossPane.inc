static id FPFull(FPBrowserPane *pane) { return Get(pane.nativeSplit,@"fullDocumentManagerViewController"); }
static NSURL *FPNodeURL(id node) {
    // These object-returning getters are evidenced by the 20G75 FPItem snapshot.
    if(![node isKindOfClass:NSClassFromString(@"FPItem")]) return nil;
    id url=Get(node,@"fileURL"); if(![url isKindOfClass:NSURL.class]) url=Get(node,@"nodeURL");
    return [url isKindOfClass:NSURL.class] && [url isFileURL] ? url : nil;
}
#include "NativeLocation.inc"
static void FPFindCollections(UIView *view, NSMutableArray *result) {
    if([view isKindOfClass:UICollectionView.class]) [result addObject:view];
    for(UIView *child in view.subviews) FPFindCollections(child,result);
}
static void FPSelectedCellURLs(UIView *view, NSMutableArray<NSURL *> *urls) {
    Class thumbnail=NSClassFromString(@"DOCThumbnailFittingImageView");
    if(thumbnail && [view isKindOfClass:thumbnail]) {
        NSURL *url=FPNodeURL(Get(view,@"node"));
        if(!url) { id candidate=Get(view,@"url"); if([candidate isKindOfClass:NSURL.class] && [candidate isFileURL]) url=candidate; }
        if(url && ![urls containsObject:url]) [urls addObject:url];
    }
    for(UIView *child in view.subviews) FPSelectedCellURLs(child,urls);
}
static NSArray<NSURL *> *FPSelectedURLs(FPBrowserPane *pane, NSError **error) {
    UIViewController *current=Get(FPFull(pane),@"currentItemCollectionViewController");
    if(!InExperiment(current) || !current.isViewLoaded) { *error=FPFileError(@"当前栏尚未就绪。"); return nil; }
    NSMutableArray *collections=[NSMutableArray new], *urls=[NSMutableArray new]; FPFindCollections(current.view,collections);
    for(UICollectionView *cv in collections) {
        if((id)cv.delegate!=current) continue;
        NSArray *paths=[cv.indexPathsForSelectedItems copy];
        id data=cv.dataSource;
        Class bridge=NSClassFromString(@"FPDiffableBridge");
        SEL supports=NSSelectorFromString(@"supportsDataSource:"), nodeSelector=NSSelectorFromString(@"nodeFrom:indexPath:");
        BOOL swiftMapped=bridge && ABI(object_getClass(bridge),NSStringFromSelector(supports),"B@:@") && ABI(object_getClass(bridge),NSStringFromSelector(nodeSelector),"@@:@@") && ((BOOL(*)(id,SEL,id))[(id)bridge methodForSelector:supports])(bridge,supports,data);
        BOOL mapped=[data isKindOfClass:UICollectionViewDiffableDataSource.class] && ABI([data class],@"itemIdentifierForIndexPath:","@@:@");
        for(NSIndexPath *path in paths) {
            NSURL *url=nil;
            if(swiftMapped) url=FPNodeURL(((id(*)(id,SEL,id,id))[(id)bridge methodForSelector:nodeSelector])(bridge,nodeSelector,data,path));
            else if(mapped) url=FPNodeURL([(UICollectionViewDiffableDataSource *)data itemIdentifierForIndexPath:path]);
            else {
                // The captured Swift generic data source has no ObjC item getter.
                // Only inspect its genuinely displayed selected cell; never dequeue or infer paths.
                UIView *cell=[cv cellForItemAtIndexPath:path];
                NSMutableArray *visible=[NSMutableArray new]; if(cell) FPSelectedCellURLs(cell,visible);
                if(visible.count==1) url=visible.firstObject;
            }
            if(!url) { *error=FPFileError(@"部分选中项在屏外、无已验证节点或无文件 URL。请只选择可见且已下载的项目后重试；本次未执行任何项目。"); return nil; }
            if(![urls containsObject:url]) [urls addObject:url];
        }
    }
    if(!urls.count) { *error=FPFileError(@"请先用该栏的原生“选择”菜单选中文件。"); return nil; }
    return urls;
}
static void FPNotice(FPDualContainer *container, NSString *message) {
    // One line only when needed; text remains complete for the tap-to-view alert.
    container.status.text=message; container.status.accessibilityLabel=message;
    container.status.accessibilityHint=@"轻点查看完整操作结果";
    container.status.hidden=!message.length;
    container.statusHeight.constant=message.length ? MAX(24,ceil(container.status.font.lineHeight+4)) : 0;
}
#include "ProviderLocation.inc"
static void FPTransfer(FPDualContainer *container, NSUInteger index, BOOL move) {
    if(container.transferBusy || container.panes.count!=2) return;
    FPBrowserPane *source=container.panes[index], *destination=container.panes[1-index];
    NSError *error=nil; NSArray *urls=FPSelectedURLs(source,&error); NSURL *folder=FPFolder(destination);
    if(!urls || !folder) { FPNotice(container,error.localizedDescription ?: @"另一栏不是可访问的真实目录。"); return; }
    // Snapshot both current native locations and the whole real selection at the user action.
    container.transferBusy=YES;
    FPNotice(container,[NSString stringWithFormat:@"%@ %lu 项 → %@ · 进行中",move ? @"移动" : @"复制",(unsigned long)urls.count,folder.lastPathComponent]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSUInteger done=0; NSError *failure=nil;
        for(NSURL *url in urls) { failure=FPTransferOne(url,folder,move); if(failure) break; done++; }
        dispatch_async(dispatch_get_main_queue(),^{
            container.transferBusy=NO;
            FPNotice(container,[NSString stringWithFormat:@"%@：成功 %lu/%lu 项 → %@%@",move ? @"移动" : @"复制",(unsigned long)done,(unsigned long)urls.count,folder.lastPathComponent,failure ? [@"；已停止：" stringByAppendingString:failure.localizedDescription] : @"（提供商云端同步另计）"]);
        });
    });
}
static void FPOfferLayoutCapture(FPDualContainer *container, NSUInteger index);
static void FPReopenLayoutReport(FPDualContainer *container);
static UIMenu *FPPaneMenu(FPDualContainer *container, NSUInteger index) {
    __weak FPDualContainer *weak=container;
    UIAction *copy=[UIAction actionWithTitle:@"复制所选 → 另一栏当前目录" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction *a){ FPTransfer(weak,index,NO); }];
    UIAction *move=[UIAction actionWithTitle:@"移动所选 → 另一栏当前目录" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *a){ FPTransfer(weak,index,YES); }];
    UIAction *capture=[UIAction actionWithTitle:@"采集当前列表布局" image:[UIImage systemImageNamed:@"ruler"] identifier:nil handler:^(UIAction *a){ FPOfferLayoutCapture(weak,index); }];
    UIAction *reopen=[UIAction actionWithTitle:@"重开最近布局报告" image:[UIImage systemImageNamed:@"doc.text"] identifier:nil handler:^(UIAction *a){ FPReopenLayoutReport(weak); }];
    return [UIMenu menuWithTitle:index==0 ? @"左栏" : @"右栏" children:@[copy,move,capture,reopen]];
}
