#import <Foundation/Foundation.h>
NSArray *WUMCacheMergeComments(NSArray *old, NSArray *observed, NSError **error);
BOOL WUMCacheSaveComments(NSURL *root, NSString *account, NSString *username, NSString *tid, NSArray *observed, NSTimeInterval now, BOOL (^valid)(void), NSError **error);
NSDictionary *WUMCacheNormalize(id tid, id username, id text);
NSArray *WUMCacheLoad(NSURL *root, NSString *account, NSError **error);
NSDictionary *WUMCacheObserve(NSURL *root, NSString *account, NSDictionary *item, NSTimeInterval now, NSError **error);
BOOL WUMCacheFavorite(NSURL *root, NSString *account, NSString *uuid, NSError **error);
BOOL WUMCacheClean(NSURL *root, NSString *account, NSUInteger days, NSTimeInterval now, NSError **error);

// Caller serializes capture, browse leases and reclamation on its module IO queue.
// Media kind is images or video-backup; video is a single local byte snapshot, not an editor draft.
BOOL WUMCacheStoreMedia(NSURL *textRoot, NSURL *mediaRoot, NSString *account, NSDictionary *item, NSString *kind, NSArray *payloads, NSTimeInterval now, NSSet *leasedIDs, BOOL (^valid)(void), NSError **error);
BOOL WUMCacheStore(NSURL *textRoot, NSURL *mediaRoot, NSString *account, NSDictionary *item, NSArray *images, NSTimeInterval now, BOOL (^valid)(void), NSError **error);
NSDictionary *WUMCacheReclaim(NSURL *textRoot, NSURL *mediaRoot, NSString *account, NSUInteger days, NSTimeInterval now, NSSet *leasedIDs, BOOL (^valid)(void), NSError **error);
BOOL WUMCacheFavoriteChecked(NSURL *root, NSString *account, NSString *uuid, BOOL (^valid)(void), NSError **error);
