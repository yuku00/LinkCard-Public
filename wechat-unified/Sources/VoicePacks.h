#import <UIKit/UIKit.h>
#import "VoiceSendLogic.h"
@interface WUVoicePackBinding : NSObject
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSString *target;
@property(nonatomic,copy) NSString *version;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,copy) BOOL (^current)(void);
@property(nonatomic,copy) NSDictionary *(^capture)(void);
@property(nonatomic,copy) NSString *(^send)(WUVoiceForwardOperation *operation);
@end
BOOL WUIsVoicePacksController(UIViewController *controller);
void WUShowVoicePacks(UIViewController *owner, WUVoicePackBinding *binding);
