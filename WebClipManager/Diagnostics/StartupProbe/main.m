#import <UIKit/UIKit.h>
@interface ProbeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation ProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *label = [UILabel new];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:26 weight:UIFontWeightSemibold];
    NSString *variant = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ProbeVariant"];
    label.text = [NSString stringWithFormat:@"探针 %@\n启动成功\niOS %@", variant, UIDevice.currentDevice.systemVersion];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-20]
    ]];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeDelegate.class));
    }
}
