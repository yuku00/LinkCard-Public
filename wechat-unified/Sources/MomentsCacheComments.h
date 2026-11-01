#import <Foundation/Foundation.h>
// Adapter seam only: the target build's comment-model decoder is NOT yet bound.
// Caller must pass ONLY comments already shown in this item's host-provided view.
// normalized rows: {id: stable per-item string, author: member ID, text: string,
// time: Unix seconds (0 = unknown), replyTo: author ID or empty}.
void WUMomentsCacheObserveNormalizedComments(id item, NSArray<NSDictionary *> *comments, NSString *account, NSUInteger generation);
