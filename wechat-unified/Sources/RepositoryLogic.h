#import <Foundation/Foundation.h>
BOOL WURepositoryValid(id items);
NSArray *WURepositoryLoad(NSURL *directory, NSString *account, NSError **error);
BOOL WURepositorySave(NSURL *directory, NSString *account, NSArray *items, NSError **error);
// Status describes local invocation only; never delivery.
NSString *WURepositoryInvoke(id receiver, NSString *selector, id first, id second);
BOOL WURepositoryCanInvoke(id receiver, NSString *selector);
// The caller constructs a fresh type-1 wrap and supplies a context recheck.
NSString *WURepositorySendText(id manager, id sessionManager, id wrap, NSString *account, NSString *target, NSString *text, BOOL (^current)(void));
// A fast-forwarded service is accepted only when it forwards to the declared host class.
BOOL WURepositoryFastService(id receiver, NSString *hostName, NSString *selector, const char *result, NSArray<NSString *> *arguments);
id WURepositoryContact(id contacts, NSString *target);
