#import <Foundation/Foundation.h>
// Only host-presented comments, never inferred from a missing page.
// Decoder accepts WCDataItem + displayed WCUserComment identities in commentUsers.
// Rows with unverified stable ID/author/text or local-pending state are rejected.
// time=0 and replyTo="" mean unknown; neither is inferred from display names.
// normalized rows: {id: stable per-item string, author: member ID, text: string,
// time: Unix seconds (0 = unknown), replyTo: author ID or empty}.
NSArray<NSDictionary *> *WUMomentsDecodeDisplayedComments(id item, NSArray *displayed);
void WUMomentsCacheObserveNormalizedComments(id item, NSArray<NSDictionary *> *comments, NSString *account, NSUInteger generation);
