#import "Metadata.h"

BOOL MPAllowed(NSString *bundle, NSString *build) {
    return [bundle isEqualToString:@"com.apple.mobilemail"] && [build isEqualToString:@"20G75"];
}
BOOL MPRelevant(NSString *name) {
    for (NSString *word in @[@"Message", @"Mailbox", @"Conversation", @"Thread", @"Query", @"Repository", @"Selection", @"Action", @"Operation", @"Predicate", @"Future", @"Promise", @"Scheduler", @"Queue", @"Permission", @"Capability"])
        if ([name rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}
NSArray<NSString *> *MPCandidates(void) {
    return @[@"MessageListViewController", @"MailboxContentViewController", @"MailMainScene", @"MailAppController", @"MessageListDataSource", @"MessageListCollectionView", @"MessageListSelectionModel", @"ConversationViewController", @"ConversationViewControllerBase", @"MessageListViewControllerState", @"MailActionsViewController", @"MFMailMessageViewController", @"MFMailboxUid", @"MFMessageOperation", @"MFMessageOperationQueue", @"EMMessage", @"EMMessageListItem", @"EMConversation", @"EMMessageList", @"EMMessageListItemPredicates", @"EMMessageListItemQuery", @"EMQuery", @"EMCollection", @"EMRepository", @"EMRepositoryObject", @"EMDaemonInterface", @"EMMessageRepository", @"EMMailbox", @"EMMailboxRepository", @"EMMailboxCollection", @"EMAccount", @"EMReceivingAccount", @"EMCreateMailboxChangeAction", @"EMMailboxChangeAction", @"EMMessageChangeAction", @"EMMessageTransferAction", @"EMMessageTransferAllAction", @"EMUndoMessageAction", @"ECEmailAddress", @"EFFuture", @"EFPromise", @"EFScheduler", @"EFSerialScheduler", @"NSOperation", @"NSOperationQueue", @"NSPredicate"];
}
static NSString *MPString(const char *s) { return s ? ([NSString stringWithUTF8String:s] ?: @"<invalid-utf8>") : @"<absent>"; }
static NSArray *MPProperties(id owner, BOOL protocolOwner, BOOL required, BOOL instance) {
    unsigned int count=0;
    objc_property_t *list=protocolOwner ? protocol_copyPropertyList2((Protocol *)owner, &count, required, instance) : class_copyPropertyList((Class)owner, &count);
    NSMutableArray *out=[NSMutableArray array];
    for (unsigned int i=0;i<count;i++) [out addObject:@{@"name":MPString(property_getName(list[i])), @"attributes":MPString(property_getAttributes(list[i]))}];
    free(list); return out;
}
static NSArray *MPMethods(Class cls) {
    unsigned int count=0; Method *list=class_copyMethodList(cls,&count);
    NSMutableArray *out=[NSMutableArray array];
    for (unsigned int i=0;i<count;i++) {
        Method m=list[i]; NSMutableArray *args=[NSMutableArray array];
        for (unsigned int a=0;a<method_getNumberOfArguments(m);a++) { char *t=method_copyArgumentType(m,a); [args addObject:MPString(t)]; free(t); }
        char *result=method_copyReturnType(m);
        [out addObject:@{@"selector":MPString(sel_getName(method_getName(m))), @"encoding":MPString(method_getTypeEncoding(m)), @"return":MPString(result), @"argumentsIncludingSelfCmd":args}]; free(result);
    }
    free(list); return out;
}
static void MPProtocol(Protocol *p, NSMutableDictionary *protocols) {
    NSString *name=MPString(protocol_getName(p)); if (protocols[name]) return;
    NSMutableDictionary *record=[NSMutableDictionary dictionary]; protocols[name]=record;
    NSMutableArray *parents=[NSMutableArray array]; unsigned int count=0;
    Protocol *__unsafe_unretained *list=protocol_copyProtocolList(p,&count);
    for(unsigned int i=0;i<count;i++) { [parents addObject:MPString(protocol_getName(list[i]))]; MPProtocol(list[i], protocols); }
    free(list); record[@"inherits"]=parents;
    for(int required=0;required<=1;required++) for(int instance=0;instance<=1;instance++) {
        NSString *key=[NSString stringWithFormat:@"%@%@",required?@"required":@"optional",instance?@"Instance":@"Class"];
        struct objc_method_description *methods=protocol_copyMethodDescriptionList(p,required,instance,&count);
        NSMutableArray *out=[NSMutableArray array];
        for(unsigned int i=0;i<count;i++) [out addObject:@{@"selector":MPString(sel_getName(methods[i].name)), @"encoding":MPString(methods[i].types)}];
        free(methods); record[key]=@{@"methods":out,@"properties":MPProperties(p,YES,required,instance)};
    }
}
NSDictionary *MPMetadata(NSArray<NSString *> *observed, NSArray<NSString *> *imageAnchors) {
    NSMutableOrderedSet *names=[NSMutableOrderedSet orderedSetWithArray:MPCandidates()]; [names addObjectsFromArray:observed];
    NSMutableSet *images=[NSMutableSet set]; NSMutableArray *discovery=[NSMutableArray array];
    // Only Mail + Email + EmailCore + EmailFoundation images; never enumerate the process class list.
    for(NSString *anchor in imageAnchors) {
        Class c=NSClassFromString(anchor); const char *image=c?class_getImageName(c):NULL; if(!image) continue;
        NSString *imageKey=MPString(image); if([images containsObject:imageKey]) continue; [images addObject:imageKey];
        unsigned int count=0, matched=0; const char **list=objc_copyClassNamesForImage(image,&count);
        for(unsigned int i=0;i<count;i++) { NSString *name=MPString(list[i]); if(MPRelevant(name)) { [names addObject:name]; matched++; } }
        free(list); [discovery addObject:@{@"anchor":anchor,@"examined":@(count),@"matched":@(matched)}];
    }
    NSMutableDictionary *classes=[NSMutableDictionary dictionary], *protocols=[NSMutableDictionary dictionary];
    NSMutableArray *missing=[NSMutableArray array];
    for(NSString *name in names) {
        Class cls=NSClassFromString(name);
        if(!cls) { Protocol *p=NSProtocolFromString(name); if(p) MPProtocol(p,protocols); else [missing addObject:name]; continue; }
        // Full ancestor chain, no per-class method/property truncation. Each class/protocol emitted once.
        for(Class c=cls;c;c=class_getSuperclass(c)) {
            NSString *n=MPString(class_getName(c)); if(classes[n]) break;
            NSMutableArray *adopted=[NSMutableArray array]; unsigned int count=0;
            Protocol *__unsafe_unretained *list=class_copyProtocolList(c,&count);
            for(unsigned int i=0;i<count;i++) { [adopted addObject:MPString(protocol_getName(list[i]))]; MPProtocol(list[i],protocols); } free(list);
            Class parent=class_getSuperclass(c);
            classes[n]=@{@"superclass":parent?MPString(class_getName(parent)):@"", @"protocols":adopted, @"instanceMethods":MPMethods(c), @"classMethods":MPMethods(object_getClass(c)), @"instanceProperties":MPProperties(c,NO,YES,YES), @"classProperties":MPProperties(object_getClass(c),NO,YES,NO)};
        }
    }
    for(NSString *name in @[@"EMMessageRepositoryInterface", @"EMMailboxRepositoryInterface", @"EMMessageListItem", @"EMMessageBuilder", @"EMMailboxBuilder", @"ECEmailAddressConvertible"]) { Protocol *p=NSProtocolFromString(name); if(p) MPProtocol(p,protocols); else [missing addObject:[@"protocol:" stringByAppendingString:name]]; }
    return @{@"classes":classes,@"protocols":protocols,@"missing":missing,@"imageDiscovery":discovery,@"classCount":@(classes.count),@"protocolCount":@(protocols.count),@"metadataTruncated":@NO};
}
