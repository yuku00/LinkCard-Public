#import <Foundation/Foundation.h>
NSDictionary *WURevokeFields(NSString *xml);
BOOL WUOwnMessage(NSString *account, NSString *session, NSString *from, NSString *real);
BOOL WURevokeEligible(NSString *account, NSString *session, NSDictionary *message, NSTimeInterval now);
BOOL WUGroupAdjacent(NSDictionary *a, NSDictionary *b);
