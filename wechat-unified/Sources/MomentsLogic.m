#import "MomentsLogic.h"
#include <math.h>
BOOL WUMomentsCommand(NSString *text, BOOL marked, BOOL editing, BOOL chatOwned) {
    return chatOwned && editing && !marked && [text isKindOfClass:NSString.class] && [text isEqualToString:@"rp"];
}
BOOL WUMomentsContext(NSString *account, NSString *session, NSUInteger generation, NSString *currentAccount, NSString *currentSession, NSUInteger currentGeneration, BOOL enabled, BOOL active) {
    return enabled && active && account.length && session.length && generation==currentGeneration && [account isEqual:currentAccount] && [session isEqual:currentSession];
}
double WUMomentsHeight(double h) { return isfinite(h) && h>0 ? floor(h/2.0) : 0; }
