# Files DualPane 0.7.3

## 本次简化

- 删除自定义首页、默认 Downloads、首页等待/重试、导航确认和错误提示；两侧菜单只保留跨栏复制/移动。自动打开双窗格与页头左菜单／关闭／右菜单不变。
- 不再关闭原生 `restoreLastVisitedLocation` / `saveLastVisitedLocation`，复制原 Files 的配置值。每次创建两栏前，从原配置对应的 `DOCUserInterfaceStateStore` 读取原生当前/最近界面状态，将位置 archive、有效根位置和选中 tab 复制到两个独立的新 state。由原生工厂恢复，不解码、猜路径、强制导航或异步抢占。
- 状态键改为真实 scene + 固定 left/right，取消每次随机 UUID；依旧用插件专属内存隔离，防止两栏共用导航/选择或覆盖 Files 自身偏好。左右目录不会分别跨进程永久保存；重新创建时重新承接原 Files 的原生状态。提供商不可用、原生恢复关闭或无历史时，显示结果由 Files 决定，可能仍是浏览页。
- 删除旧首页书签核心和菜单，启动仅清理准确插件偏好域 `dev.filesdualpane.home`；不清理 Files 系统历史，不停止全局偏好服务。卸载仍只清理插件自己的域文件。

## 空间回收

- 继续实际移除公开 disclosure/multiselect accessory，而非隐藏其图像；保留提供商/下载状态 accessory。
- 额外清零 cell/contentView 的继承边距，禁止 content configuration 保留父视图布局边距，以 6pt 内容边距替代旧尾部留白；退出作用域/重用时恢复。
- 仅针对已证实 thumbnail 横向栈中的纯 UILabel/文本 stack 区域，允许剩余宽度分配给文字、释放该文字 slot 的固定宽约束，纵向文字 stack 使用 fill；未知控件及状态图标不改。所有约束、分配、hugging 和 alignment 均保存并恢复。
- 列表标题最多两行，副标题一行；侧栏维持单行。行高至少 44pt，支持 Dynamic Type。没有整体 transform，也不增加按钮。

## 保留与验证

原生菜单、原生选择状态与背景、跨栏复制/移动、冲突不覆盖、预览及安全 scope 生命周期保留。当前目录使用真实可见 container 的 location 映射；共享 FileProvider resolver 独立保留在 ProviderLocation.inc，不依赖首页。

CI 执行静态约束、生产 native state seed/隔离、当前目录映射、公开边距回收/恢复、选择/侧栏、Swift diffable selection bridge、文件传输/冲突和协调预览 fixtures；构建 RootHide arm64 + arm64e，校验签名与包版本。

这些 Foundation/view doubles 与源码断言不是越狱设备上的 UIKit/Files 运行截图；原生恢复结果和真实窄栏排版仍需要设备安装确认。不承诺左右目录永久独立记忆。
