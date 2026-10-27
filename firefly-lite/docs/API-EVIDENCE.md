# 接口依据与验证边界

## RootHide 官方规范（已读本地官方快照）
- https://github.com/roothide/Developer/blob/main/README.md
- https://github.com/roothide/Developer/blob/main/roothide.md

使用 `roothide/theos` 的 `THEOS_PACKAGE_SCHEME=roothide`；RootHide 包架构是 `iphoneos-arm64e`，不代表只编译 arm64e。本工程编译 arm64 与 arm64e。随机 jbroot 和 `.jbroot` 链接交给工具链/dpkg，不生成固定 `/var/jb` 路径。没有手写 Mach-O 加载路径或自行转换旧包。
工程没有需要按 jailbreak 根目录读取的资源文件；PreferenceLoader 使用 bundle 名，Info.plist 随 bundle 打包，图标使用系统 SF Symbols，无绝对资源路径。清理工具使用 CFPreferences，不打开猜测的 plist 路径。

## SpringBoard 公开头文件
这些是社区导出的 Apple 私有接口，不是 Apple 的稳定 SDK。

1. iOS 16.0 20A5303f 的 `SBIconObserver`：
https://github.com/lechium/iPhoneOS_16.0_20A5303f/blob/master/System/Library/PrivateFrameworks/SpringBoardHome/SBIconObserver-Protocol.h
已获取并核对的声明：
```objc
@protocol SBIconObserver <NSObject>
@optional
- (void)iconAccessoriesDidUpdate:(SBIcon *)arg1;
- (void)iconImageDidUpdate:(SBIcon *)arg1;
@end
```
因此角标附件刷新使用有 iOS16 协议依据的 `iconAccessoriesDidUpdate:`，不是杜撰 `icon:didUpdateBadgeNumberOrString:`。

2. `SBIconView`/`SBIcon` 的类级声明交叉依据：
https://github.com/MTACS/iOS-17-Runtime-Headers/blob/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/SpringBoardHome.framework/SBIconView.h
https://github.com/MTACS/iOS-17-Runtime-Headers/blob/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/SpringBoardHome.framework/SBIcon.h
已核对：
```objc
// SBIconView
- (id)icon;
- (id)_iconImageView;
- (bool)isFolderIcon;
- (void)setIcon:(id)arg1;
- (void)iconAccessoriesDidUpdate:(id)arg1;
- (void)layoutSubviews;
- (void)didMoveToWindow;
// SBIcon
- (id)badgeNumberOrString;
```

**证据限制：类级完整声明来源是 iOS17，不冒称 iOS16.6 头文件。** iOS16 仓库可获取协议但未取得上述完整类头；Limneos iOS16.3 页面遇人机校验，没有将其算作成功核对。故完整 iOS16.6 类级验证仍未完成，交付是待真机验证的源码候选，不是“已适配 iOS16.6”成品。

实现启动时逐一检查类、返回类型和参数数量/类型；任一必需接口缺失/不匹配则不安装任何 hook。模型角标 getter 每次读取前也检查。只接受 `isFolderIcon` 的 `_Bool`（编码 B），不是猜测 BOOL 的 ABI。接口匹配不能证明语义、布局或注入兼容；真机仍要验证 accessory 回调是否覆盖角标更新。

无私有 ivar、结构体偏移、定时轮询或通知内容读取。发光依据是应用角标，不是 Notification Center 未读通知数据库。关闭系统角标的通知不会触发。文件夹本身排除，文件夹内部的应用仍按其角标处理。

## 0.1.2 已显示图像接口依据
通过浏览器 TLS fetch 成功核对固定提交（HTTP 200）：
https://github.com/MTACS/iOS-17-Runtime-Headers/blob/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/SpringBoardHome.framework/SBIconImageView.h
```objc
@interface SBIconImageView : UIView
@property (nonatomic, readonly) UIImage *displayedImage;
- (id)displayedImage;
- (void)updateImageAnimated:(bool)arg1;
- (void)didEndAsynchronousImageLoadForIcon:(id)arg1;
@end
```
它不是 UIImageView，不盲发 `image`。仅 UIImageView 实例使用公开 `image`；SBIconImageView 实例用已核对的 `displayedImage`，调用前检查对象返回和零显式参数，再验证返回对象为 UIImage。图像更新 hook 各自检查 void/参数数量及 bool(B) 或 object(@)，不匹配跳过。没有使用 snapshot、屏幕渲染、私有 ivar 或猜测图像 getter。

限制：此证据仍是 iOS17 类头，不是 iOS16.6 实机。目标系统缺少匹配 getter 时确定回退手动色；只有 getter 而无可选回调时，图像变更在下一次 SBIconView 布局/现有事件才复核。UIImage 视为不可变对象，以身份变化检测内容更新，不支持外部原地篡改底层像素的非标准图像。

## 下载信任记录
Shell 的 HTTPS CA 链校验失败；公开只读研究文件使用 curl -k 获取，仅作接口线索，没有执行下载文件、没有安装包、没有作为可执行依赖打包。由此不能将取证称为完整 TLS 认证。上述固定提交可在可信网络上重新核对。
