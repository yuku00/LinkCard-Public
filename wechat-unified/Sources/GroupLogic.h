#import <Foundation/Foundation.h>
BOOL WUValidAccountOptions(id value);
NSDictionary *WUEmptyEmojiGroups(void);
BOOL WUValidMD5(NSString *value);
NSArray<NSNumber *> *WUEmojiIndexes(NSArray<NSString *> *identifiers, NSDictionary *state);
NSDictionary *WURemoveEmojiGroup(NSDictionary *state, NSString *identifier);
NSArray<NSString *> *WUToolbarActions(id value);
