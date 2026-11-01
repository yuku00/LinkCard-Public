# 语音转述主工程增量接入记录

- 开始时本地主工程 HEAD：cb0704e（保留；未 reset、未清理工作树）。
- 接入目标仅隐藏语音转述图标与 0.35 秒未聚焦短点按聚焦防误触；不新增弹窗、不重放业务动作。
- 接线前实查 release-state 与独立分支远端均为 cb772143a6b4068659d0da9b7f17f12afefcea9c；main 为 03ddb13b4a015e9fe456d19ba6502c8b0a902a9a，未修改它。
- 已接入 Sources 三文件、Core 两项配置读写校验及安装、Settings 两个独立开关和准确说明、Appearance 已有 Input/InputWindow 刷新；不重复安装布局选择子。
- 本地 29 项结构护栏、纯 C 生产逻辑已通过；新增原生测试完整编译生产 WUDictation.m 与精确 Core WUHook/WUMatches，UIKit 为明确标注的 Foundation/CoreGraphics mock。真实 iOS UIKit 编译仍由完整构建的 dylib 目标执行。此次发布等待 CI；没有真机验收。

## 行为和恢复边界
- 未聚焦、原 hitTest 命中明确所属图标、单触点和完整聊天上下文时，改由输入框承接；严格短于 0.35 秒、始终未拖出、未取消且结束前后上下文有效才额外聚焦。普通输入、已聚焦与未知布局保持原命中；每个原 touches 回调调用一次，不异步重放任何业务操作。
- 增加 touchesMoved 类型验证和拖出粘性取消、多触点/重复 began 取消、原 ended 同 view 重入失效、切账号/会话/窗口/配置/前后台/图标替换复核。部分安装时 ready 为 NO；已占用 Hook 键返回 YES 但 original 为空不能冒充安装成功，重试不覆盖已保存 original。
- 已确认宿主 bundle 内的具体图标类可独占拦截 setHidden：只改带对象标记的图标，保留最新宿主请求，关闭配置、离窗/父视图失效或切号时恢复。系统 UIView/UIImageView 不安装全局 Hook。
- UIImageView 及不适合专属 Hook 的实际所属图标采用对象级 alpha 快照隐藏，宿主 hidden 完全不写，因此最新 setHidden 意图自然保留；通过既有 getter/布局/离窗/配置刷新恢复。alpha 被宿主改成非零时记录新值；遮罩期间宿主再次写 alpha=0 无法与本模块的 0 区分，这是快照路径的明确限制。未观察到的布局更新间隙可能短暂显示；离开所有回调后才发生的脱离须等下次刷新/配置通知恢复。非明确所属、非 UIView、ABI 不匹配均不作用。
- UIKit 的触摸派发、宿主 touches 自身副作用、VoiceOver/硬件键盘、真实控件类和其他插件共存仍需真机；mock 不能证明微信真实行为。没有真实微信操作、真实发送或用户文件操作。

## 本增量测试
- 保留原纯 C mask/route/0.35 秒边界测试。
- 原生 mock：完整生产模块、真实 ObjC runtime、真实 Core Hook 注册器；覆盖 original 次数、重复安装、错误 ABI、已占用 Hook/部分安装回退、短点按/长按/拖出返回/多触点/取消/重入/复用/切号、宿主最新隐藏意图、父视图失效、总开关恢复和 UIImageView 对象级隔离。
- 扩展既有 P0 配置用例，直接使用生产 ReadConfig/WUSave 做两个开关独立保存/重载/总开关/类型拒绝往返；既有消息构造 I/q/i/Q、31 项统计 XCTest 和其他回归不删除、不弱化。
- 所有既有改动、P0/统计测试、github_native.py 的 cache:no-store 变更保留。
- 不发布逆向输出、原库、用户数据；不触碰 main 的 Ghidra 工作流。
