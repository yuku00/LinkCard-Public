#import <UIKit/UIKit.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

// No directory enumeration, file reads, database opening, writes, or networking.
static NSString *OpenDirectory(const char *path) {
    int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    int code = errno;
    if (fd >= 0) { close(fd); return @"成功（仅打开目录）"; }
    return [NSString stringWithFormat:@"失败 errno=%d", code];
}
@interface ProbeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UILabel *label;
@end
@implementation ProbeDelegate
- (void)testAccess {
    NSString *webclips = OpenDirectory("/var/mobile/Library/WebClips");
    NSString *groups = OpenDirectory("/var/mobile/Containers/Shared/AppGroup");
    NSString *legacyNotes = OpenDirectory("/var/mobile/Library/Notes");
    self.label.text = [NSString stringWithFormat:@"探针 C · 启动成功\niOS %@ · uid=%u euid=%u\n\nWebClips：%@\nAppGroup 根：%@\n旧 Notes 路径：%@\n\n未枚举名称、未读文件或数据库。\nAppGroup 成功不等于 Notes 数据库可读。\nerrno 1/13 权限失败；2 路径不存在。", UIDevice.currentDevice.systemVersion, (unsigned)getuid(), (unsigned)geteuid(), webclips, groups, legacyNotes];
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    self.label = [UILabel new];
    self.label.numberOfLines = 0;
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.label.text = @"探针 C · 启动成功\ncontainer-required = false（布尔）\n\n无 platform / root / JIT 权限。\n启动时不访问目标目录。\n\n点击下方仅测试目录能否只读打开。\n不枚举名称、不读笔记、不作删除。";
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"只读测试目录访问" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(testAccess) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.label, button]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 24;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-20]
    ]];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeDelegate.class)); }
}
