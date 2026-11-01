#import <Foundation/Foundation.h>
// Nonnegative message types; only the explicit i/I/q/Q constructor shapes are supported.
BOOL WUMessageCanConstruct(Class messageClass);
id WUCreateMessage(Class messageClass, uint64_t type, NSString *account);
