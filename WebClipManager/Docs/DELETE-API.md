# 删除接口证据与启用门槛

本次仅 GET 读取公开头文件；未上传任何内容，未读取用户既有归档。

## 已实际读取

1. https://raw.githubusercontent.com/nst/iOS-Runtime-Headers/master/PrivateFrameworks/UIKitCore.framework/UIWebClip.h
   - RuntimeBrowser 生成头文件，声明 `@interface UIWebClip : NSObject`、`+webClipWithIdentifier:`、`- (bool)removeFromDisk`、`-requestIconUpdateInSpringBoard`。
   - 仓库 master 是移动引用，页面不能作为 iOS 16.6 版本证据。仅证实该公开转储存在这些声明。
2. https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/main/PrivateFrameworks/UIKitCore.framework/UIWebClip.h
   - 同样看到 `UIWebClip` 和 `- (bool)removeFromDisk` 声明。
   - 仓库名指向 iOS 17，不是 iOS 16.6；无实现体，不能推出清理语义。

## 未取得证据

- 尝试 MTACS/iOS-16.4-Runtime-Headers 对应 UIWebClip 路径返回 404，不能据此推断系统没有此类。
- 尝试 `https://developer.limneos.net/?ios=16.3&framework=UIKitCore.framework&header=UIWebClip.h`，未得到可提取的目标头文件文本，不能用作核实证据。
- 没有 iOS 16.6 runtime 导出、反汇编实现、SpringBoard 删除调用链、服务鉴权要求或本机测试。没有证明 `removeFromDisk` 会删除主屏幕注册、独立数据与关联缓存，或遵循描述文件管理约束。

## 当前决定

不导入/链接私有框架、不动态调用 selector。诊断页面仅通过 `NSClassFromString`、`class_getInstanceMethod`、`class_getClassMethod` 检查元数据；不实例化 UIWebClip、不执行 selector、不获取实现指针。Repository.delete 对每个标识返回拒绝原因。代码不存在删除目标目录、发 Darwin 通知、重启 SpringBoard 或清 Safari 数据的后备路径。界面明确显示“不可用”，不存在成功删除计数。

未来仅拿到头文件或 selector 可响应还不够：需要 16.6 的实际删除路径、调用进程/权限与错误语义证据，并在可丢弃真机验证图标、注册、单独数据及失败场景。应尊重 RemovalDisallowed 与配置描述文件管理权限。系统共享 Safari 数据不能作为所谓“清理残留”批量清除。

## 2026-11-02 补充核验（build12，独立副本）

- 已知真机诊断仅确认 iPhone 14 / iOS 16.6 的 `+webClipWithIdentifier:`、`-removeFromDisk`、`-requestIconUpdateInSpringBoard` selector 存在；未调用，不是行为验证。上文“没有 iOS 16.6 runtime 导出”不否定这项用户提供的元数据证据。
- Apple 开源设备管理 payload 规范：https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.webClip.managed.yaml ：`IsRemovable` 为描述文件中的受管策略，默认 true，false 禁止用户移除。它不是已经证明等价于本项目读到的 Info.plist `RemovalDisallowed` 字段；不能以字段缺失或 false 推断非受管，未知一律不得自行删除。
- 公开开源 TrollTools WebclipsThemeManager：https://github.com/sourcelocation/TrollTools/blob/main/TrollTools/Private%20APIs/Themes/WebclipsThemeManager.swift#L59-L64 对自己创建且名称包含特定前缀的主题快捷方式直接 `FileManager.removeItem`；不是 UIKit 原生删除，也没有证明 SpringBoard 注册、隔离数据等完成清理，不可用作任意 WebClip 干净删除的依据。未复制其代码。main 为移动引用，检索只代表所见版本。
- 相同项目 UI 的 Full reset 见 https://github.com/sourcelocation/TrollTools/blob/main/TrollTools/Views/Themes/ThemesView.swift#L110-L111 ；该提示不证明通用删除语义。
- 社区代码搜索 grep.app 返回 429；Sourcegraph 受到防火墙阻挡；Google 检索未找到可核验的通用原生删除调用。搜索引擎 AI 概览没有具体源码佐证，不作为证据。没找到并不等于不存在。

## 当前结论和后续验证

继续默认禁用：没有可证实的 identifier 映射、调用主体/权限、受管判断、返回值与 UI 同步/清理完整性语义；没有引入猜测的调用实现或实验开关。build12 的 UIKit 页面只提示删除未启用；旧 SwiftUI 页面确认后仅逐项拒绝，取消不调用 delete；不可将拒绝显示为成功。备份只是原目录二进制 plist 导出，部分项可失败；目前没有恢复能力、也不含系统注册、布局和共享 Safari 数据，不能承诺可回滚删除。

必须先找到针对 iOS 16.6 的系统调用链及授权/托管策略来源，再在完全独立的可丢弃设备上创建合成普通、全屏及受管样本，分别对照系统长按删除：标识解析、确认取消、消失及重启后不复现、SpringBoard 注册、独立数据与失败/权限、受管拒绝、重复/不存在对象；期间不触碰真实书签，不清共享 Safari 数据。只有逐项验证成功后才能设计后端/测试和默认启用。mock 只能验证自身控制流，不能证明私有 ABI 或系统清理。


## build22 实验版更正（以上历史决定不再描述当前实验入口）

删除仍仅限用户自建 `WCM-DELETE-TEST` 单项，先双重确认并完成完整副本备份验证；不修改源 plist，不覆盖任何实际受管或禁止标记。原 `ConfigurationIsManaged` 必须是 CFBoolean false；`RemovalDisallowed` 如存在必须是 CFBoolean false，缺失只是未声明，并不直接授权。构造匹配的 UIWebClip 实例并核验调用签名、路径、标识；运行时 `removalDisallowed` 必须明确返回 false，缺方法、签名不符、true 或异常拒绝。若有 `configurationIsManaged`，亦必须签名正确且返回 false；不存在不自动拒绝。调用前重新读原 plist 并重新检查运行时状态，至多调用一次。检查无法消除所有并发竞争，也不是完整 MDM 政策判定或系统安全保证。CFBoolean 必填策略是本实验的保守约束，不是宣称 Apple 强制如此。私有 ABI 检查只验证调用形状，不证明运行时语义；真实设备删除行为尚未验证。
