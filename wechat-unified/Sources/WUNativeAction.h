#import "WUNative.h"

// One owner-retained UI operation; no private sender methods are invented here.
@interface WUNativeAction : NSObject
@property(nonatomic,strong) UIViewController *owner;
@property(nonatomic,strong) UIAlertController *alert;
@property(nonatomic,copy) NSString *key, *account, *session, *outcome;
@property(nonatomic,copy) BOOL (^valid)(void);
@property(nonatomic,copy) void (^commit)(NSUInteger choice);
@property(nonatomic,readonly) BOOL consumed;
- (BOOL)present;
- (void)choose:(NSUInteger)choice;
- (void)cancel;
@end
WUNativeAction *WUNativePendingAction(NSString *key, NSString *account, NSString *session);
void WUNativeRefreshActions(void);
void WUNativeCancelActions(void);
BOOL WUNativeOwnsController(UIViewController *controller);
id WUNativeObject(id object, NSString *selector);
NSString *WUNativeString(id object, NSString *selector);
NSNumber *WUNativeUnsigned(id object, NSString *selector);
NSDictionary *WUNativeMessageIdentity(id message);
BOOL WUNativeSetUnsigned(id object, NSString *setter, uint64_t value);
BOOL WUNativeNumberField(Class cls, NSString *getter, NSString *setter);
