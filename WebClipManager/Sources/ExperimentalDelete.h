#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Production always resolves UIWebClip and uses the fixed system root.
NSDictionary *WCMExperimentalDelete(NSString *identifier);
// Injectable only for synthetic unit tests; callers must supply an isolated root and mock class.
NSDictionary *WCMExperimentalDeleteForTesting(NSString *identifier, NSString *root, Class mockClass);
NS_ASSUME_NONNULL_END
