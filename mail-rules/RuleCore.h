#import <Foundation/Foundation.h>
BOOL MRContextMatches(id owner, id source, id currentSource, NSString *account, NSString *currentAccount, id mailbox, id currentMailbox);
BOOL MRValidateNativeSenderPredicate(NSPredicate *predicate, NSString *address, id (^addressObject)(NSString *), id (^messageObject)(NSArray *));
NSString *MRReadAddress(id convertible);
NSString *MRIdentityKey(id representation, NSMutableDictionary *identities);
NSString *MRNormalize(NSString *input);
BOOL MRScope(BOOL inbox, BOOL smart, NSUInteger count, BOOL threaded, BOOL search);
NSPredicate *MRCombine(NSPredicate *original, NSPredicate *exclude);
NSPredicate *MRCombineSection(NSPredicate *original, NSPredicate *exclude, NSString *section);
BOOL MRValidateSenderPredicate(NSPredicate *predicate, NSString *address, id (^addressObject)(NSString *));
BOOL MRValidateSenderPredicateWithModel(NSPredicate *predicate, NSString *address, id (^addressObject)(NSString *), id (^messageObject)(NSArray *));
