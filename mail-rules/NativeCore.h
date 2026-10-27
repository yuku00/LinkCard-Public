#import <Foundation/Foundation.h>
// Shared production semantics, exercised with Foundation/native-shaped models.
NSString *MR5Address(NSString *value);
NSString *MR5Identity(id serialized);
NSPredicate *MR5And(NSPredicate *a, NSPredicate *b);
typedef NSPredicate *(^MR5PredicateTransform)(NSPredicate *);
typedef id (*MR5ListFactory)(id,SEL,id,id,BOOL,BOOL,id,MR5PredicateTransform,id);
id MR5InvokeFactory(MR5ListFactory factory,id cls,SEL selector,id boxes,id repository,BOOL oldest,BOOL display,id sort,MR5PredicateTransform transform,id ignore,NSPredicate *local);
NSPredicate *MR5Transform(NSPredicate *base, NSPredicate *(^original)(NSPredicate *), NSPredicate *local);
BOOL MR5SenderContract(NSPredicate *predicate, NSString *address, id (^makeAddress)(NSString *), id (^makeMessage)(NSArray *));
NSArray *MR5RulesForBox(NSArray *rules, NSString *account, NSString *mailbox);
BOOL MR5Batch(NSArray *items, NSArray *expectedIDs, NSString *account, NSSet *sourceBoxes, NSPredicate *sender, id (^read)(id,NSString *));
BOOL MR5Context(id owner, id expectedOwner, NSArray *boxes, NSArray *expectedBoxes);
// Submission labels are deliberately not server-success receipts.
void MR5Perform(BOOL allowed, id interaction, void (^native)(void (^)(id,BOOL)), void (^report)(NSString *), void (^completion)(id,BOOL));
