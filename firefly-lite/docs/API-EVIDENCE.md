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

## 0.1.4 真实调用链与实现（取代0.1.2/0.1.3行为描述）

本地原 Metamorphosis arm64 反汇编已确认 `_iconImageView` → `contentsImage` → 平均色 → `shadowColor`，原平均色不排斥灰阶。本工程只采用该接口证据，不复制旧二进制、授权或 ivar 偏移。`contentsImage` 和兼容 getter 均校验对象返回/参数数量，并验证 UIImage 及其 CGImage；公开 layer.contents 仅接受 CGImage 类型。

0.1.3 的 localCapture 在 layer.contents 回退前赋值，静态 CGImage 被误判为动态截图，分散事件重复失效；此外主线程 renderInContext、无条件 shadowPath/颜色重建、离屏销毁和图像事件全表扫描增加滑动开销。0.1.4 删除截图路径及 localCapture/dirty 重试机制，只在后台对保留的不可变 CGImage 做 24×24 栅格化；相同图源不重采。布局不扫描像素；弱 owner 关联、异步合并、同尺寸路径复用和同样式早退减少重复工作。同图标离屏保留缓存，关闭/换图标/卸载清除。

灰阶使用有效像素的 alpha 加权均值回退，不再当作失败；彩色仍沿用本工程主色投票，不声称完全复制原插件 1×1 平均的视觉结果。完全透明或无可用 CGImage 时使用手动色。私有事件缺失时不能保证捕获每次图标动画变化；不支持原地修改不可变 CGImage 存储的非标准行为。

测试边界：旧0.1.3生产 FLColor.h 对新白色有效性断言实际失败，新版生产函数通过；缓存/路径测试共享生产判定函数并模拟40次事件和1000次布局，不是 UIKit 性能测量。无任何 renderInContext/截图代码的静态扫描通过。真机颜色、SpringBoard 回调覆盖、FPS及功耗未验证。

## 0.1.3 历史重新核对（以下实现已由0.1.4取代）

通过浏览器 TLS fetch（HTTP 200）核对 iOS16.4 20E247 固定提交：
https://github.com/lechium/iPhone_OS_16.4_20E247/blob/6e936b9f702d6d5746430d3d918709479dffafb5/System/Library/PrivateFrameworks/SpringBoardHome/SBIconObserver-Protocol.h
```objc
- (void)iconAccessoriesDidUpdate:(SBIcon *)arg1;
- (void)iconImageDidUpdate:(SBIcon *)arg1;
```
同目录 SBCrossfadingIconImageSource-Protocol.h 明确 sourceView 返回 UIView*；SBHIconImageCacheObserver-Protocol.h 声明 iconImageCache:didUpdateImageForIcon:。本版只新增前述单参数 iconImageDidUpdate: 可选 hook，检查 v/@/参数数3，不调用 sourceView 或猜测新的 getter。

已检查 lechium 的16.0和16.4 SpringBoardHome目录：有这些协议，没有完整 SBIconImageView 类头。qingralf/iOS16-Runtime-Headers 的根递归结果被截断，改查 PrivateFrameworks 子树后确认没有 SpringBoardHome。Tweaker177 的“iOS-14-16”仓库中 SBIconImageView.h 文首实际标记 iOS15.7.2，不能冒称16头。Limneos16.3页面访问未取得可核对头文件。**因此没有证据证明16.6缺少 displayedImage，也没有证据证明实际签名错误；这两点仍是假设，不据此放宽 ABI 检查。**

确定的代码缺陷：旧版 getter 返回nil/非CGImage/过大图片时无局部采图路径；同 UIImage/icon 身份的失败状态在图像更新回调中不会失效。新增公开 UIKit/QuartzCore 图标局部 fallback，避免必须依赖该私有getter；图像事件使失败和局部渲染缓存失效，250ms合并回调；首次失败一次延迟重试，之后等待真实事件/源变化/开关刷新。

安全与性能边界：仅渲染经验证为 SBIconView 严格子视图的 _iconImageView 图层树；不渲染容器、窗口或屏幕，自有光晕为容器的兄弟图层。采图和24×24缩放在主线程，颜色投票在串行后台；源不变的layout复用缓存。无磁盘、照片、网络、日志采集。CALayer局部渲染对特殊硬件图层不保证有像素；全中性图标仍回手动色。尚未验证16.6实际 getter/hook覆盖、视觉效果或功耗。

测试等级：旧版缺少 renderInContext 路径的静态断言已观察到失败；修复后静态接线检查、生产代码共用的缓存决策C测试（含1000次不变layout决策）、颜色算法测试和卸载脚本测试通过。这不是UIKit/SpringBoard运行复现，不把主机模型测试称为真机修复证明。
