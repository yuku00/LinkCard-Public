#import "WU.h"
void WUOpenLinkInput(UIViewController *owner);
void WUOpenSelectedLinks(UIViewController *owner, NSArray<NSDictionary *> *frozen, BOOL (^current)(void));
void WUExportEmoticon(UIViewController *owner, NSString *path, BOOL (^current)(void));
void WUChooseRepeatIcon(UIViewController *owner);
void WUCancelMessageEntries(void);
BOOL WUMessageEntriesOwnsController(UIViewController *controller);
void WUShowRepeatSettings(UIViewController *owner);
UIImage *WUThemeRepeatIcon(NSString *userIcon, BOOL themed, UITraitCollection *traits);
