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
// Current provenance is available even when it is not a startup event.
NSString *WUStorageRecoveryNotice(void);
BOOL WUStorageShouldPresentRecoveryNotice(void);
NSString *WUStorageDiagnosticSummary(void);
