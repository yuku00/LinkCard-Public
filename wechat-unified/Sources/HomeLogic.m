#import "HomeLogic.h"
static BOOL Text(id s,NSUInteger n) { return [s isKindOfClass:NSString.class] && [s length]>0 && [s length]<=n; }
NSDictionary *WUEmptyHomeGroups(void) { return @{ @"enabled":@NO,@"selected":@"all",@"groups":@[],@"membership":@{} }; }
BOOL WUValidHomeGroups(id s) {
    if(![s isKindOfClass:NSDictionary.class] || [s count]!=4 || ![s[@"enabled"] isKindOfClass:NSNumber.class] || ![s[@"groups"] isKindOfClass:NSArray.class] || [s[@"groups"] count]>32 || ![s[@"membership"] isKindOfClass:NSDictionary.class] || [s[@"membership"] count]>500) return NO;
    NSMutableSet *ids=[NSMutableSet setWithArray:@[@"all",@"private",@"chatroom",@"other"]];
    for(id g in s[@"groups"]) { if(![g isKindOfClass:NSDictionary.class] || [g count]!=2 || !Text(g[@"name"],40) || !Text(g[@"id"],36) || ![[NSUUID alloc] initWithUUIDString:g[@"id"]] || [ids containsObject:g[@"id"]]) return NO; [ids addObject:g[@"id"]]; }
    if(!Text(s[@"selected"],36) || ![ids containsObject:s[@"selected"]]) return NO;
    for(id user in s[@"membership"]) { id gid=s[@"membership"][user]; if(!Text(user,256) || !Text(gid,36) || ![[NSUUID alloc] initWithUUIDString:gid] || ![ids containsObject:gid]) return NO; }
    return YES;
}
NSString *WUHomeKind(NSString *u, BOOL box, BOOL brand, BOOL single) {
    if(!Text(u,256)) return nil;
    NSString *n=u.lowercaseString;
    if(box || [n isEqual:@"chatroom_session_box"] || [n hasSuffix:@"@chatroom"] || [n hasSuffix:@"@im.chatroom"]) return @"chatroom";
    if(brand || [n containsString:@"@openim"] || [n hasPrefix:@"gh_"] || [n isEqual:@"brandsessionholder"] || [n isEqual:@"brandservicesessionholder"]) return @"other";
    return single?@"private":@"other";
}
NSArray<NSNumber *> *WUHomeIndexes(NSArray<NSDictionary *> *rows, NSDictionary *s) {
    if(!WUValidHomeGroups(s) || ![rows isKindOfClass:NSArray.class] || rows.count>20000) return nil;
    NSMutableArray *out=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
    for(NSUInteger i=0;i<rows.count;i++) {
        id r=rows[i]; if(![r isKindOfClass:NSDictionary.class] || !Text(r[@"username"],256) || ![@[@"private",@"chatroom",@"other"] containsObject:r[@"kind"]] || [seen containsObject:r[@"username"]]) return nil;
        [seen addObject:r[@"username"]]; NSString *selected=s[@"selected"];
        if(![s[@"enabled"] boolValue] || [selected isEqual:@"all"] || [selected isEqual:r[@"kind"]] || [selected isEqual:s[@"membership"][r[@"username"]]]) [out addObject:@(i)];
    }
    return [out copy];
}
NSDictionary *WURemoveHomeGroup(NSDictionary *s, NSString *gid) {
    if(!WUValidHomeGroups(s) || ![[NSUUID alloc] initWithUUIDString:gid]) return s;
    NSMutableDictionary *out=[s mutableCopy], *members=[s[@"membership"] mutableCopy]; NSMutableArray *groups=[NSMutableArray array];
    for(NSDictionary *g in s[@"groups"]) if(![g[@"id"] isEqual:gid]) [groups addObject:g];
    for(NSString *u in [members.allKeys copy]) if([members[u] isEqual:gid]) [members removeObjectForKey:u];
    out[@"groups"]=groups; out[@"membership"]=members; if([out[@"selected"] isEqual:gid]) out[@"selected"]=@"all"; return out;
}

NSDictionary *WUHomeProjection(NSArray<NSArray *> *sources, NSArray<NSArray<NSDictionary *> *> *rows, NSDictionary *state, NSUInteger originalTopCount) {
    if(sources.count!=3 || rows.count!=3 || !WUValidHomeGroups(state)) return nil;
    NSMutableArray *projected=[NSMutableArray array];
    for(NSUInteger slot=0;slot<3;slot++) {
        if(![sources[slot] isKindOfClass:NSArray.class] || ![rows[slot] isKindOfClass:NSArray.class] || sources[slot].count!=rows[slot].count) return nil;
        NSArray *indexes=WUHomeIndexes(rows[slot],state); if(!indexes) return nil;
        NSMutableArray *a=[NSMutableArray array]; for(NSNumber *i in indexes) [a addObject:sources[slot][i.unsignedIntegerValue]];
        [projected addObject:[a copy]];
    }
    // top is the visible (possibly collapsed) subset, allTop owns the full pin count.
    NSSet *allTop=[NSSet setWithArray:[rows[1] valueForKey:@"username"]];
    for(NSDictionary *r in rows[0]) if(![allTop containsObject:r[@"username"]]) return nil;
    for(NSDictionary *r in rows[2]) if([allTop containsObject:r[@"username"]]) return nil;
    BOOL filtering=[state[@"enabled"] boolValue] && ![state[@"selected"] isEqual:@"all"];
    return @{@"arrays":[projected copy],@"topCount":filtering?@([projected[1] count]):@(originalTopCount)};
}
