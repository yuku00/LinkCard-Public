#import <Foundation/Foundation.h>

@class UIView;
NS_ASSUME_NONNULL_BEGIN
/* Use the existing Appearance Input/InputWindow hooks; do not double-install them. */
FOUNDATION_EXPORT void WURefreshDictation(UIView *view);
/* Called on main thread after Core's configuration/hook registry initialization. */
FOUNDATION_EXPORT void WUInstallDictation(void);
/* Availability includes observed concrete icon compatibility, not just a switch. */
FOUNDATION_EXPORT BOOL WUDictationAvailable(NSString *key);
FOUNDATION_EXPORT NSString *const WUDictationHideKey;
FOUNDATION_EXPORT NSString *const WUDictationGuardKey;
NS_ASSUME_NONNULL_END
