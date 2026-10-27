#import "ReadOnly.h"

static NSString *ROString(const char *s) { return s ? ([NSString stringWithUTF8String:s] ?: @"invalid") : @"absent"; }
static BOOL ROTarget(NSString *name) {
    for(NSString *prefix in @[@"MessageList",@"Mailbox",@"Mailboxes",@"MailMain",@"MailApp",@"MailActions",@"Conversation",@"EMMessage",@"EMMailbox",@"EMQuery",@"EMRepository"])
        if([name hasPrefix:prefix]) return YES;
    return NO;
}
static NSDictionary *ROMethods(Class cls) {
    unsigned int count=0; Method *list=class_copyMethodList(cls,&count);
    NSMutableArray *methods=[NSMutableArray array];
    for(unsigned int i=0;i<count && i<64;i++)
        [methods addObject:@{@"selector":ROString(sel_getName(method_getName(list[i]))),@"encoding":ROString(method_getTypeEncoding(list[i]))}];
    free(list); return @{@"declarations":methods,@"total":@(count),@"truncated":@(count>64)};
}
static NSDictionary *ROProperties(Class cls) {
    unsigned int count=0; objc_property_t *list=class_copyPropertyList(cls,&count);
    NSMutableArray *properties=[NSMutableArray array];
    for(unsigned int i=0;i<count && i<48;i++)
        [properties addObject:@{@"name":ROString(property_getName(list[i])),@"attributes":ROString(property_getAttributes(list[i]))}];
    free(list); return @{@"declarations":properties,@"total":@(count),@"truncated":@(count>48)};
}
static void ROProtocol(Protocol *protocol,NSMutableDictionary *out) {
    NSString *name=ROString(protocol_getName(protocol)); if(out[name] || out.count>=32) return;
    NSMutableDictionary *item=[NSMutableDictionary dictionary]; out[name]=item;
    unsigned int count=0; Protocol *__unsafe_unretained *parents=protocol_copyProtocolList(protocol,&count);
    NSMutableArray *parentNames=[NSMutableArray array];
    for(unsigned int i=0;i<count;i++) { [parentNames addObject:ROString(protocol_getName(parents[i]))]; ROProtocol(parents[i],out); }
    free(parents); item[@"parents"]=parentNames;
    for(int required=0;required<=1;required++) for(int instance=0;instance<=1;instance++) {
        struct objc_method_description *list=protocol_copyMethodDescriptionList(protocol,required,instance,&count);
        NSMutableArray *methods=[NSMutableArray array];
        for(unsigned int i=0;i<count && i<48;i++) [methods addObject:@{@"selector":ROString(sel_getName(list[i].name)),@"encoding":ROString(list[i].types)}];
        free(list);
        item[[NSString stringWithFormat:@"%@%@",required?@"required":@"optional",instance?@"Instance":@"Class"]]=@{@"methods":methods,@"total":@(count),@"truncated":@(count>48)};
    }
}
NSDictionary *ROMetadata(NSArray<NSString *> *observed) {
    NSMutableOrderedSet *names=[NSMutableOrderedSet orderedSet];
    // Observed owners first, then a fixed declaration-only fallback. No image/process dump.
    for(NSString *name in observed) if(ROTarget(name) && names.count<20) [names addObject:name];
    [names addObjectsFromArray:@[@"MessageListViewController",@"MessageListDataSource",@"MessageListSelectionModel",@"MailboxPickerController",@"MailboxListViewController",@"MailActionsViewController",@"EMMessageList",@"EMMessageListItemQuery",@"EMMessageRepository",@"EMMailboxRepository"]];
    NSMutableDictionary *classes=[NSMutableDictionary dictionary], *protocols=[NSMutableDictionary dictionary];
    NSMutableArray *missing=[NSMutableArray array];
    for(NSString *name in names) {
        Class cls=NSClassFromString(name);
        if(!cls) { [missing addObject:name]; continue; }
        for(Class c=cls;c && classes.count<48;c=class_getSuperclass(c)) {
            NSString *n=ROString(class_getName(c)); if(classes[n]) break;
            unsigned int count=0; Protocol *__unsafe_unretained *ps=class_copyProtocolList(c,&count);
            NSMutableArray *adopted=[NSMutableArray array];
            for(unsigned int i=0;i<count;i++) { [adopted addObject:ROString(protocol_getName(ps[i]))]; ROProtocol(ps[i],protocols); }
            free(ps); Class parent=class_getSuperclass(c);
            classes[n]=@{@"superclass":parent?ROString(class_getName(parent)):@"",@"protocols":adopted,@"instanceMethods":ROMethods(c),@"classMethods":ROMethods(object_getClass(c)),@"properties":ROProperties(c)};
        }
    }
    return @{@"classes":classes,@"protocols":protocols,@"missing":missing,@"classLimitReached":@(classes.count>=48),@"protocolLimitReached":@(protocols.count>=32),@"scope":@"Targeted declarations only; each ancestor/protocol deduplicated. Per-class limits explicit; unavailable Swift-only declarations not inferred."};
}
