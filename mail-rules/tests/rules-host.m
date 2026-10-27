#import <Foundation/Foundation.h>
#import "RuleCore.h"
@interface FixtureAddress : NSObject
@property(copy) NSString *stringValue;
@property(readonly) FixtureAddress *emailAddressValue;
@property(readonly) NSString *simpleAddress;
@end
@implementation FixtureAddress
- (FixtureAddress *)emailAddressValue { return self; }
- (NSString *)simpleAddress { return self.stringValue; }
- (BOOL)isEqual:(id)o {return [o isKindOfClass:FixtureAddress.class] && [self.stringValue isEqual:[o stringValue]];}
- (NSUInteger)hash {return self.stringValue.hash;}
@end
@interface ForwardedAddress : NSProxy
@property(strong) FixtureAddress *target;
@end
@implementation ForwardedAddress
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector { return [self.target methodSignatureForSelector:selector]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.target]; }
@end
@interface FixtureMessage : NSObject
@property(copy) NSArray *senderList;
@property(readonly) id senderAddress;
@property(readonly) NSArray *fixtureDerivedSenders;
@property(readonly) NSArray *recipientValues;
@end
@implementation FixtureMessage
- (id)senderAddress {return self.senderList.firstObject;}
- (NSArray *)fixtureDerivedSenders {return [self.senderList valueForKey:@"stringValue"];}
- (NSArray *)recipientValues {return @[@"mr.fixture+keep@fixture.invalid"];}
@end
static id Message(NSArray *senders) {FixtureMessage *m=[FixtureMessage new];m.senderList=senders;return m;}
static id Address(NSString *s) {FixtureAddress *a=[FixtureAddress new]; a.stringValue=MRNormalize(s); return a;}
int main(void) { @autoreleasepool {
    NSMutableDictionary *identities=[NSMutableDictionary dictionary];
    NSDictionary *serialized=@{@"id":@"fixture-account-A",@"type":@1};
    NSString *key=MRIdentityKey(serialized,identities);
    assert(key.length && [MRIdentityKey([serialized copy],identities) isEqual:key]);
    NSData *stored=[NSPropertyListSerialization dataWithPropertyList:identities format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    NSMutableDictionary *reloaded=[NSPropertyListSerialization propertyListWithData:stored options:NSPropertyListMutableContainers format:NULL error:NULL];
    assert([MRIdentityKey(serialized,reloaded) isEqual:key]);
    assert(![MRIdentityKey(@{@"id":@"fixture-account-B"},reloaded) isEqual:key]);
    assert(!MRIdentityKey(nil,reloaded) && !MRIdentityKey([NSObject new],reloaded));
    assert(!MRIdentityKey(@{},reloaded) && !MRIdentityKey(@"",reloaded));
    NSMutableDictionary *ambiguous=[reloaded mutableCopy]; ambiguous[@"object:duplicate"]=serialized;
    assert(!MRIdentityKey(serialized,ambiguous));
    NSObject *owner=[NSObject new], *source=[NSObject new], *boxA=[NSObject new], *boxB=[NSObject new];
    assert(MRContextMatches(owner,source,source,@"A",@"A",boxA,boxA));
    assert(!MRContextMatches(owner,source,source,@"A",@"B",boxA,boxB));
    assert(!MRContextMatches(owner,source,source,@"A",@"A",boxA,boxB));
    assert(!MRContextMatches(owner,source,[NSObject new],@"A",@"A",boxA,boxA));
    assert(!MRContextMatches(nil,source,source,@"A",@"A",boxA,boxA));
    assert(!MRContextMatches(owner,source,source,@"A",nil,boxA,boxA));
    ForwardedAddress *forwarded=[ForwardedAddress alloc]; forwarded.target=Address(@"A.B+tag@EXAMPLE.COM");
    assert([MRReadAddress(forwarded) isEqual:@"A.B+tag@example.com"]);
    assert(!MRReadAddress(nil) && !MRReadAddress(@42));
    assert([MRNormalize(@" A.B+tag@EXAMPLE.COM ") isEqual:@"A.B+tag@example.com"]);
    for(NSString *bad in @[@"",@"a",@"a@@b",@"Name <a@b>",@"a b@c",@".a@b",@"a..b@c",@"a@-b"]) assert(!MRNormalize(bad));
    for(NSUInteger n=0;n<4;n++) for(int i=0;i<2;i++) for(int s=0;s<2;s++) for(int t=0;t<2;t++) for(int q=0;q<2;q++) assert(MRScope(i,s,n,t,q)==(i && !s && n==1 && !t && !q));
    NSString *address=@"mr.fixture+keep@fixture.invalid";
    NSPredicate *include=[NSPredicate predicateWithFormat:@"senderAddress == %@",Address(address)];
    assert(MRValidateSenderPredicate(include,address,^id(NSString *s){return Address(s);}));
    NSPredicate *any=[NSPredicate predicateWithFormat:@"ANY senderList == %@",Address(address)];
    assert(MRValidateSenderPredicate(any,address,^id(NSString *s){return Address(s);}));
    for(NSPredicate *bad in @[[NSPredicate predicateWithFormat:@"senderAddress.stringValue CONTAINS %@",address], [NSPredicate predicateWithFormat:@"senderAddress.stringValue ==[c] %@",address], [NSPredicate predicateWithFormat:@"subject == %@",address], [NSPredicate predicateWithFormat:@"senderAddress.stringValue BEGINSWITH %@",address], [NSPredicate predicateWithValue:YES]]) assert(!MRValidateSenderPredicate(bad,address,^id(NSString *s){return Address(s);}));
    assert(NSAnyPredicateModifier==2 && NSEqualToPredicateOperatorType==4 && NSCaseInsensitivePredicateOption==1);
    NSPredicate *nativeShape=[NSPredicate predicateWithFormat:@"ANY senderList.emailAddressValue.simpleAddress ==[c] %@",address];
    assert(MRValidateSenderPredicateWithModel(nativeShape,address,^id(NSString *s){return Address(s);},^id(NSArray *senders){return Message(senders);}));
    assert([nativeShape evaluateWithObject:Message(@[Address(@"other@fixture.invalid"),Address([address uppercaseString])])]);
    assert(![nativeShape evaluateWithObject:Message(@[Address(@"other@fixture.invalid"),Address(@"prefixmr.fixture+keep@fixture.invalid")])]);
    assert(!MRValidateSenderPredicateWithModel(nativeShape,address,^id(NSString *s){return Address(s);},^id(NSArray *senders){return nil;}));
    NSPredicate *derived=[NSPredicate predicateWithFormat:@"ANY fixtureDerivedSenders ==[c] %@",address];
    assert(MRValidateNativeSenderPredicate(derived,address,^id(NSString *s){return Address(s);},^id(NSArray *senders){return Message(senders);}));
    assert(!MRValidateSenderPredicateWithModel(derived,address,^id(NSString *s){return Address(s);},^id(NSArray *senders){return Message(senders);}));
    for (NSString *keyPath in @[@"recipientValues",@"notADeclaredField",@"senderList.@count",@"senderList.description"]) {
        NSPredicate *bad=[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForKeyPath:keyPath] rightExpression:[NSExpression expressionForConstantValue:address] modifier:NSAnyPredicateModifier type:NSEqualToPredicateOperatorType options:NSCaseInsensitivePredicateOption];
        assert(!MRValidateNativeSenderPredicate(bad,address,^id(NSString *s){return Address(s);},^id(NSArray *senders){return Message(senders);}));
    }
    for (NSComparisonPredicateOptions options=2;options<8;options++) {
        NSPredicate *bad=[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForKeyPath:@"senderList.emailAddressValue.simpleAddress"] rightExpression:[NSExpression expressionForConstantValue:address] modifier:NSAnyPredicateModifier type:NSEqualToPredicateOperatorType options:options];
        assert(!MRValidateSenderPredicate(bad,address,^id(NSString *s){return Address(s);}));
    }
    for (NSString *badKey in @[@"toList.emailAddressValue.simpleAddress", @"senderList.displayName", @"senderList.@count", @"accountIdentifier", @"subject"]) {
        NSPredicate *bad=[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForKeyPath:badKey] rightExpression:[NSExpression expressionForConstantValue:address] modifier:NSAnyPredicateModifier type:NSEqualToPredicateOperatorType options:NSCaseInsensitivePredicateOption];
        assert(!MRValidateSenderPredicate(bad,address,^id(NSString *s){return Address(s);}));
    }
    NSPredicate *base=[NSPredicate predicateWithFormat:@"unread == YES"], *ignore=[NSPredicate predicateWithFormat:@"ignored == YES"];
    NSPredicate *exclude=[NSCompoundPredicate notPredicateWithSubpredicate:include];
    NSPredicate *combined=MRCombine(base,exclude);
    assert(MRCombineSection(base,exclude,@"OtherSection")==base);
    assert(MRCombineSection(base,exclude,nil)==base);
    assert([MRCombineSection(base,exclude,@"MessageListSectionRecent") isEqual:combined]);
    // The same guard used by production restore must not replay A's baseline into B.
    NSPredicate *bBase=[NSPredicate predicateWithFormat:@"unread == NO"];
    NSPredicate *restored=MRContextMatches(owner,source,source,@"A",@"B",boxA,boxB) ? base : bBase;
    assert(restored==bBase);
    restored=MRContextMatches(owner,source,source,@"A",@"A",boxA,boxA) ? base : bBase;
    assert(restored==base);
    NSDictionary *hidden=@{@"senderAddress":Address(address),@"unread":@YES,@"ignored":@NO};
    NSDictionary *visible=@{@"senderAddress":Address(@"other@fixture.invalid"),@"unread":@YES,@"ignored":@NO};
    assert(![combined evaluateWithObject:hidden]); assert([combined evaluateWithObject:visible]);
    assert(MRCombine(base,nil)==base); assert(![ignore evaluateWithObject:visible]);
    NSMutableArray *loaded=[NSMutableArray arrayWithObject:visible]; assert([loaded filteredArrayUsingPredicate:combined].count==1);
    [loaded addObject:hidden]; assert([loaded filteredArrayUsingPredicate:combined].count==1);
    assert([loaded filteredArrayUsingPredicate:MRCombine(base,nil)].count==2);
    NSDictionary *accounts=@{@"account-A":@{@"enabled":@YES,@"rules":@[address]},@"account-B":@{@"enabled":@NO,@"rules":@[]}};
    assert([accounts[@"account-A"][@"rules"] count]==1); assert(![accounts[@"account-B"][@"enabled"] boolValue]); assert([accounts[@"account-B"][@"rules"] count]==0);
    puts("PASS: normalization, 64 scope combinations, exact predicate AST/fixtures, original filter restoration, ignore preservation, new arrival reevaluation, account isolation");
} return 0; }
