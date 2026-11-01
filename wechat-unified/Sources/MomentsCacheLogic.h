#import <Foundation/Foundation.h>
NSDictionary *WUMCacheNormalize(id tid, id username, id text);
NSArray *WUMCacheLoad(NSURL *root, NSString *account, NSError **error);
NSDictionary *WUMCacheObserve(NSURL *root, NSString *account, NSDictionary *item, NSTimeInterval now, NSError **error);
BOOL WUMCacheFavorite(NSURL *root, NSString *account, NSString *uuid, NSError **error);
BOOL WUMCacheClean(NSURL *root, NSString *account, NSUInteger days, NSTimeInterval now, NSError **error);

// Caller serializes capture, browse leases and reclamation on its module IO queue.
BOOL WUMCacheStore(NSURL *textRoot, NSURL *mediaRoot, NSString *account, NSDictionary *item, NSArray *images, NSTimeInterval now, BOOL (^valid)(void), NSError **error);
NSDictionary *WUMCacheReclaim(NSURL *textRoot, NSURL *mediaRoot, NSString *account, NSUInteger days, NSTimeInterval now, NSSet *leasedIDs, BOOL (^valid)(void), NSError **error);
BOOL WUMCacheFavoriteChecked(NSURL *root, NSString *account, NSString *uuid, BOOL (^valid)(void), NSError **error);
