# Files 双窗格：原生验证优先

更新：2026-10-27。目标机：iOS 16.6、RootHide、系统 `com.apple.DocumentsApp`。

## 已纠正的路线

先验证两套原生独立导航、选择、历史和 scene/provider/action 上下文，再验证跨栏桥。不将自绘列表或两个目录 picker 替代原生双栈；本项目当前不实现自绘文件面板。Firefly 源码、包和 workflow 均不改。

第一包为 `dev.filesdualpane.nativeprobe` 0.1.0，只读观察探针，不是双窗格成品。注入过滤仅 DocumentsApp，运行时再核对 bundle 和系统 16.6.x。不 hook、替换或迁移原 controller，不调用猜测的私有构造器。诊断按钮及报告页是探针自身 UI，不是文件浏览器替代品。

## 16.6 证据核查

本轮 GitHub repository search `iOS 16.6 runtime headers`、`iPhoneOS_16.6` 未返回精确匹配（这不证明不存在）。候选 `qingralf/iOS16-Runtime-Headers` README 仅称 iOS16，无版本标签，根目录无 Applications；无法据此认证为 16.6 Files dump。`nst/iOS-Runtime-Headers` 顶部标签为 11.4 等旧版，不作为 16.6 契约。

先前 16.0 build 20A5303f 的 `DOCSplitBrowserViewController`、`DOCFullDocumentManagerViewController`、`initWithConfiguration:sourceObserver:` 只能作为检索线索。签名不等于可独立构造的工厂/生命周期契约。第一包不包含第二控制器实验开关，也不假装具备初始化证据。真机已加载类的 runtime 元数据是下一轮证据；Swift-only 成员可能无法从 Objective-C runtime 看到。

参考：
- https://github.com/qingralf/iOS16-Runtime-Headers
- https://github.com/nst/iOS-Runtime-Headers/tags
- https://github.com/lechium/iPhoneOS_16.0_20A5303f/tree/master/Applications/Files
- https://github.com/roothide/Developer
- https://developer.apple.com/documentation/uikit/adding-a-document-browser-to-your-app

## 第一包实际行为

1. 通过公开 UIApplication/UIScene/UIWindow 通知，在前台 normal-level key window 附加 `FP 诊断` 按钮。无 timer、无私有挂载点、无全局方法交换。若存在模态页，先关闭模态再触发，避免干扰 picker 或操作菜单。
2. 用户点按钮，再点“生成报告”，才在 UIKit 主线程做一次快照。遍历公开 scene/window/root/child/parent/presented/presenting/navigationStack/split/tab 关系。
3. 每份快照为对象分配 o1、o2 等匿名 ID；不输出内存地址。ID 仅在同一份报告中可比较，不可跨快照比较。报告不读 scene persistentIdentifier。
4. 输出实际类名、父类、类自身方法及 type encoding、属性定义、ivar 名称及类型（不读值）、直接采用的协议及其属性元数据。加载类候选由 DOC、DocumentManager、DocumentBrowser、FileProvider 名称匹配选出；不加载额外 framework，不触发私有 getter/构造器。候选不是“对象存在”的证明。
5. 导航对象身份来自公开 UIKit 关系；私有 selection/history/provider/action/context 对象关联全部标为 UNREAD/UNVERIFIED。名称或类型线索不等于对象关联已证实。后续只可在确证安全关系后扩大白名单，不能用 KVC 或 object_getIvar 全盘读取。
6. 报告在探针原生文本页查看，通过系统分享按钮由用户选择目的地。探针不写文件、不建立长期日志、不联网/上传、不读用户文件内容、标题、路径、URL、bookmark 或 provider 账号。系统分享目标可能保存用户主动分享的副本；这不是自动上传。
7. 有对象/方法/类数量及报告长度限制，达到限制明确标 TRUNCATED。枚举有限，不声称是完整 runtime dump。

## 分阶段验收，不混淆结论

| 阶段 | 首包状态与下一步 |
|---|---|
| S0 注入、按钮、显式捕获 | 编译无法证明；目标机出现入口并成功出报告才确认 |
| S1 原生图/元数据 | 只观测公开 UIKit 图与静态声明；私有上下文身份未读 |
| S2 工厂/生命周期 | 未验证；根据 16.6 报告确认 configuration/source observer/scene/action manager 等安全建立与拆卸契约 |
| S3 第二原生控制器 | 未构造、未展示；禁止复制 view、偷移系统现有 controller 或共用状态冒充独立栈 |
| S4 双栈独立性 | 未测试；需明确验证左右导航、选择和历史互不污染，以及 scene/provider/action 路由正确 |
| S5 跨栏桥 | 未测试；首包绝无复制/移动/删除/重命名等操作 |

后续实验只有在 S2 证据充分时才加入可关闭原生双栈实验。跨栏首测必须用户明确选择专用测试目录和样本；先只读检查路由、来源目标上下文及可用性，不能用写操作证明桥已安全。真正文件操作属于独立批准及测试阶段。

## 安装、触发、分享与卸载

- 将真正编译产物 .deb 用用户现有 RootHide 包管理器安装；包架构应为 iphoneos-arm64e。不要直接当普通 rootless 包用，不自动安装或重启设备。
- 在当前 RootHide 环境确认 Files 可启用注入。彻底退出并重开 Files。处于普通浏览页时，右下方应见 `FP 诊断`。
- 点 `FP 诊断` → `生成报告` → 右上分享。点“完成”关闭报告。若按钮无响应，先关闭任何模态页。没有入口不是双栈失败结论；先查注入开关、系统版本和 key window。
- 可在普通浏览页、返回上一级后、进入/退出原生选择模式后各手动生成一份，不必选个人文件；对比仅看图结构和类型。不能用跨报告匿名 ID 判定对象相同。
- 卸载 `dev.filesdualpane.nativeprobe` 并彻底退出重开 Files；不改 Files 偏好或数据，没有持久报告需要清理。若异常，先关闭 Files 注入/卸包，勿操作用户数据。

## 构建与局限

RootHide Theos；独立目录 `files-dualpane/` 与 `.github/workflows/files-native-probe-roothide.yml`。沿用安全浏览器 TLS GitHub API 桥，token 仅来自环境变量、不进 repo、不回显；禁止带凭据 curl -k。

静态检查覆盖过滤范围、禁止危险 API、只读反射、主线程断言及报告阶段字符串；CI 实际编译并检查 deb 包 ID/架构。静态检查和构建成功均不等于 iOS 16.6 真机通过。入口使用公开 UIKit 无猜测私有 selector，但其可见性、模态流程、RootHide 注入及特定 Files 子类 override 仍须真机验证；不可声称已经验证两套原生导航成功。
