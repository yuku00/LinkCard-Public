#import <Foundation/Foundation.h>
BOOL WUValidAccountOptions(id value);
NSDictionary *WUEmptyEmojiGroups(void);
BOOL WUValidMD5(NSString *value);
NSArray<NSNumber *> *WUEmojiIndexes(NSArray<NSString *> *identifiers, NSDictionary *state);
NSDictionary *WURemoveEmojiGroup(NSDictionary *state, NSString *identifier);
// Return nil on invalid/stale identity; preserve the host media and selected group ID.
NSDictionary *WURenameEmojiGroup(NSDictionary *state, NSString *identifier, NSString *name);
NSDictionary *WUMoveEmojiGroup(NSDictionary *state, NSString *identifier, NSInteger destination);
NSArray<NSString *> *WUToolbarActions(id value);
