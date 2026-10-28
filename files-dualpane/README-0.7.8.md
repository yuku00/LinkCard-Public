# Files DualPane 0.7.8

## 修复对象

0.7.7 修的是图像等比尺寸，并没有覆盖这次反馈的普通文件右侧 disclosure 空位。本版只增加原生文字右缘能力，不再改图像比例，也不改跨窗格操作、主页或页头（左菜单／中关闭／右菜单）。

## 具体行为

- 原有 `FPPlanEdges` 要求 row 的 leading 和 trailing 都直接连接 contentView／其 margins guide，并且与图像尺寸规划串联；文件的 guide／文字槽预留会让整组计划被拒绝。
- 新增独立 trailing 计划：使用现有、ABI 已验证的 accessibilityTitleLabel／accessibilitySubtitleLabel，沿真实 active、倍率为 1 的祖先 trailing 等式读取 label → textSlot → row → contentView／guide 的约束链。只改已验证链的入口 constant，回收标题、副标题和文字槽的行尾留白；图像不匹配或 leading 不是直接 root 链不再阻断文字右缘。
- 无附件时文字右缘为 contentView.trailing − 10pt；root margins guide 的原有边距计入方程，不叠加成额外空白。
- provider status／下载附件继续由原生 accessories 和 guide 布局管理。存在保留附件时不抵消自定义 guide 的原生预留宽，不修改 guide，文字在其边界内再留 10pt。不估算附件像素宽度，不覆盖状态区域。
- 只有披露箭头和 multiselect 被原有过滤器删除，其他附件不删除。未知或冲突约束不进行盲改；尾部另有 arrangedSubview 的结构仍由旧路径管理，不承诺本版扩宽。
- 保持既有 folder、图像尺寸和字体路径；只在配置／显示／复用事件写入，不增加 per-frame 或 controller 布局扫描，不写未知 frame、不使用 transform、KVC 或 Swift ivar offset，也不调用未证实的 trailingConstraint getter。
- 计划在 setter 前存储；附带保留附件和上游 guide 方程见证，原生边界变化会失效重算。恢复只在 identity 与写入值仍匹配时执行，避免覆盖 native reconfiguration。

## 回归范围与边界

新增 fixture 直接执行生产 Objective-C，并求解活动 trailing 等式得到 title/subtitle 可用宽，而非字符串匹配或 unknown no-op。覆盖普通文件与 folder、隐藏 disclosure 前后、无 disclosure 但仍有 reserved gap、provider guide 36／52pt 变化、右缘 10pt、图像不匹配／leading 非直接 root、selected／普通模式／复用恢复、同步 setter 重入和 1000 次重复更新零新增写入。

旧版生产代码加新 fixture 的真实 CI `40655995165` 在 title 可用宽断言判红（commit `6d782fff0de8e60316b782d1bd482b99a6a4aaa8`），旧有图像与 native 用例仍通过。持续集成还运行主动恢复右缘预留的变异，要求用例拒绝它。

这些是生产代码 + Foundation/CoreGraphics doubles 的方程测试，不是 UIKit 真机布局测试。实际生效条件是目标 native 行存在上述可验证 trailing 链；公开头只证明相关属性存在，不证明任意系统/provider 的实例结构。本版没有新增用户报告或截图采集，未在目标真机安装验证。

打包要求：RootHide，版本 0.7.8，dylib 同时包含 arm64／arm64e，CI 验证版本、架构和签名页，输出 deb 与 SHA256SUMS。
