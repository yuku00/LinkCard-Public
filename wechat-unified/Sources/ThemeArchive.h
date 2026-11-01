#import <Foundation/Foundation.h>
// Strict ZIP32 reader: stored/deflate only, UTF-8 paths, no encryption/links/ZIP64.
NSDictionary<NSString *, NSData *> *WUReadThemeZIP(NSData *data, NSError **error);
NSString *WUThemeKey(NSString *name);
BOOL WUThemeBubble(NSString *name);
