#import "ReadOnly.h"

NSString *ROType(id object) {
    if(!object) return @"nil";
    const char *name=class_getName(object_getClass(object));
    return name ? [NSString stringWithUTF8String:name] : @"unknown";
}
BOOL ROIsKind(id object, Class cls) {
    for(Class c=object_getClass(object);c;c=class_getSuperclass(c)) if(c==cls) return YES;
    return NO;
}
NSString *ROPageRole(NSArray<NSString *> *types, BOOL hasList) {
    BOOL messageList=NO,mailboxHome=NO;
    for(NSString *name in types) {
        for(Class c=NSClassFromString(name);c;c=class_getSuperclass(c)) {
            NSString *n=[NSString stringWithUTF8String:class_getName(c)];
            if([n containsString:@"MailboxPicker"] || [n containsString:@"Transfer"] || [n containsString:@"MailboxSelection"])
                return @"mailbox-picker-not-message-list";
            if([n isEqualToString:@"MessageListViewController"] || [n isEqualToString:@"MailboxContentViewController"])
                messageList=YES;
            if([n containsString:@"MailboxList"] || [n containsString:@"MailboxesViewController"]) mailboxHome=YES;
        }
    }
    if(messageList && hasList) return @"message-list-candidate-not-verified-inbox";
    if(mailboxHome) return @"mailbox-home";
    return @"other-or-unverified-native-page";
}

@interface ROSession ()
@property(nonatomic,readwrite) BOOL active;
@property(nonatomic,readwrite) BOOL paused;
@property(nonatomic,readwrite) NSUInteger generation;
@property(nonatomic,readwrite) NSString *pageRole;
@property(nonatomic,strong) NSMapTable *identifiers;
@property(nonatomic,strong) NSMutableArray *stages;
@property(nonatomic,strong) NSMutableDictionary *events;
@property(nonatomic,strong) NSMutableOrderedSet *types;
@property(nonatomic,strong) NSDictionary *lastGraph;
@property(nonatomic) NSUInteger serial;
@property(nonatomic) NSUInteger omittedStages;
@end
@implementation ROSession
- (instancetype)init {
    if((self=[super init])) {
        _identifiers=[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory];
        _stages=[NSMutableArray array]; _events=[NSMutableDictionary dictionary]; _types=[NSMutableOrderedSet orderedSet];
        _pageRole=@"not-captured";
    } return self;
}
- (NSUInteger)stageCount { return self.stages.count; }
- (void)start { [self clear]; self.active=YES; }
- (void)pause { self.paused=YES; self.generation++; }
- (void)resume { self.paused=NO; self.generation++; }
- (void)stop { self.active=NO; self.paused=NO; self.generation++; }
- (void)clear {
    [self stop]; [self.identifiers removeAllObjects]; [self.stages removeAllObjects]; [self.events removeAllObjects]; [self.types removeAllObjects];
    self.serial=0; self.omittedStages=0; self.lastGraph=nil; self.pageRole=@"not-captured";
}
- (NSString *)identifier:(id)object {
    if(!object) return @"none";
    NSString *identifier=[self.identifiers objectForKey:object];
    if(!identifier) { identifier=[NSString stringWithFormat:@"o%lu",(unsigned long)++self.serial]; [self.identifiers setObject:identifier forKey:object]; }
    return identifier;
}
- (void)eventOwner:(id)owner argument:(id)argument {
    if(!self.active || self.paused) return;
    // Aggregate by type, not event contents or addresses. No event retained.
    NSString *ownerType=ROType(owner), *argumentType=ROType(argument);
    NSString *key=[ownerType stringByAppendingFormat:@"/%@",argumentType];
    NSDictionary *old=self.events[key];
    if(!old && self.events.count>=16) return;
    self.events[key]=@{@"method":@"sendEvent:",@"abi":@"v24@0:8@16",@"owner": [self identifier:owner],@"ownerType":ownerType,@"argumentType":argumentType,@"relation":@"argument-delivered-to-owner",@"valuesRead":@NO,@"count":@([old[@"count"] unsignedIntegerValue]+1)};
}
- (void)record:(NSDictionary *)graph label:(NSString *)label automatic:(BOOL)automatic {
    if(!self.active || self.paused || !graph) return;
    self.pageRole=graph[@"pageRole"] ?: @"unknown";
    if(automatic && [graph isEqual:self.lastGraph]) return;
    // Reserve eight slots for explicit stage marks even during many natural events.
    if(self.stages.count >= (automatic?16:24)) { self.omittedStages++; return; }
    self.lastGraph=graph;
    [self.types addObjectsFromArray:graph[@"types"] ?: @[]];
    [self.stages addObject:@{@"index":@(self.stages.count+1),@"label":label,@"source":automatic?@"public-event-settled-snapshot":@"user-stage-mark",@"graph":graph}];
}
- (NSDictionary *)document:(NSString *)observerStatus {
    return @{@"name":@"Mail Read-only Probe",@"version":RO_VERSION,@"production":RO_MODULES,@"observer":observerStatus ?: @"unavailable-manual-stages-only",@"privateBusinessHooks":@[],@"predicateInspection":@"none; constants and values are never read",@"fieldWhitelist":@[],@"active":@(self.active),@"stages":[self.stages copy],@"publicEventCalls":[self.events.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"ownerType"] compare:b[@"ownerType"]];}],@"metadata":ROMetadata(self.types.array),@"limits":@{@"stages":@24,@"automaticStageCeiling":@16,@"nodesPerStage":@180,@"edgesPerStage":@400,@"depth":@16,@"omittedStages":@(self.omittedStages)},@"evidence":@"Public UIKit graph and targeted class/protocol declarations only. Stage labels are user intent, not proof of selection/filter/refresh or inbox identity. Event counts are sendEvent calls, not business calls. MailboxPicker is not a message list. No private owner getters, query execution, selection writes, predicate values, UI text, account values or automatic upload. Swift-only storage is not inspected. Actual inbox identity and business completion remain unverified."};
}
@end
