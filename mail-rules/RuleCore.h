#import <Foundation/Foundation.h>
NSString *MRNormalize(NSString *input);
BOOL MRScope(BOOL inbox, BOOL smart, NSUInteger count, BOOL threaded, BOOL search);
NSPredicate *MRCombine(NSPredicate *original, NSPredicate *exclude);
BOOL MRValidateSenderPredicate(NSPredicate *predicate, NSString *address, id (^addressObject)(NSString *));
