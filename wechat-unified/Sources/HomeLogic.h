#import <Foundation/Foundation.h>
NSDictionary *WUEmptyHomeGroups(void);
BOOL WUValidHomeGroups(id state);
NSDictionary *WURemoveHomeGroup(NSDictionary *state, NSString *identifier);
// Immutable indexes into each original host array; nil means preserve the entire host snapshot.
NSArray<NSNumber *> *WUHomeIndexes(NSArray<NSDictionary *> *rows, NSDictionary *state);
NSString *WUHomeKind(NSString *username, BOOL chatBox, BOOL brand, BOOL single);
NSDictionary *WUHomeProjection(NSArray<NSArray *> *sources, NSArray<NSArray<NSDictionary *> *> *rows, NSDictionary *state, NSUInteger originalTopCount);
