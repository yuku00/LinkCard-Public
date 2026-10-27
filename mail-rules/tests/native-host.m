#import <Foundation/Foundation.h>
#import "NativeCore.h"
#import <assert.h>
@interface FixtureAddress:NSObject
@property(nonatomic,copy) NSString *stringValue;
@end
@implementation FixtureAddress
@end
@interface FixtureMessage:NSObject
@property(nonatomic,strong) NSArray *senderList;
@property(nonatomic,strong) NSArray *boxes;
@property(nonatomic,copy) NSString *itemID;
@property(nonatomic) BOOL isMessage;
@property(nonatomic) BOOL unread;
- (NSArray *)derivedSenders; // Deliberately not a declared property: old gate rejected this.
@end
@implementation FixtureMessage
- (NSArray *)derivedSenders {return self.senderList;}
@end
static id A(NSString *value) {FixtureAddress *a=[FixtureAddress new];a.stringValue=value;return a;}
static FixtureMessage *M(NSString *sender,NSString *account,NSString *box,NSString *itemID) {
    FixtureMessage *m=[FixtureMessage new];m.senderList=sender?@[A(sender)]:@[];
    m.boxes=@[@{@"account":account,@"mailbox":box}];m.itemID=itemID;m.isMessage=YES;m.unread=YES;return m;
}
static NSPredicate *P(NSString *s) {return [NSPredicate predicateWithFormat:@"ANY derivedSenders.stringValue ==[c] %@",s];}
static BOOL Batch(NSArray *items,NSArray *ids) {
    return MR5Batch(items,ids,@"A",[NSSet setWithObject:@"A-inbox"],P(@"same+tag@fixture.invalid"),^id(id x,NSString *key){return [x valueForKey:key];});
}
static MR5PredicateTransform DeferredTransform;
static NSArray *ExpectedFactory;
static BOOL ExpectedOldest,ExpectedDisplay;
static id FixtureFactory(id cls,SEL selector,id boxes,id repository,BOOL oldest,BOOL display,id sort,MR5PredicateTransform transform,id ignore) {
    assert(cls==ExpectedFactory[0] && selector==@selector(description));
    assert(boxes==ExpectedFactory[1] && repository==ExpectedFactory[2] && sort==ExpectedFactory[3] && ignore==ExpectedFactory[4]);
    assert(oldest==ExpectedOldest && display==ExpectedDisplay);
    DeferredTransform=[transform copy];
    return repository;
}
static void PrepareDeferredFactory(NSPredicate *local) {
    @autoreleasepool {
        NSString *key=[NSString stringWithFormat:@"%@%@",@"un",@"read"];
        MR5PredicateTransform transform=^NSPredicate *(NSPredicate *base) {
            return MR5And(base,[NSPredicate predicateWithFormat:@"%K == YES",key]);
        };
        id result=MR5InvokeFactory(FixtureFactory,ExpectedFactory[0],@selector(description),ExpectedFactory[1],ExpectedFactory[2],ExpectedOldest,ExpectedDisplay,ExpectedFactory[3],transform,ExpectedFactory[4],local);
        assert(result==ExpectedFactory[2]);
    }
}
static void ReleaseDeferred(void) {
#if !__has_feature(objc_arc)
    [DeferredTransform release];
#endif
    DeferredTransform=nil;
}
int main(void) {@autoreleasepool {
    assert([MR5Address(@" SAME+Tag@Fixture.Invalid ") isEqual:@"same+tag@fixture.invalid"]);
    assert(!MR5Address(@"Person <a@fixture.invalid>"));
    assert(!MR5Address(@"a@-invalid"));
    assert(![MR5Address(@"a.b@fixture.invalid") isEqual:MR5Address(@"ab@fixture.invalid")]);
    NSDictionary *id1=@{@"b":@[@"B",@2],@"a":[@"id" dataUsingEncoding:NSUTF8StringEncoding]};
    NSDictionary *id2=@{@"a":[@"id" dataUsingEncoding:NSUTF8StringEncoding],@"b":@[@"B",@2]};
    assert([MR5Identity(id1) isEqual:MR5Identity(id2)]);
    assert(![MR5Identity(@"1") isEqual:MR5Identity(@1)]);
    BOOL (^validate)(NSPredicate *)=^BOOL(NSPredicate *p){return MR5SenderContract(p,@"same+tag@fixture.invalid",^id(NSString *s){return A(s);},^id(NSArray *senders){FixtureMessage *m=[FixtureMessage new];m.senderList=senders;return m;});};
    assert(validate(P(@"same+tag@fixture.invalid")));
    assert(!validate([NSPredicate predicateWithFormat:@"ANY derivedSenders.stringValue CONTAINS[c] %@",@"same"]));
    assert(!validate([NSPredicate predicateWithFormat:@"ANY derivedSenders.stringValue == %@",@"same+tag@fixture.invalid"]));
    assert(!validate([NSPredicate predicateWithValue:YES]));
    assert(!MR5SenderContract(P(@"same+tag@fixture.invalid"),@"same+tag@fixture.invalid",^id(NSString *s){return nil;},^id(NSArray *a){return nil;}));
    NSDictionary *r=@{@"account":@"A",@"mailbox":@"A-inbox",@"scope":@"mailbox",@"sender":@"same+tag@fixture.invalid",@"enabled":@YES};
    assert(MR5RulesForBox(@[r],@"A",@"A-inbox").count==1);
    assert(!MR5RulesForBox(@[r],@"B",@"B-inbox").count);
    assert(!MR5RulesForBox(@[r],@"A",@"A-archive").count);
    NSMutableDictionary *accountRule=[r mutableCopy];accountRule[@"scope"]=@"account";
    assert(MR5RulesForBox(@[accountRule],@"A",@"A-archive").count==1);
    accountRule[@"enabled"]=@NO;
    assert(!MR5RulesForBox(@[accountRule],@"A",@"A-inbox").count);
    FixtureMessage *hidden=M(@"same+tag@fixture.invalid",@"A",@"A-inbox",@"m1");
    FixtureMessage *other=M(@"other@fixture.invalid",@"A",@"A-inbox",@"m2");
    FixtureMessage *otherAccount=M(@"same+tag@fixture.invalid",@"B",@"B-inbox",@"m3");
    FixtureMessage *otherBox=M(@"same+tag@fixture.invalid",@"A",@"A-archive",@"m4");
    NSPredicate *scope=[NSPredicate predicateWithFormat:@"ANY boxes.mailbox IN %@",@[@"A-inbox",@"B-inbox"]];
    NSPredicate *aScope=[NSPredicate predicateWithFormat:@"ANY boxes.mailbox == %@",@"A-inbox"];
    NSPredicate *exclude=[NSCompoundPredicate notPredicateWithSubpredicate:MR5And(aScope,P(@"same+tag@fixture.invalid"))];
    ExpectedFactory=@[[NSObject new],@[@"A-inbox"],[NSObject new],[NSObject new],[NSObject new]];
    ExpectedOldest=YES;ExpectedDisplay=NO;
    PrepareDeferredFactory(exclude);
    assert(![DeferredTransform(scope) evaluateWithObject:hidden]);
    assert([DeferredTransform(scope) evaluateWithObject:other]);
    other.unread=NO;assert(![DeferredTransform(scope) evaluateWithObject:other]);other.unread=YES;
    ReleaseDeferred();
    ExpectedOldest=NO;ExpectedDisplay=YES;
    PrepareDeferredFactory(nil);
    assert([DeferredTransform(scope) evaluateWithObject:hidden]);ReleaseDeferred();
    __block NSUInteger transforms=0;
    NSPredicate *(^original)(NSPredicate *)=^NSPredicate *(NSPredicate *base){transforms++;return MR5And(base,[NSPredicate predicateWithFormat:@"unread == YES"]);};
    NSPredicate *query=MR5Transform(scope,original,exclude);
    assert(transforms==1);
    assert(![query evaluateWithObject:hidden]);assert([query evaluateWithObject:other]);
    assert([query evaluateWithObject:otherAccount]);assert(![query evaluateWithObject:otherBox]);
    other.unread=NO;assert(![query evaluateWithObject:other]);other.unread=YES;
    // Mixed conversation: process each member's message, never its representative sender.
    NSArray *threadMembers=@[hidden,other];NSArray *visible=[threadMembers filteredArrayUsingPredicate:query];
    assert(visible.count==1 && visible.firstObject==other && [other.itemID isEqual:@"m2"]);
    FixtureMessage *arrived=M(@"SAME+TAG@fixture.invalid",@"A",@"A-inbox",@"m5");
    assert(![query evaluateWithObject:arrived]);
    NSPredicate *restored=MR5Transform(scope,nil,nil);assert(restored==scope);
    assert([restored evaluateWithObject:hidden]);
    NSPredicate *(^widen)(NSPredicate *)=^NSPredicate *(NSPredicate *p){return [NSCompoundPredicate orPredicateWithSubpredicates:@[p,[NSPredicate predicateWithValue:YES]]];};
    assert(![MR5Transform(scope,widen,exclude) evaluateWithObject:otherBox]);
    NSObject *ownerA=[NSObject new],*ownerB=[NSObject new];
    assert(!MR5Context(ownerA,ownerA,@[],@[]));
    assert(!MR5Context(nil,nil,@[@"A-inbox"],@[@"A-inbox"]));
    assert(MR5Context(ownerA,ownerA,@[@"A-inbox"],@[@"A-inbox"]));
    assert(!MR5Context(ownerB,ownerA,@[@"B-inbox"],@[@"A-inbox"]));
    assert(!MR5Context(ownerA,ownerA,@[@"A-archive"],@[@"A-inbox"]));
    // B has no rules: no original predicate from A is present in this invocation.
    NSPredicate *bScope=[NSPredicate predicateWithFormat:@"ANY boxes.mailbox == %@",@"B-inbox"];
    assert(MR5Transform(bScope,nil,nil)==bScope);
    assert(Batch(@[hidden,arrived],@[@"m1",@"m5"]));
    assert(!Batch(@[hidden,other],@[@"m1",@"m2"]));
    assert(!Batch(@[hidden,otherAccount],@[@"m1",@"m3"]));
    assert(!Batch(@[otherBox],@[@"m4"]));
    assert(!Batch(@[hidden,hidden],@[@"m1",@"m1"]));
    assert(!Batch(@[hidden],@[@"different-id"]));
    hidden.isMessage=NO;assert(!Batch(@[hidden],@[@"m1"]));hidden.isMessage=YES;
    id interaction=[NSObject new];__block NSUInteger calls=0,completions=0;
    NSMutableArray *states=[NSMutableArray array];
    void (^report)(NSString *)=^(NSString *s){[states addObject:s];};
    MR5Perform(NO,interaction,^(void (^done)(id,BOOL)){calls++;done(interaction,YES);},report,^(id result,BOOL performed){assert(result==interaction && !performed);completions++;});
    assert(!calls && completions==1 && [states isEqual:@[@"blocked"]]);
    [states removeAllObjects];
    MR5Perform(YES,interaction,^(void (^done)(id,BOOL)){calls++;done(interaction,NO);},report,nil);
    assert(calls==1 && [states isEqual:(@[@"handedOff",@"notPerformed"])]);
    [states removeAllObjects];
    MR5Perform(YES,interaction,^(void (^done)(id,BOOL)){calls++;done(interaction,YES);},report,nil);
    assert(calls==2 && [states isEqual:(@[@"handedOff",@"pendingSync"])] && ![states containsObject:@"completed"]);
    [states removeAllObjects];
    __block void (^deferredDone)(id,BOOL)=nil;
    __block NSUInteger exactlyOnce=0;
    MR5Perform(YES,interaction,^(void (^done)(id,BOOL)){deferredDone=[done copy];},report,^(id result,BOOL performed){
        assert(result==interaction && performed);exactlyOnce++;
        deferredDone(interaction,NO); // Reentrant duplicate must not escape.
    });
    deferredDone(interaction,YES);deferredDone(interaction,NO);
    assert(exactlyOnce==1 && [states isEqual:(@[@"handedOff",@"pendingSync"])]);
#if !__has_feature(objc_arc)
    [deferredDone release];
#endif
    deferredDone=nil;
    puts("PASS production NativeCore: scoped native-shaped queries, ANY/case, derived getters, multi-owner, exact IDs, mixed-thread members, new arrivals, restore, explicit batch, deferred factory parameters/ownership and once-only reentrant native results");
}return 0;}
