#import "Graph.h"

static BOOL ROOwn(id object) { return [ROType(object) hasPrefix:@"RO"]; }
UIViewController *ROVisibleHost(UIWindow *window) {
    UIViewController *vc=window.rootViewController;
    for(NSUInteger i=0;vc && i<24;i++) {
        UIViewController *next=nil;
        if(vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) next=vc.presentedViewController;
        else if(ROIsKind(vc,UINavigationController.class)) next=((UINavigationController *)vc).visibleViewController;
        else if(ROIsKind(vc,UITabBarController.class)) next=((UITabBarController *)vc).selectedViewController;
        if(!next || next==vc) return ROOwn(vc)?nil:vc;
        vc=next;
    }
    return nil;
}
NSDictionary *ROGraph(UIWindow *window, ROSession *session) {
    UIViewController *host=ROVisibleHost(window); if(!host) return nil;
    NSMutableDictionary *nodes=[NSMutableDictionary dictionary];
    NSMutableArray *edges=[NSMutableArray array], *queue=[NSMutableArray arrayWithObject:@[host,@0]], *controllers=[NSMutableArray array];
    NSMutableOrderedSet *types=[NSMutableOrderedSet orderedSet];
    NSMutableSet *visited=[NSMutableSet set];
    __block BOOL truncated=NO; BOOL hasList=NO; NSUInteger cursor=0;
    NSString *(^record)(id)=^NSString *(id object) {
        NSString *identifier=[session identifier:object];
        if(!nodes[identifier]) { NSString *type=ROType(object); nodes[identifier]=@{@"class":type}; [types addObject:type]; }
        return identifier;
    };
    while(cursor<queue.count && visited.count<180) {
        NSArray *item=queue[cursor++]; id object=item[0]; NSUInteger depth=[item[1] unsignedIntegerValue];
        if(ROOwn(object)) continue;
        NSString *source=[session identifier:object]; if([visited containsObject:source]) continue;
        if(nodes.count>=180 && !nodes[source]) { truncated=YES; break; }
        record(object); [visited addObject:source];
        if(depth>=16) { truncated=YES; continue; }
        void (^link)(id,NSString *,BOOL)=^(id child,NSString *relation,BOOL traverse) {
            if(!child || ROOwn(child)) return;
            NSString *identifier=[session identifier:child];
            if(edges.count>=400 || (!nodes[identifier] && nodes.count>=180) || queue.count>=400) { truncated=YES; return; }
            [edges addObject:@{@"from":source,@"relation":relation,@"to":record(child)}];
            if(traverse) [queue addObject:@[child,@(depth+1)]];
        };
        if(ROIsKind(object,UIViewController.class)) {
            UIViewController *vc=object; [controllers addObject:ROType(vc)];
            // Only already-loaded, attached children. Never load a Mail view for collection.
            for(UIViewController *child in vc.childViewControllers)
                if(child.viewIfLoaded.window==window && !child.viewIfLoaded.hidden) link(child,@"visibleChild",YES);
            link(vc.parentViewController,@"parent",NO);
            link(vc.viewIfLoaded,@"loadedView",YES);
        }
        if(ROIsKind(object,UIView.class)) {
            UIView *view=object;
            for(UIView *child in view.subviews) if(!child.hidden) link(child,@"subview",YES);
            id responder=view.nextResponder;
            link(responder,@"nextResponder",ROIsKind(responder,UIViewController.class));
        }
        if(ROIsKind(object,UITableView.class)) {
            hasList=YES; link(((UITableView *)object).dataSource,@"tableDataSource",NO); link(((UITableView *)object).delegate,@"tableDelegate",NO);
        }
        if(ROIsKind(object,UICollectionView.class)) {
            hasList=YES; link(((UICollectionView *)object).dataSource,@"collectionDataSource",NO); link(((UICollectionView *)object).delegate,@"collectionDelegate",NO);
            link(((UICollectionView *)object).collectionViewLayout,@"collectionLayout",NO);
        }
    }
    return @{@"root": [session identifier:host],@"rootType":ROType(host),@"pageRole":ROPageRole(controllers,hasList),@"nodes":nodes,@"edges":edges,@"types":types.array,@"graphTruncated":@(truncated || cursor<queue.count),@"mailboxIdentityRead":@NO};
}
