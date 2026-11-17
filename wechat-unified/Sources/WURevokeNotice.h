#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, WURevokeActor) {
    WURevokeActorUnknown, WURevokeActorSelf, WURevokeActorOther
};
WURevokeActor WURevokeNoticeActor(NSString *xml);

// Call only after the existing anti-revoke path has decided to protect the message.
// `valid` must recheck enablement, account, generation and current message service.
// Keep the context stable across this synchronous call (see integration notes).
void WURevokeNoticeInsert(id manager, NSString *account, NSString *session,
                          uint64_t serverID, NSUInteger generation,
                          NSString *from, NSString *to, uint32_t createTime,
                          BOOL (^valid)(void));
