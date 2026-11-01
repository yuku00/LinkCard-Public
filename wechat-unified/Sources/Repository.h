#import <UIKit/UIKit.h>
#import "RepositoryLogic.h"
@interface WURepositoryBinding : NSObject
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSString *target;
@property(nonatomic,copy) BOOL (^current)(void);
@property(nonatomic,copy) NSArray *(^capture)(void);
@property(nonatomic,copy) NSString *(^send)(NSDictionary *part);
@end
void WUShowRepository(UIViewController *owner, WURepositoryBinding *binding);
