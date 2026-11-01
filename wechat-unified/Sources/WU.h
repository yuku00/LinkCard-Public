#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
BOOL WUEnabled(NSString *key);
BOOL WUSave(NSString *key, id value);
id WUValue(NSString *key);
BOOL WUMatches(Method method, const char *result, NSArray<NSString *> *arguments);
BOOL WUHook(NSString *className, NSString *selector, BOOL meta, const char *result, NSArray<NSString *> *arguments, IMP replacement, IMP *original);
NSArray<NSString *> *WUHookStatus(void);
void WUInstallAds(void);
void WUInstallTimeline(void);
void WUInstallAppearance(void);
void WUInstallMessages(void);
BOOL WUMessageAvailable(NSString *key);
void WUInstallSettings(void);
void WUShowSettings(UIViewController *owner);
void WUShowLinks(UIViewController *owner);
FOUNDATION_EXPORT NSString *const WUChanged;
