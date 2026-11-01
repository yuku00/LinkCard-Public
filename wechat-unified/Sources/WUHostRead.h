#import <Foundation/Foundation.h>
// Only selectors whose read/value semantics are independently evidenced.
FOUNDATION_EXPORT id WUHostObject(id object, NSString *selector, id argument, BOOL hasArgument);
FOUNDATION_EXPORT NSNumber *WUHostUInt32(id object, NSString *selector);
FOUNDATION_EXPORT NSNumber *WUHostBool(id object, NSString *selector);
FOUNDATION_EXPORT BOOL WUHostIs(id object, NSString *className);
FOUNDATION_EXPORT NSString *WUHostString(id value, NSUInteger limit);
