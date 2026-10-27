// Explicit, bounded, in-memory snapshot. No hook recorder, filesystem or networking.
static BOOL FPBridgeCaptured;
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
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"Snapshot unavailable";
}
static void FPOfferBridgeCapture(FPDualContainer *container) {
    if(FPBridgeCaptured || container.presentedViewController) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"仅一次定向采集：补跨栏桥" message:@"先在左栏多选两个屏幕上可见的临时测试文件，右栏进入目标目录，再点采集。只导出类/selector/签名、匿名关系和 URL 对象是否存在的布尔值；不读文件，不输出名称、路径、URL、账号或内容。不自动联网/保存。采集后本进程不可重复。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"尚未准备好" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"采集并由我选择分享" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        if(FPBridgeCaptured) return; FPBridgeCaptured=YES;
        NSString *text=FPBridgeSnapshot(container);
        dispatch_async(dispatch_get_main_queue(),^{
            UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
            share.popoverPresentationController.barButtonItem=container.navigationItem.rightBarButtonItem;
            [container presentViewController:share animated:YES completion:nil];
            container.navigationItem.rightBarButtonItem.enabled=NO;
        });
    }]];
    [container presentViewController:alert animated:YES completion:nil];
}
