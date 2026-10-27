#import <Preferences/PSViewController.h>
#import <UIKit/UIKit.h>
#import "Shared/FLPreferences.h"

@interface FLRootController : PSViewController <UITableViewDataSource, UITableViewDelegate,
                                               UIColorPickerViewControllerDelegate>
@property(nonatomic, strong) UITableView *table;
@property(nonatomic) FLConfig config;
@property(nonatomic) BOOL stopped;
@end
static void PreferencesNotification(CFNotificationCenterRef center, void *observer,
    CFStringRef name, const void *object, CFDictionaryRef info) {
    __weak FLRootController *weakController = (__bridge FLRootController *)observer;
    BOOL stop = CFEqual(name, FL_STOP);
    dispatch_async(dispatch_get_main_queue(), ^{
        FLRootController *controller = weakController;
        if (!controller) return;
        if (stop) {
            controller.stopped = YES;
            controller.table.userInteractionEnabled = NO;
            [controller dismissViewControllerAnimated:YES completion:nil];
            controller.title = @"萤光已卸载";
            CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                (__bridge void *)controller);
        } else if (!controller.stopped) {
            controller.config = FLReadConfig();
            [controller.table reloadData];
        }
    });
}
@implementation FLRootController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"萤光 · 精简版";
    self.config = FLReadConfig();
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = UITableViewAutomaticDimension;
    self.table.estimatedRowHeight = 60;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center, (__bridge void *)self, PreferencesNotification,
        FL_CHANGED, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center, (__bridge void *)self, PreferencesNotification,
        FL_STOP, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self);
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.stopped) { self.config = FLReadConfig(); [self.table reloadData]; }
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : 3;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"让待处理事项轻轻亮起" : @"光晕外观";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"默认仅有角标的应用发光；开启“全部应用图标发光”后，无角标应用也发光。关闭“启用图标发光”后立即移除所有光晕。"
        : @"跟随图标颜色默认关闭；开启后提取已显示图标主色，纯黑白或取色失败时使用手动颜色。无需重启。文件夹不发光；强度为零时不显示。";
}
- (UIColor *)selectedColor {
    FLConfig c = self.config;
    return [UIColor colorWithRed:c.red green:c.green blue:c.blue alpha:1];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == 0) {
        BOOL allApps = indexPath.row == 1;
        cell.textLabel.text = allApps ? @"全部应用图标发光" : @"启用图标发光";
        UISwitch *toggle = [UISwitch new];
        toggle.on = allApps ? self.config.allApps : self.config.enabled;
        toggle.accessibilityLabel = cell.textLabel.text;
        [toggle addTarget:self action:allApps ? @selector(toggleAllApps:) : @selector(toggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (indexPath.row == 2) {
        cell.textLabel.text = @"跟随图标颜色";
        UISwitch *toggle = [UISwitch new];
        toggle.on = self.config.followIconColor;
        toggle.accessibilityLabel = cell.textLabel.text;
        [toggle addTarget:self action:@selector(toggleFollow:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (indexPath.row == 0) {
        cell.textLabel.text = @"光晕颜色";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.imageView.image = [UIImage systemImageNamed:@"circle.fill"];
        cell.imageView.tintColor = self.selectedColor;
        cell.accessibilityLabel = @"光晕颜色，打开系统颜色选择器";
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        UIStackView *stack = [UIStackView new];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 10;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *label = [UILabel new];
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        label.adjustsFontForContentSizeCategory = YES;
        label.text = [NSString stringWithFormat:@"光晕强度 · %.0f%%", self.config.intensity * 100];
        UISlider *slider = [UISlider new];
        slider.minimumValue = 0; slider.maximumValue = 1;
        slider.value = self.config.intensity; slider.continuous = NO;
        slider.accessibilityLabel = @"光晕强度";
        [slider addTarget:self action:@selector(intensity:) forControlEvents:UIControlEventValueChanged];
        [stack addArrangedSubview:label]; [stack addArrangedSubview:slider];
        [cell.contentView addSubview:stack];
        UILayoutGuide *guide = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:5],
            [stack.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-5],
            [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor]]];
    }
    return cell;
}
- (void)save {
    if (self.stopped) return;
    if (!FLWriteConfig(self.config)) {
        self.config = FLReadConfig();
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未能保存"
            message:@"CFPreferences 同步失败，设置未确认写入。请检查注入和偏好权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        if (!self.presentedViewController) [self presentViewController:alert animated:YES completion:nil];
    }
    [self.table reloadData];
}
- (void)toggle:(UISwitch *)sender { FLConfig c = self.config; c.enabled = sender.on; self.config = c; [self save]; }
- (void)toggleFollow:(UISwitch *)sender { FLConfig c = self.config; c.followIconColor = sender.on; self.config = c; [self save]; }
- (void)toggleAllApps:(UISwitch *)sender { FLConfig c = self.config; c.allApps = sender.on; self.config = c; [self save]; }
- (void)intensity:(UISlider *)sender { FLConfig c = self.config; c.intensity = sender.value; self.config = c; [self save]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.stopped || indexPath.section != 1 || indexPath.row != 0) return;
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.title = @"选择光晕颜色";
    picker.supportsAlpha = NO;
    picker.selectedColor = self.selectedColor;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)picker {
    if (self.stopped) return;
    CGFloat r, g, b, a;
    if ([picker.selectedColor getRed:&r green:&g blue:&b alpha:&a]) {
        FLConfig c = self.config; c.red = r; c.green = g; c.blue = b;
        self.config = c; [self save];
    }
}
@end
