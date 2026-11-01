#import "WU.h"
#import "PluginHubLogic.h"
// Optional local registration for plugins loaded in this process.
@interface WUPluginHubManager : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(id)controller;
@end
void WUInstallPluginHub(void);
void WUShowPluginHub(UIViewController *owner);
