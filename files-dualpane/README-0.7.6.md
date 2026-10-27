# Files DualPane 0.7.6

面向 iOS 16.6 / RootHide 的 Files 双栏插件。包包含 arm64、arm64e。保留原生双栏导航、选择、跨栏协调复制/移动、预览与删除确认；没有首页恢复或新数据采集。

## 本版样式范围

- 仅独立双栏 pane 中的列表。范围同时检查 responder 链、控制器父链、DOC 类链、列表模式与行宽；原 Files 主界面和网格不套用。
- DOC `UICollectionViewListCell` 的多选圈与 disclosure 箭头使用公共 accessories API 隐藏，保留其他附件；不改变真实选择状态。选中背景使用公共 backgroundConfiguration 独立处理。两者不依赖 contentConfiguration 是否为公共配置，nil / provider custom content 也可命中。
- 公共 `UIListContentConfiguration`：20pt 图标、6pt 图文间距、左右10pt/上下4pt内边距；14/13pt Dynamic Type 字体。按行高选择名称1或2行，放不下则保留原生内容样式。
- 已知 DOC 原生结构：ABI 匹配的 accessibility title/thumbnail getters、唯一 `DOCThumbnailFittingImageView`、相邻文本槽的水平 UIStackView。仅处理可证明兼容的槽宽/图像宽高约束与 row leading/trailing 到 contentView 或其 margins guide 的等式约束。原生边距只调整水平方向；不改 frame、transform、Swift ivar offset 或行高。字体与行数必须在已有 label/cell 高度中装得下。
- Sidebar 仅走可靠的公共 content configuration，不进行 DOC slot 修改。

## 事件、恢复与未知回退

样式只在 willDisplay / configuration 更新事件执行，不挂 layoutSubviews 或每帧遍历。真实 isa 子类 override 和父/子桥接均有去重保护；busy guard 与完整状态计划先于 setter，避免同步重入反复写入。

退出范围和复用时恢复一次；对象、文本、图像或原生配置已替换时不把旧快照覆盖到新对象。样式已一致时不重复写入。Getter 存在但 ABI 不兼容、未知/多重缩略图、未知约束关系、改名状态及固定高度放不下时停止原生内容修改；可支持的附件/背景通道仍独立工作。未知 Swift 内存布局不猜 offset，也不宣称全部 DOC 私有版本都可用。

## 验证

独立 Files GitHub Actions 运行源码安全契约，以及展开真实生产 `CompactCells.inc`、`NativeCompact.inc`、`NativeActions.inc` 的 Foundation/CoreGraphics 宿主测试。fixtures 包括真实 Objective-C 类继承/方法 hook、controller/responder scope、AutoLayout 约束 doubles、nil/custom DOC content、typed getter ABI 拒绝、NSDate/nil detail、对象/文本 identity 边界、setter 同步重入、1000次零重复写入、退出/复用/内容替换、固定高度回退和父子/桥接原方法各一次；公共 margin 与原生图标尺寸 mutation 必须被拒绝。

保留 current-location、Swift diffable bridge、file core/selection、coordinated preview、transient state 等现有 fixtures。CI 构建双架构 deb，并检查包版本、架构切片、签名和 SHA-256。

**测试边界：**宿主视图/约束是 doubles，不是 UIKit 渲染或 AutoLayout 求解器，也不是 Files 真机验证。CI 成功不等于已证明设备显示、私有 getter 可用性或旧卡死根因。此版本不增加诊断采集。
