#import <Foundation/Foundation.h>
// Nonnegative message types; only the explicit i/I/q/Q constructor shapes are supported.
BOOL WUMessageCanConstruct(Class messageClass);
id WUCreateMessage(Class messageClass, uint64_t type, NSString *account);
// Voice only: try the verified one-argument initializer if the preferred initializer
// is unavailable or returns nil. The caller must populate and validate from/to fields.
id WUCreateVoiceMessage(Class messageClass, uint64_t type, NSString *account);
