// Only typed FileProvider read operations; never create placeholders, import or fetch a default
// via DOCDownloadSettings.fetchDefaultDownloadsLocationItem (that can create a folder).
@protocol FPLocationFactory <NSObject>
- (instancetype)initWithSourceIdentifier:(NSString *)source node:(id)node;
@end
static id FPLocationForNode(FPBrowserPane *pane,id node) {
    if(![node isKindOfClass:NSClassFromString(@"FPItem")]) return nil;
    id favorites=Get(FPClassGet(@"DOCFavoritesManager",@"sharedManager"),@"favoritedLocations");
    if([favorites isKindOfClass:NSArray.class]) for(id location in favorites)
        if([Get(location,@"node") isEqual:node]) return location;
    id domain=Get(node,@"cachedDomain"), sources=Get(pane.sourceObserver,@"sources");
    if(!domain || ![sources isKindOfClass:NSArray.class]) return nil;
    for(id source in sources) {
        if(![Get(source,@"providerDomain") isEqual:domain]) continue;
        id identifier=Get(source,@"identifier"); Class cls=NSClassFromString(@"DOCConcreteLocation");
        if([identifier isKindOfClass:NSString.class] && ABI(cls,@"initWithSourceIdentifier:node:","@@:@@"))
            return [(id<FPLocationFactory>)[cls alloc] initWithSourceIdentifier:identifier node:node];
    }
    return nil;
}
static void FPFetchNodeURL(id node,void(^completion)(NSURL *)) {
    NSURL *url=FPNodeURL(node); if(url) { completion(url); return; }
    id manager=FPClassGet(@"FPItemManager",@"defaultManager");
    SEL s=NSSelectorFromString(@"fetchURLForItem:creatingPlaceholderIfMissing:completionHandler:");
    if(!node || !ABI([manager class],NSStringFromSelector(s),"v@:@B@?")) { completion(nil); return; }
    ((void(*)(id,SEL,id,BOOL,id))[manager methodForSelector:s])(manager,s,node,NO,^(NSURL *value,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{ completion([value isKindOfClass:NSURL.class] && value.isFileURL ? value : nil); });
    });
}
static void FPFetchLocation(FPBrowserPane *pane,NSURL *url,void(^completion)(id)) {
    id manager=FPClassGet(@"FPItemManager",@"defaultManager"); SEL s=NSSelectorFromString(@"fetchItemForURL:completionHandler:");
    if(!url || !ABI([manager class],NSStringFromSelector(s),"v@:@@?")) { completion(nil); return; }
    ((void(*)(id,SEL,id,id))[manager methodForSelector:s])(manager,s,url,^(id item,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{ completion(FPLocationForNode(pane,item)); });
    });
}
static BOOL FPHomeAlive(FPBrowserPane *pane,NSUInteger token,NSUInteger attempt) {
    if(!FPHomeMayContinue(token,pane.homeGeneration,pane.parentViewController!=nil,pane.homeTouched,attempt)) return NO;
    // Also respect keyboard/VoiceOver navigation that did not create a touch event.
    return pane.homeNavigationIssued || FPHomeLocationUnchanged(pane.homeInitialLocation,FPCurrentLocation(pane));
}
static void FPHomeFallback(FPBrowserPane *pane,NSString *reason) {
    id split=pane.nativeSplit; SEL s=NSSelectorFromString(@"showSidebar");
    if(ABI([split class],NSStringFromSelector(s),"v@:")) ((void(*)(id,SEL))[split methodForSelector:s])(split,s);
    FPNotice((id)pane.parentViewController,reason);
}
static void FPConfirmHome(FPBrowserPane *pane,id location,NSUInteger token,NSUInteger attempt) {
    if(!FPHomeAlive(pane,token,0)) return;
    if([FPCurrentLocation(pane) isEqual:location]) { FPNotice((id)pane.parentViewController,@"首页目录已打开"); return; }
    id current=FPCurrentLocation(pane);
    if(current && !FPHomeLocationUnchanged(pane.homeInitialLocation,current)) return;
    if(attempt>=19) { FPHomeFallback(pane,@"首页目录未确认打开，已退回浏览；保存的首页未更改。"); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/4),dispatch_get_main_queue(),^{ FPConfirmHome(pane,location,token,attempt+1); });
}
static void FPOpenHomeLocation(FPBrowserPane *pane,id location,NSUInteger token) {
    if(!FPHomeAlive(pane,token,0)) return;
    pane.homeNavigationIssued=YES;
    if(!location || !FPShowLocation(pane,location)) { FPHomeFallback(pane,@"该提供商没有可用的目录导航入口，已退回浏览；原首页保留。"); return; }
    FPConfirmHome(pane,location,token,0);
}
static void FPDefaultDownloads(FPBrowserPane *pane,NSUInteger token,NSUInteger attempt) {
    if(!FPHomeAlive(pane,token,0)) return;
    // This getter represents the SYSTEM's chosen item, not a sandbox Downloads URL.
    id item=Get(pane.downloadSettings,@"currentDefaultDownloadsLocationItem");
    id location=FPLocationForNode(pane,item);
    if(location) { FPOpenHomeLocation(pane,location,token); return; }
    if(attempt>=19) { FPHomeFallback(pane,@"系统下载位置尚未提供可导航节点，已退回浏览；未创建目录或修改下载设置。"); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/4),dispatch_get_main_queue(),^{ FPDefaultDownloads(pane,token,attempt+1); });
}
static void FPRestoreHome(FPBrowserPane *pane) {
    if(pane.homeTouched || !pane.parentViewController) return;
    NSUInteger token=++pane.homeGeneration; pane.homeInitialLocation=FPCurrentLocation(pane); pane.homeNavigationIssued=NO;
    id old=[FPHomeDefaults() objectForKey:FPHomeKey(pane)]; NSDictionary *record=FPHomeRecord(old);
    if(!record) { FPHomeFallback(pane,@"首页记录损坏或版本不支持；原记录保留，已退回浏览。"); return; }
    if([old isKindOfClass:NSData.class]) [FPHomeDefaults() setObject:record forKey:FPHomeKey(pane)];
    if([record[@"mode"] isEqual:@"browse"]) { FPHomeFallback(pane,@""); return; }
    if([record[@"mode"] isEqual:@"defaultDownloads"]) {
        Class cls=NSClassFromString(@"DOCDownloadSettings");
        if(ABI(cls,@"init","@@:")) pane.downloadSettings=[[cls alloc] init];
        FPDefaultDownloads(pane,token,0); return;
    }
    NSError *error=nil; NSURL *url=FPResolveHome(record[@"bookmark"],&error);
    if(!url) { FPHomeFallback(pane,error.localizedDescription ?: @"首页书签失效，原记录保留。"); return; }
    BOOL scope=[url startAccessingSecurityScopedResource];
    __block BOOL finished=NO;
    void(^finish)(id)=^(id location){
        if(finished) return; finished=YES;
        if(scope) [url stopAccessingSecurityScopedResource];
        if(FPHomeAlive(pane,token,0)) FPOpenHomeLocation(pane,location,token);
    };
    // Readability checks run off main. A stalled provider never holds restoration indefinitely.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{ finish(nil); });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *failure=nil; BOOL valid=FPDirectory(url,&failure) && FPReadyURL(url,&failure);
        dispatch_async(dispatch_get_main_queue(),^{
            if(finished) return;
            if(!valid || !FPHomeAlive(pane,token,0)) { finish(nil); return; }
            FPFetchLocation(pane,url,finish);
        });
    });
}
