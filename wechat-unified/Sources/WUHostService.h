#import <Foundation/Foundation.h>

// Resolves a fresh provider on every call; never retains a context or service.
id WUHostService(NSString *name);
typedef enum { WUProviderUnknown, WUProviderActive, WUProviderCurrent, WUProviderLegacy } WUProviderPath;
id WUHostServiceWithPath(NSString *name, WUProviderPath *path);
void WURecordAccountServiceMismatch(id service, WUProviderPath path);
NSString *WUAccountServiceDiagnosticSnapshot(void);
// Only the verified getSelfContact object-returning ABI may use proxy forwarding.
BOOL WUAccountServiceHasSelfContact(id service);
