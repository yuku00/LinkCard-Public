#import <Foundation/Foundation.h>
// No UIKit or host objects: import planning, indexing and ordering are independently testable.
BOOL WUThemeSafePath(NSString *path);
NSDictionary *WUThemeMergeFiles(NSDictionary *existing, NSDictionary *incoming, BOOL replace, NSError **error);
NSDictionary *WUThemeResourceIndex(NSArray<NSString *> *paths);
NSArray<NSString *> *WUThemeCandidates(NSString *name, BOOL dark, NSDictionary *aliases);
NSString *WUThemeBestPath(NSArray<NSString *> *paths, double scale);
NSArray<NSDictionary *> *WUThemeSortedPacks(NSArray<NSDictionary *> *packs, NSDictionary *options);
BOOL WUValidThemeOptions(id value);
NSDictionary *WUThemeReadDescriptor(NSData *data, NSError **error);
NSDictionary *WUThemeReadColors(NSData *data, NSString *extension, BOOL darkFile, NSError **error);
BOOL WUValidSurfaceStyles(id value);
NSArray<NSString *> *WUSurfaceRoles(void);
