# Files DualPane 0.7.2

面向 iOS 16.6 / 20G75、RootHide 的独立原生双栏插件。保留 0.7.1 的页头左栏菜单／中间关闭／右栏菜单、无底部操作栏、双栏 always、原生选择背景无圈和跨栏协调复制／移动。

## 布局

- 仅插件 pane 内的原生浏览／位置 sidebar 使用紧凑标题、14pt Dynamic Type 字体、20pt provider 图标槽、6pt 图文间隔。位置名称单行尾部省略，避免 Mini/s 拆行；辅助功能仍保留完整原生文本。触摸行高至少 44pt，大字号按行高增长。
- 文件列表与 sidebar 只移除 `UICellAccessoryDisclosureIndicator` 装饰箭头；文件列表同时保留原有去多选圈与选中背景策略。状态附件、导航栏返回按钮和原生行点击委托不改。
- 复用／离开作用域／关闭时恢复字体、图标槽、间距、附件和标题策略。附件已被原生替换时不把旧附件强行塞回去。没有全局 UILabel 或 UIAppearance 改动。
- sidebar 样式依赖原生 cell 提供 `UIListContentConfiguration`；不猜 Swift 字段或给未知自绘 provider 视图强改布局。

## 首页

偏好域只有 `dev.filesdualpane.home`，`left` / `right` 各自保存 schema 1：

- `defaultDownloads`：没有自定义首页以及清除首页后，尝试系统实际选择的下载位置。
- `custom`：验证过的 minimal bookmark。
- `browse`：明确的浏览／位置总览，不需要虚构目录 URL 或书签。

旧版 NSData bookmark 原样装入 custom schema；不跨栏迁移、不覆盖失败记录。损坏、过期、不可访问的书签保留，明确提示并退回浏览。

保存目录不再使用 `hierarchy.lastLocation`。通过实测导出的 `provideContainerControllerAt:from:isUserInteraction:isBrowsingTrash:` 给原生容器记录其真实 location，并以当前可见 navigation controller 的容器为准；折叠 sidebar 显示时明确判为浏览总览。真实 provider root 但没有 URL，不会被当成浏览总览。

若目录节点未缓存 URL，尝试 FileProvider 的 `fetchURLForItem:creatingPlaceholderIfMissing:NO:completionHandler:`，不创建占位目录。书签解析后通过 `fetchItemForURL:completionHandler:` 重新取得节点，以真实 provider domain 对应原生 source identifier 构造 location，再调用 `showLocation:fromRootAnimated:withCompletionBlock:`。这与仅选中项目的公开 reveal 不同；只有可见 location 匹配才报告“首页目录已打开”。所有私有入口调用前核验 runtime ABI，不读 Swift offset、不猜枚举。

恢复独立于“已确认列表模式”，就绪等待、provider 解析、导航验证均有界；触摸即取消后续自动恢复，晚到回调不能覆盖更新过的首页。清除只改本栏模式并立即尝试默认下载。

### 系统下载位置的明确边界

只读 `DOCDownloadSettings.currentDefaultDownloadsLocationItem`，用原生 favorite location 或同一 provider domain 的 source 构造目录位置。**不根据显示名搜索，不猜 app sandbox/Downloads、不使用 NSDownloadsDirectory。**

`fetchDefaultDownloadsLocationItem:` 的实现存在创建默认目录的路径，因此本版不调用它。当系统尚未向只读 getter 提供下载节点、provider domain 未就绪或导航入口不兼容时，最多等待约 5 秒后退回浏览，并显示“系统下载位置尚未提供可导航节点”；不假称进入下载、不创建目录、不申请新权限、不更改系统下载设置。已有可解析节点时适用于本机、iCloud 及支持该原生映射的 provider；不能保证所有 provider root，也不能保证冷启动时系统下载缓存已填充。

## 验证与限制

CI 编译实际生产 Objective-C/Swift，运行 Foundation host fixtures：文件协调核心、Swift 泛型选择桥、preview/state 生命周期、首页 schema／旧书签迁移／失败保留／左右独立／root-vs-folder／stale lastLocation 排除、恢复等待与取消策略，以及生产附件过滤／恢复、sidebar 字号行高策略与 largeTitle 恢复。

Host 使用 UIKit doubles，不等于真机截图或 FileProvider 集成测试。尚未真机验证；当前可见容器关联、原生 showLocation 进入目录、系统下载缓存可用性与第三方 provider 仍需设备验收。未增加诊断报告采集。卸载仅删除插件自有偏好 plist，不删除 Files 设置或文件。

## 原生接口依据

- 已有 20G75 runtime 报告：DOCConcreteLocation 的 browseStartingPointsLocation、Files hierarchy、Full 的 container factory/showLocation、DOCDownloadSettings getter、DOCFavoritesManager 与 FileProvider source/domain；用户报告不随源码发布。
- 公开 16.0 头：`lechium/iPhoneOS_16.0_20A5303f/Applications/Files/DOCFullDocumentManagerViewController.h`、`DOCSourceObserver.h` 与 sidebar 声明。
- 公开 FileProvider 声明：`nst/iOS-Runtime-Headers/Frameworks/FileProvider.framework/FPItemManager.h`。公开旧头不是 20G75 执行保证，所有入口仍由 runtime 签名门控。
