# MailLoadCheck 0.1.0 — 空载对照，不是修复版

适用对照：TrollFools 向系统 Mail 注入，iOS 16.6 / 20G75。

这个 dylib 只有返回即结束的 C constructor 和只读版本字符串。没有 UIKit/ObjC、hook、按钮、通知、日志、账号、文件、网络或偏好访问；不链接 RootHide、libroot、Substrate。包含 arm64 / arm64e；install name 为 @rpath/MailLoadCheck.dylib，仅 dylib 自身 ad-hoc 签名，无宿主 entitlement。

## 只做这一次对照

1. 记住下载文件的唯一完整名称；可用同目录 SHA256SUMS 核对。不要与 MailRules / MailProbe 同时注入。
2. 使用原来注入旧插件的工具撤销旧 MailRules / MailProbe，并通过它的还原机制恢复原始 Mach-O；不是仅删掉 dylib 文件。若工具不能确认还原，不要叠加本库。不要重装、重置、注销账号或清理邮件。
3. 沿用同一 TrollFools 注入路径，仅导入此 dylib；其已注入列表应显示这次唯一文件名。空库没有 UI，不会显示版本按钮。
4. 彻底结束并重新打开同一个系统 Mail，保持账号、筛选、网络、入口及其他插件状态不变。只看原来同一目录树是否恢复，以及同一范围的计数（此前正常 842，异常 515；计数会随新邮件变化，目录完整性优先）。不需要再采集或上传报告。

正常：收窄到旧 Probe 特有代码、依赖、构建兼容性或交互；不能直接判定 sendEvent。
仍异常：优先沿共同注入/加载/签名/宿主环境方向查；不能据此证明权限丢失或邮件被删。

## 对照边界

未注入正常是已知基线；本库与 0.5.2 的 ID、链接和构建特征也不同，因此不是只移除 sendEvent 的单变量实验。成功注入列表不等于运行时加载证据；若无法确认是干净的新进程/注入成功，结果应标记为不确定，不强行归因。不添加 UI 或日志来确认。

这是静态验证过的加载对照，不是设备验证过的功能修复。注入器仍可能改写或重签宿主，空代码不能消除注入工具本身的风险。撤销时仍用同一工具的还原功能，不删除账号/邮件。

## 构建

GitHub macOS runner + Xcode iPhoneOS SDK + Apple clang，分别 -arch arm64 / -arch arm64e，-miphoneos-version-min=16.6，lipo 合并，ldid -S（无 entitlement 文件）。SHA256SUMS 对应下载字节；TrollFools 导入后如重新签名，设备内文件哈希可能不同。CI 审计两切片的依赖、ID、最小系统版本、零导入、唯一 constructor 入口/ret 机器码和 CodeDirectory 页面哈希。
