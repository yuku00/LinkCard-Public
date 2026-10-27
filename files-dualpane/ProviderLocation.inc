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
static void __attribute__((unused)) FPFetchNodeURL(id node,void(^completion)(NSURL *)) {
    NSURL *url=FPNodeURL(node); if(url) { completion(url); return; }
    id manager=FPClassGet(@"FPItemManager",@"defaultManager");
    SEL s=NSSelectorFromString(@"fetchURLForItem:creatingPlaceholderIfMissing:completionHandler:");
    if(!node || !ABI([manager class],NSStringFromSelector(s),"v@:@B@?")) { completion(nil); return; }
    ((void(*)(id,SEL,id,BOOL,id))[manager methodForSelector:s])(manager,s,node,NO,^(NSURL *value,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{ completion([value isKindOfClass:NSURL.class] && value.isFileURL ? value : nil); });
    });
}
static void __attribute__((unused)) FPFetchLocation(FPBrowserPane *pane,NSURL *url,void(^completion)(id)) {
    id manager=FPClassGet(@"FPItemManager",@"defaultManager"); SEL s=NSSelectorFromString(@"fetchItemForURL:completionHandler:");
    if(!url || !ABI([manager class],NSStringFromSelector(s),"v@:@@?")) { completion(nil); return; }
    ((void(*)(id,SEL,id,id))[manager methodForSelector:s])(manager,s,url,^(id item,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{ completion(FPLocationForNode(pane,item)); });
    });
}
