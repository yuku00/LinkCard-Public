#import <Foundation/Foundation.h>
BOOL WURepositoryValid(id items);
NSArray *WURepositoryLoad(NSURL *directory, NSString *account, NSError **error);
BOOL WURepositorySave(NSURL *directory, NSString *account, NSArray *items, NSError **error);
// Status describes local invocation only; never delivery.
NSString *WURepositoryInvoke(id receiver, NSString *selector, id first, id second);
BOOL WURepositoryCanInvoke(id receiver, NSString *selector);
