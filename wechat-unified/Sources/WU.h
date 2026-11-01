#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
@class UINavigationController;
BOOL WUEnabled(NSString *key);
BOOL WUSave(NSString *key, id value);
id WUValue(NSString *key);
BOOL WUMatches(Method method, const char *result, NSArray<NSString *> *arguments);
BOOL WUHook(NSString *className, NSString *selector, BOOL meta, const char *result, NSArray<NSString *> *arguments, IMP replacement, IMP *original);
NSArray<NSString *> *WUHookStatus(void);
void WUInstallVoice(void);
void WUCancelVoice(void);
BOOL WUVoiceAvailable(NSString *key);
void WUInstallAds(void);
BOOL WUAdsAvailable(NSString *key);
void WUInstallMomentsCache(void);
void WUMomentsCacheObserveHost(id item);
void WUShowMomentsCache(UIViewController *owner);
void WUInstallTimeline(void);
void WUInstallAppearance(void);
void WUInstallMessages(void);
BOOL WUMessageAvailable(NSString *key);
void WUInstallSettings(void);
void WUShowSettings(UIViewController *owner);
void WUShowLinks(UIViewController *owner);
void WUInstallSurfaces(void);
void WUInstallThemes(void);
void WUShowThemes(UIViewController *owner);
void WUStyleSettingSwitches(UIViewController *controller);
NSString *WUCurrentAccount(void);
NSUInteger WUContextGeneration(void);
// Background read only; does not call any host object or refresh account identity.
NSUInteger WUContextGenerationSnapshot(void);
NSDictionary *WUAccountOptions(NSString *account);
BOOL WUSaveAccountOption(NSString *account, NSString *key, id value);
void WUInstallGroups(void);
void WUShowGroups(UIViewController *owner);
void WUInstallHomeGroups(void);
void WURefreshHome(UIViewController *owner);
void WUShowHomeGroups(UIViewController *owner);
NSString *WUChatSession(UIViewController *owner);
BOOL WUMomentsAvailable(void);
BOOL WUIsMomentsSheet(UIViewController *controller);
BOOL WUOpenMoments(UIViewController *owner);
void WURefreshMomentsInput(UIViewController *owner);
void WUCancelMoments(void);
void WUMomentsDraftsAction(UINavigationController *nav, NSString *account, NSUInteger generation);
void WUInstallMoments(void);
FOUNDATION_EXPORT NSString *const WUChanged;
