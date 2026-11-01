#import <Foundation/Foundation.h>
// 0: no layer, 1: static border, 2: editing pulse. No responder mutations.
NSUInteger WUInputEffect(BOOL border, BOOL pulse, BOOL visible, BOOL editing, BOOL active, BOOL reducedMotion);
// Only exact message semantics; unknown app messages are never file cards.
NSString *WUCardRole(NSUInteger type, NSString *content);
BOOL WUSurfaceValueOwned(id current, id applied);
