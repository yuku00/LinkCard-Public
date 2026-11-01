#import "PluginHubLogic.h"
static BOOL Text(id x, NSUInteger limit) { return [x isKindOfClass:NSString.class] && [x length]>0 && [x length]<=limit; }
BOOL WUHubValidControllerName(id v) {
    if(!Text(v,256)) return NO;
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.$"];
    return [v rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound;
}
NSDictionary *WUHubDefaultOptions(void) { return @{@"enabled":@NO,@"hidden":@[],@"order":@[],@"names":@{},@"groups":@{},@"custom":@{}}; }
BOOL WUHubValidOptions(id v) {
    if(![v isKindOfClass:NSDictionary.class] || [v count]!=6 || ![v[@"enabled"] isKindOfClass:NSNumber.class] ||
       !([v[@"enabled"] isEqual:@YES] || [v[@"enabled"] isEqual:@NO])) return NO;
    for(NSString *key in @[@"hidden",@"order"]) {
        id a=v[key]; if(![a isKindOfClass:NSArray.class] || [a count]>100 || [NSSet setWithArray:a].count!=[a count]) return NO;
        for(id name in a) if(!WUHubValidControllerName(name)) return NO;
    }
    for(NSString *key in @[@"names",@"groups",@"custom"]) {
        id d=v[key]; if(![d isKindOfClass:NSDictionary.class] || [d count]>100) return NO;
        for(id name in d) if(!WUHubValidControllerName(name) || !Text(d[name],[key isEqual:@"groups"]?40:80)) return NO;
    }
    return YES;
}
NSArray<NSDictionary *> *WUHubRows(NSArray<NSDictionary *> *registry, NSDictionary *options, BOOL includeHidden) {
    if(![registry isKindOfClass:NSArray.class] || !WUHubValidOptions(options) || registry.count>100) return @[];
    NSMutableArray *out=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
    for(id entry in registry) {
        if(![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *identifier=entry[@"controller"];
        if(!WUHubValidControllerName(identifier) || [seen containsObject:identifier] || !Text(entry[@"title"],80)) continue;
        [seen addObject:identifier]; BOOL hidden=[options[@"hidden"] containsObject:identifier];
        if(hidden && !includeHidden) continue;
        NSString *title=options[@"names"][identifier]?:entry[@"title"], *group=options[@"groups"][identifier]?:@"功能";
        [out addObject:@{@"controller":identifier,@"title":title,@"group":group,@"hidden":@(hidden),@"version":Text(entry[@"version"],80)?entry[@"version"]:@""}];
    }
    NSArray *order=options[@"order"];
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        NSUInteger ia=[order indexOfObject:a[@"controller"]], ib=[order indexOfObject:b[@"controller"]];
        if(ia!=ib) return ia<ib?NSOrderedAscending:NSOrderedDescending;
        NSComparisonResult r=[a[@"title"] compare:b[@"title"]];
        return r==NSOrderedSame?[a[@"controller"] compare:b[@"controller"]]:r;
    }];
    return [out copy];
}
NSDictionary *WUHubSetEntry(NSDictionary *o, NSString *identifier, NSString *name, NSString *group, BOOL hidden) {
    if(!WUHubValidOptions(o) || !WUHubValidControllerName(identifier) || !Text(name,80) || !Text(group,40)) return nil;
    name=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    group=[group stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!name.length || !group.length) return nil;
    NSMutableDictionary *out=[o mutableCopy],*names=[o[@"names"] mutableCopy],*groups=[o[@"groups"] mutableCopy];
    NSMutableArray *h=[o[@"hidden"] mutableCopy]; [h removeObject:identifier]; if(hidden) [h addObject:identifier];
    names[identifier]=name; groups[identifier]=group; out[@"names"]=names; out[@"groups"]=groups; out[@"hidden"]=h;
    return WUHubValidOptions(out)?[out copy]:nil;
}
NSDictionary *WUHubMove(NSDictionary *o, NSArray<NSDictionary *> *registry, NSString *identifier, NSInteger delta) {
    if(!WUHubValidOptions(o) || (delta!=1 && delta!=-1)) return nil;
    NSArray *rows=WUHubRows(registry,o,YES); NSMutableArray *ids=[[rows valueForKey:@"controller"] mutableCopy];
    NSUInteger at=[ids indexOfObject:identifier];
    if(at==NSNotFound || (delta<0 && !at) || (delta>0 && at+1>=ids.count)) return nil;
    [ids exchangeObjectAtIndex:at withObjectAtIndex:(NSUInteger)((NSInteger)at+delta)];
    NSMutableDictionary *out=[o mutableCopy]; out[@"order"]=ids;
    return WUHubValidOptions(out)?[out copy]:nil;
}
