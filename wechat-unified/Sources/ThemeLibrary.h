#import <Foundation/Foundation.h>
NSDictionary *WUThemeReadPackFiles(NSString *path, NSError **error);
NSDictionary *WUThemePackMetadata(NSString *path);
BOOL WUThemeCommitPack(NSString *root, NSString *identifier, NSDictionary *files, NSDictionary *metadata, NSError **error);
