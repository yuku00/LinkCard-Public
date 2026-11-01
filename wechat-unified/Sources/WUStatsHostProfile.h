#import <Foundation/Foundation.h>
// Main-thread host reads are sliced; completion contains only immutable values.
// current is the existing account/session/generation gate; false drops all work.
FOUNDATION_EXPORT void WUStatsReadHostProfile(id contactManager, NSString *account, NSString *session, NSArray<NSDictionary *> *sessions, BOOL (^current)(void), void (^done)(NSDictionary *));
FOUNDATION_EXPORT NSDictionary *WUStatsContactProfile(id contactManager, NSString *username, NSTimeInterval now);
FOUNDATION_EXPORT NSDictionary *WUStatsParseMembers(id raw);
// Called on the existing statistics worker after host objects have been discarded.
FOUNDATION_EXPORT NSDictionary *WUStatsProfileSummary(NSDictionary *snapshot);
FOUNDATION_EXPORT NSArray<NSString *> *WUStatsProfileLines(NSDictionary *summary, NSTimeZone *zone);
