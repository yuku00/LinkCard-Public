#import "WU.h"
#import "WUNativeLogic.h"
BOOL WUNativeValidOptions(id value);
BOOL WUNativeEnabled(NSString *key);
BOOL WUNativeSave(NSString *key, BOOL on);
BOOL WUNativeAvailable(NSString *key);
void WUInstallNative(void);
void WUShowNativeSettings(UIViewController *owner);
/* Core calls this once before ANY plugin hooks, with its own config-directory fd. */
BOOL WUNativeStartGuard(int configDirectory);
BOOL WUNativeGuardAllowsHooks(void);
BOOL WUNativeGuardReady(void);
BOOL WUNativeSafeModeArmed(void);
BOOL WUNativeResetGuard(void);
NSString *WUNativeGuardStatus(void);
void WUNativeGuardLifecycle(BOOL active); // same production entry used by synthetic lifecycle tests

/* Core's WUHook calls this once after a successful installation; slot has static lifetime. */
void WUNativeRecordHook(Class cls, SEL selector, IMP replacement, IMP *originalSlot);
BOOL WUNativeHasRegisteredHooks(void);
BOOL WUNativeRebaseOwnedHook(Class cls, SEL selector, IMP expectedOriginal, IMP verifiedHost);
void WUInstallNativeInteractions(void);
BOOL WUNativeInteractionAvailable(NSString *key);
void WUInstallNativeGames(void);
BOOL WUNativeGameAvailable(void);
BOOL WUNativeApplyGameChoice(id wrap, unsigned type, unsigned choice);
unsigned WUNativeGameNumber(id object, NSString *selector);
