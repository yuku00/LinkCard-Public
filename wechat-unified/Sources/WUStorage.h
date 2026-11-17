#import <Foundation/Foundation.h>
// Call once before registering any plugin hooks. Failure never falls back to old data.
BOOL WUStorageInitialize(void);
NSURL *WUStorageEnvelope(void);
NSURL *WUStorageRoot(void);
NSURL *WUStorageEmoticons(void);
NSString *WUStorageFailure(void);
