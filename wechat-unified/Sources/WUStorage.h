#import <Foundation/Foundation.h>
// Call once before registering any plugin hooks. Failure never falls back to old data.
BOOL WUStorageInitialize(void);
NSURL *WUStorageEnvelope(void);
NSURL *WUStorageRoot(void);
NSURL *WUStorageEmoticons(void);
NSString *WUStorageFailure(void);
BOOL WUStorageMayCreateSeparate(void);
// Only call from an explicit confirmation; restart the host after success.
BOOL WUStorageCreateSeparate(void);
// Persisted v3 provenance: defaults were created after verified zero-file legacy remnants.
NSString *WUStorageRecoveryNotice(void);
