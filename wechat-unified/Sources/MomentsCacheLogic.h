#import <Foundation/Foundation.h>
NSDictionary *WUMCacheNormalize(id tid, id username, id text);
NSArray *WUMCacheLoad(NSURL *root, NSString *account, NSError **error);
NSDictionary *WUMCacheObserve(NSURL *root, NSString *account, NSDictionary *item, NSTimeInterval now, NSError **error);
BOOL WUMCacheFavorite(NSURL *root, NSString *account, NSString *uuid, NSError **error);
BOOL WUMCacheClean(NSURL *root, NSString *account, NSUInteger days, NSTimeInterval now, NSError **error);
