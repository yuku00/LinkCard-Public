#import <UIKit/UIKit.h>
@interface WUEmoticonLibraryBinding : NSObject
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSString *target;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,copy) BOOL (^current)(void);
// Capture only the user's one selected type47 message; never an album or database scan.
@property(nonatomic,copy) NSDictionary *(^capture)(void);
@property(nonatomic,copy) BOOL (^selectionCurrent)(NSDictionary *capture);
@property(nonatomic,copy) BOOL (^canSubmit)(void);
@property(nonatomic,copy) NSString *(^submit)(NSData *original);
@end
void WUShowEmoticonLibrary(UIViewController *owner, WUEmoticonLibraryBinding *binding);
BOOL WUIsEmoticonLibraryController(UIViewController *controller);
