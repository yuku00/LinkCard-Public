static void FPSaveHome(FPBrowserPane *pane) {
    FPDualContainer *container=(id)pane.parentViewController;
    ++pane.homeGeneration; NSUInteger revision=++pane.homeRevision;
    if(FPBrowseVisible(pane)) {
        [FPHomeDefaults() setObject:@{@"schema":@1,@"mode":@"browse"} forKey:FPHomeKey(pane)];
        FPNotice(container,@"本栏浏览／位置总览已设为首页"); return;
    }
    id location=FPCurrentLocation(pane), node=Get(location,@"node");
    if(!node) { FPNotice(container,@"当前可见位置尚未取得真实目录节点；原首页保留。请待目录加载完成后重试。"); return; }
    __block BOOL finished=NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(finished || revision!=pane.homeRevision) return;
        finished=YES; FPNotice(container,@"提供商未及时返回可保存目录；原首页保留。");
    });
    FPFetchNodeURL(node,^(NSURL *url){
        if(finished || revision!=pane.homeRevision) return;
        if(!url) { finished=YES; FPNotice(container,@"该提供商目录未返回可用文件 URL；并非浏览 root，原首页保留。"); return; }
        BOOL scope=[url startAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            NSError *error=nil; NSData *bookmark=FPHomeBookmark(url,&error);
            NSURL *check=bookmark ? FPResolveHome(bookmark,&error) : nil;
            BOOL valid=check && FPDirectory(check,&error);
            if(scope) [url stopAccessingSecurityScopedResource];
            dispatch_async(dispatch_get_main_queue(),^{
                if(finished || revision!=pane.homeRevision) return; finished=YES;
                if(!FPHomeCanCommit(valid,revision,pane.homeRevision)) { FPNotice(container,error.localizedDescription ?: @"书签验证失败，原首页保留。"); return; }
                [FPHomeDefaults() setObject:@{@"schema":@1,@"mode":@"custom",@"bookmark":bookmark} forKey:FPHomeKey(pane)];
                FPNotice(container,pane.homeIndex==0 ? @"左栏当前目录已设为首页" : @"右栏当前目录已设为首页");
            });
        });
    });
}
static void FPClearHome(FPBrowserPane *pane) {
    ++pane.homeRevision; ++pane.homeGeneration;
    [FPHomeDefaults() setObject:@{@"schema":@1,@"mode":@"defaultDownloads"} forKey:FPHomeKey(pane)];
    pane.homeTouched=NO; FPRestoreHome(pane);
}
