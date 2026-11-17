#import <Foundation/Foundation.h>
// Call once before registering any plugin hooks. Failure never falls back to old data.
BOOL WUStorageInitialize(void);
NSURL *WUStorageEnvelope(void);
NSURL *WUStorageRoot(void);
NSURL *WUStorageEmoticons(void);
NSString *WUStorageFailure(void);
// Persisted v3 provenance: defaults were created after verified zero-file legacy remnants.
NSString *WUStorageRecoveryNotice(void);
