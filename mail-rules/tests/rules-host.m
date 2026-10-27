#import <Foundation/Foundation.h>
#import "RuleCore.h"
@interface FixtureAddress : NSObject
@property(copy) NSString *stringValue;
@end
@implementation FixtureAddress
- (BOOL)isEqual:(id)o {return [o isKindOfClass:FixtureAddress.class] && [self.stringValue isEqual:[o stringValue]];}
- (NSUInteger)hash {return self.stringValue.hash;}
@end
static id Address(NSString *s) {FixtureAddress *a=[FixtureAddress new]; a.stringValue=MRNormalize(s); return a;}
int main(void) { @autoreleasepool {
    assert([MRNormalize(@" A.B+tag@EXAMPLE.COM ") isEqual:@"A.B+tag@example.com"]);
    for(NSString *bad in @[@"",@"a",@"a@@b",@"Name <a@b>",@"a b@c",@".a@b",@"a..b@c",@"a@-b"]) assert(!MRNormalize(bad));
    for(NSUInteger n=0;n<4;n++) for(int i=0;i<2;i++) for(int s=0;s<2;s++) for(int t=0;t<2;t++) for(int q=0;q<2;q++) assert(MRScope(i,s,n,t,q)==(i && !s && n==1 && !t && !q));
    NSString *address=@"mr.fixture+keep@fixture.invalid";
    NSPredicate *include=[NSPredicate predicateWithFormat:@"senderAddress == %@",Address(address)];
    assert(MRValidateSenderPredicate(include,address,^id(NSString *s){return Address(s);}));
    NSPredicate *any=[NSPredicate predicateWithFormat:@"ANY senderList == %@",Address(address)];
    assert(MRValidateSenderPredicate(any,address,^id(NSString *s){return Address(s);}));
    for(NSPredicate *bad in @[[NSPredicate predicateWithFormat:@"senderAddress.stringValue CONTAINS %@",address], [NSPredicate predicateWithFormat:@"senderAddress.stringValue ==[c] %@",address], [NSPredicate predicateWithFormat:@"subject == %@",address], [NSPredicate predicateWithFormat:@"senderAddress.stringValue BEGINSWITH %@",address], [NSPredicate predicateWithValue:YES]]) assert(!MRValidateSenderPredicate(bad,address,^id(NSString *s){return Address(s);}));
    NSPredicate *base=[NSPredicate predicateWithFormat:@"unread == YES"], *ignore=[NSPredicate predicateWithFormat:@"ignored == YES"];
    NSPredicate *exclude=[NSCompoundPredicate notPredicateWithSubpredicate:include];
    NSPredicate *combined=MRCombine(base,exclude);
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
