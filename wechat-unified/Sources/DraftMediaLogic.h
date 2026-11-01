#import <Foundation/Foundation.h>
// Immutable owned resources: deletion only removes index rows, never files.
NSArray *WUDraftMediaLoad(NSURL *root, NSString *account, NSError **error);
// Bounded descriptor read; callers may use a smaller limit before decoding.
NSData *WUDraftMediaReadSource(NSURL *url, NSUInteger limit);
BOOL WUDraftMediaPutChecked(NSURL *root, NSString *account, NSString *uuid, NSString *text, NSString *kind, NSArray *sources, BOOL (^valid)(void), NSError **error);
BOOL WUDraftMediaPut(NSURL *root, NSString *account, NSString *uuid, NSString *text, NSString *kind, NSArray *sources, NSError **error);
BOOL WUDraftMediaDelete(NSURL *root, NSString *account, NSString *uuid, NSError **error);
NSArray<NSURL *> *WUDraftMediaURLs(NSURL *root, NSString *account, NSDictionary *row, NSError **error);
