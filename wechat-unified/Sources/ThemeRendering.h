#import <UIKit/UIKit.h>
BOOL WUThemeValidImage(NSData *data);
BOOL WUThemeValidateResource(NSString *relative, NSData *data, NSString **failure);
UIImage *WUThemeRenderFile(NSString *path, CGSize size, CGFloat scale, UIColor *color);
UIImage *WUThemeRenderCatalog(NSString *path, NSString *name, UITraitCollection *traits);
void WUThemeClearRenderCache(void);
