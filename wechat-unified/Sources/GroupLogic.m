#import "GroupLogic.h"
#import "HomeLogic.h"
static BOOL Text(id v, NSUInteger max) { return [v isKindOfClass:NSString.class] && [v length]>0 && [v length]<=max; }
BOOL WUValidMD5(NSString *v) {
    if(![v isKindOfClass:NSString.class] || v.length!=32) return NO;
    return [v rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location==NSNotFound;
}
NSDictionary *WUEmptyEmojiGroups(void) { return @{@"enabled":@NO,@"groups":@[],@"membership":@{},@"selected":@"__all__"}; }
NSArray<NSString *> *WUToolbarActions(id value) {
    if(![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *out=[NSMutableArray array];
    for(id a in value) if([@[@"search",@"stats",@"settings",@"moments",@"repository",@"emojiSave",@"voiceForward",@"voicePacks",@"messageLinks",@"imageEmoji",@"emoticonLibrary"] containsObject:a] && ![out containsObject:a]) [out addObject:a];
    return [out copy];
}
static BOOL ValidEmoji(id s) {
    if(![s isKindOfClass:NSDictionary.class] || [s count]!=4 || ![s[@"enabled"] isKindOfClass:NSNumber.class] || ![s[@"groups"] isKindOfClass:NSArray.class] || [s[@"groups"] count]>32 || ![s[@"membership"] isKindOfClass:NSDictionary.class] || [s[@"membership"] count]>500) return NO;
    NSMutableSet *ids=[NSMutableSet setWithArray:@[@"__all__",@"__ungrouped__"]];
    for(id g in s[@"groups"]) {
        if(![g isKindOfClass:NSDictionary.class] || [g count]!=2 || !Text(g[@"name"],40) || !Text(g[@"id"],36) || ![[NSUUID alloc] initWithUUIDString:g[@"id"]] || [ids containsObject:g[@"id"]]) return NO;
        [ids addObject:g[@"id"]];
    }
    if(![ids containsObject:s[@"selected"]?:@""]) return NO;
    for(id md5 in s[@"membership"]) { id gid=s[@"membership"][md5]; if(!WUValidMD5(md5) || ![ids containsObject:gid] || [gid hasPrefix:@"__"]) return NO; }
    return YES;
}
BOOL WUValidAccountOptions(id v) {
    if(![v isKindOfClass:NSDictionary.class] || [v count]>24) return NO;
    for(id a in v) {
        id s=v[a]; if(!Text(a,256) || ![s isKindOfClass:NSDictionary.class] || [s count]>5) return NO;
        for(id key in s) if(![@[@"emoji",@"toolbar",@"home",@"momentsCache",@"toolbarLayout"] containsObject:key]) return NO;
        if(s[@"momentsCache"]) {
            id m=s[@"momentsCache"];
            if(![m isKindOfClass:NSDictionary.class] || [m count]!=4 || ![m[@"enabled"] isKindOfClass:NSNumber.class] || ![m[@"days"] isKindOfClass:NSNumber.class] || [m[@"days"] integerValue]<1 || [m[@"days"] integerValue]>3650 || [m[@"days"] doubleValue]!=[m[@"days"] integerValue]) return NO;
            for(NSString *k in @[@"monitor",@"exclude"]) { if(![m[k] isKindOfClass:NSArray.class] || [m[k] count]>100) return NO; for(id u in m[k]) if(!Text(u,256)) return NO; }
        }
        if(s[@"toolbarLayout"] && ![@[@"menu",@"grid2",@"grid3",@"grid4"] containsObject:s[@"toolbarLayout"]]) return NO;
        if(s[@"home"] && !WUValidHomeGroups(s[@"home"])) return NO;
        if(s[@"emoji"] && !ValidEmoji(s[@"emoji"])) return NO;
        if(s[@"toolbar"] && (![s[@"toolbar"] isKindOfClass:NSArray.class] || ![s[@"toolbar"] isEqual:WUToolbarActions(s[@"toolbar"])])) return NO;
    }
    return YES;
}
NSArray<NSNumber *> *WUEmojiIndexes(NSArray<NSString *> *identifiers, NSDictionary *s) {
    if(!ValidEmoji(s)) return nil;
    NSMutableArray *out=[NSMutableArray array]; NSString *selected=s[@"selected"];
    for(NSUInteger i=0;i<identifiers.count;i++) {
        NSString *md5=identifiers[i]; BOOL add=[md5 isEqual:@"custom_emoticon_pid"];
        if(!add && !WUValidMD5(md5)) return nil; // Unknown model: preserve entire host list.
        NSString *group=s[@"membership"][md5];
        if(![s[@"enabled"] boolValue] || add || [selected isEqual:@"__all__"] || ([selected isEqual:@"__ungrouped__"]?!group:[selected isEqual:group])) [out addObject:@(i)];
    }
    return [out copy];
}
NSDictionary *WURenameEmojiGroup(NSDictionary *s, NSString *identifier, NSString *name) {
    if(!ValidEmoji(s) || ![identifier isKindOfClass:NSString.class] ||
       [identifier hasPrefix:@"__"] || ![name isKindOfClass:NSString.class]) return nil;
    name=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!Text(name,40)) return nil;
    NSMutableArray *groups=[s[@"groups"] mutableCopy];
    NSUInteger index=[groups indexOfObjectPassingTest:^BOOL(NSDictionary *g,NSUInteger i,BOOL *stop){ return [g[@"id"] isEqual:identifier]; }];
    if(index==NSNotFound) return nil;
    groups[index]=@{@"id":identifier,@"name":name};
    NSMutableDictionary *next=[s mutableCopy]; next[@"groups"]=[groups copy];
    return ValidEmoji(next)?[next copy]:nil;
}
NSDictionary *WUMoveEmojiGroup(NSDictionary *s, NSString *identifier, NSInteger destination) {
    if(!ValidEmoji(s) || ![identifier isKindOfClass:NSString.class] || [identifier hasPrefix:@"__"] ||
       destination<0 || (NSUInteger)destination>=[s[@"groups"] count]) return nil;
    NSMutableArray *groups=[s[@"groups"] mutableCopy];
    NSUInteger index=[groups indexOfObjectPassingTest:^BOOL(NSDictionary *g,NSUInteger i,BOOL *stop){ return [g[@"id"] isEqual:identifier]; }];
    if(index==NSNotFound) return nil;
    id moved=groups[index]; [groups removeObjectAtIndex:index]; [groups insertObject:moved atIndex:(NSUInteger)destination];
    NSMutableDictionary *next=[s mutableCopy]; next[@"groups"]=[groups copy];
    return ValidEmoji(next)?[next copy]:nil;
}
NSDictionary *WURemoveEmojiGroup(NSDictionary *s, NSString *identifier) {
    if(!ValidEmoji(s) || [identifier hasPrefix:@"__"]) return s;
    NSMutableDictionary *out=[s mutableCopy], *membership=[s[@"membership"] mutableCopy]; NSMutableArray *groups=[NSMutableArray array];
    for(NSDictionary *g in s[@"groups"]) if(![g[@"id"] isEqual:identifier]) [groups addObject:g];
    for(NSString *md5 in [membership.allKeys copy]) if([membership[md5] isEqual:identifier]) [membership removeObjectForKey:md5];
    out[@"groups"]=groups; out[@"membership"]=membership;
    if([out[@"selected"] isEqual:identifier]) out[@"selected"]=@"__all__";
    return [out copy];
}
