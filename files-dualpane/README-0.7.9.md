# Files DualPane 0.7.9

## 本版最小修复

0.7.8 的普通 file 路径仍可能被原生 textSlot／label 的固定宽度或最大宽度卡住，或者 image-only 状态早于文字 ready 而被永久缓存。本版只修这些已识别的文字布局路径，保留 folder 紧凑样式、图像等比尺寸、选择行为、主页／页头与跨窗格功能。

- 先验证文字右缘链，再对 getter 已识别的 label／textSlot 的无第二项、倍率 1、常量 `width ==`／`width <=` 约束记录并暂时停用。约束对象与原常量保存在状态中，退出紧凑模式和复用时仅在身份与写入状态仍匹配时恢复。未知宽度关系不释放。
- 支持已识别 sibling label 的零常量 same-right／same-trailing 关系，优先已有祖先边；同右缘只保留零偏移，不沿兄弟链重复叠加 padding。非零兄弟偏移仍拒绝。
- 支持 textSlot.trailing → 后续 arranged provider.leading：必须证明 provider 自身的正固定宽度与 trailing 到 row 的链，保持 provider 宽度／右缘不变，文字到其 leading 留 10pt；provider 宽度改变会使缓存失效。不能证明的额外 arrangedSubview 不解除文字限宽。既有 provider guide 保留逻辑不变。
- 对零 bounds 的已知 root／row／textSlot／label 保存 pending 状态；每个身份只安排一次主队列 retry，先验证 ticket 与 cell identity，再走原有 scope／selection／busy 门禁。ready 后缓存失效补做文字；仍未 ready 时不递归派发、不增加逐帧循环。退出或复用会取消旧 ticket。
- 计划仍在 setter 前写入，避免同步重入。没有 Swift offset、KVC 猜测、未知 view 扫描、文本 frame／transform 改形或新 layout hook。没有新增用户报告或截图采集。

## 验证

`tests/style_host.py` 展开未修改的生产 Objective-C，Foundation/CoreGraphics doubles 执行活动 right／trailing／provider-leading 与 width 等式。覆盖 textSlot 与 label 各自固定／最大宽度、双向 sibling same-right、status.leading 与动态 provider 宽度、未知尾部拒绝、delayed-ready 和过期身份拒绝；检查复用／退出恢复、同步 setter 重入、1000 次重复更新零新增 setter／retry。旧 folder、portrait／landscape 图像比例以及其他生产 host 测试继续保留。

独立 Files workflow 固定读取旧提交 `8a803fd6df47febded148e8892a1556071a1a295` 的 0.7.8 生产文件并校验 SHA-256；五类新 fixture 分别要求旧版在对应断言判红，再执行本版全套新绿测试。既有 margin／图像尺寸／图像正方形／右缘预留变异也必须判红。最初 width 回归的真实旧红 run 为 `40661529889`。

RootHide 包版本为 0.7.9，CI 同时编译 arm64／arm64e，验证包版本／架构和每个 Mach-O slice 签名页，生成 deb 与 SHA256SUMS。

这些不是 UIKit 真机布局测试；公开属性与测试图不能证明任意 Files／provider 实例都采用支持的约束结构。未知、冲突或无法证明安全右缘的布局保留原生行为。本版未在目标真机安装验证，不宣称实际文件右空位已在真机消失。
