# WebClip Manager — build12 UIKit 直接读取

> 当前实现与验证边界以 [build12 说明](Docs/BUILD12-UIKIT-DIRECT-READ.md) 为准。使用与 build9 相同的非容器权限和系统 HOME，以纯 UIKit 双页业务界面直接扫描书签、只读解析 Notes 并导出。生产入口不再呈现诊断首页/SwiftUI hosting，不再通过受阻 helper 读取。没有新增权限或 root 操作。**尚无本构建 iOS16.6/TrollStore 真机验证，不得称已修复真机问题；删除禁用。**

## build8 历史记录

> build8 的历史行为见 [build8 恢复说明](Docs/BUILD8-STARTUP-RECOVERY.md)，不代表当前入口。

## build6 历史记录

> 当前状态以 [build6 证据、变更及最少测试步骤](Docs/BUILD6-READ-ACCESS.md) 为准。用户已确认 build5 在 iPhone14 / iOS16.6 / TrollStore2.1 启动、SwiftUI 和手动刷新正常；未解决的是 WebClips 目录读取拒绝，不是启动闪退。build6 保留已成功的启动架构与原六项权限，仅增加 Safari storage 候选、POSIX 只读访问与脱敏错误诊断。真实读取效果待设备确认，删除禁用。下面初始开发时期的构建/授权状态仅是历史记录，不代表当前结论。

## 初始开发记录（历史）

面向 iOS 16.6 / TrollStore 的 SwiftUI 原生工具，最低部署 iOS 16。**没有编译、签名、安装或真机验证；删除功能明确不可用。** 本次仅写入源码，不创建公开仓库、不上传、不发布、不运行 Actions。

## 本轮更新

- 原生双 Tab：书签管理 / 备忘录导出；统一 insetGrouped 卡片、系统字体与青绿色点缀，支持系统深浅色和动态字体。书签主列表不再展示长 UUID，搜索仍可按标识查找；保留搜索、多选、重复/全屏筛选与隐藏选择计数。
- Apple Notes 直读路径：确认后定位 Notes AppGroup，SQLite 只读源连接 + backup API 创建内存一致性快照，解压 gzip 并按 MIT 上游协议映射提取 protobuf 正文，批量保存 TXT/Markdown。不再要求先手动复制文本。跳过锁定、删除标记和无法解析记录，明确计数；TXT/MD 导入作为备用。附件/表格不重建，详见 [Notes 研究与边界](Docs/NOTES-EXPORT.md)。
- 书签页提供「诊断」：仅检查 UIWebClip 类和相关方法元数据，不调用方法；脱敏 JSON 只包含 iOS 版本、读取状态和接口存在性等白名单字段。
- 手动 workflow 默认构建 unsigned ZIP；显式勾选后可用 Homebrew ldid 写入并回读核验 entitlement，打包待验证 TrollStore IPA。本轮未运行。详见 [构建与首次测试](Docs/BUILD-AND-TEST.md)。
- 新增 `Sources/AppleNotesStore.swift`、`Sources/AppleNoteBody.swift`、`Tests/AppleNotesTests.swift`，接入现有 Notes 界面。合成 XCTest 涵盖 gzip/protobuf、WAL 快照、锁定/删除跳过、缺失结构、容器识别与符号链接拒绝；已编写但未执行。MIT 协议引用、完整许可与修订号见 `NOTICE` / `ThirdParty`。静态检查不是编译通过证明。

## 已实现

- 直接枚举 `/var/mobile/Library/WebClips` 下 `.webclip/Info.plist`，读取 Title、URL、FullScreen、RemovalDisallowed；读取常用 icon.png / icon@2x.png / icon@3x.png。不下载网站图标，不扫描 Safari。
- 名称/URL/目录搜索、多选、选择当前结果、全屏筛选、精确 URL 重复筛选。**重复组包含所有成员，不自动选择“可删除副本”**；空 URL 不参与去重，不合并大小写、fragment、query、尾斜杠。
- 导出前确认。逐项备份原始 `.webclip` 目录文件和空目录，系统文件导出器保存单个二进制 plist（`.webclipbackup`）；并非 ZIP。清单包含每项成功/失败，部分失败不会伪称完整备份。没有恢复功能。
- 删除入口确认后只逐项返回“未删除”，没有 `rm`、私有调用或 Safari 清理逻辑。受管理 WebClip 应通过原配置描述文件或管理员处理。
- 扫描/文件读取在 Repository actor 执行；界面更新在 MainActor。读取失败与空列表区分。无遥测、网络服务、自动打开链接或外部依赖。

## 删除接口核查结论

详见 [接口证据](Docs/DELETE-API.md)。公开 runtime header 中存在 `UIWebClip -removeFromDisk` 声明，但声明不证明该方法与主屏幕长按删除语义一致，也不证明 iOS 16.6 的权限、SpringBoard 图标更新、缓存和独立站点数据清理行为。**没有拿到可验证的 iOS 16.6 完整删除调用链，因此本版 fail closed。** 即使以后 `NSClassFromString` / `respondsToSelector` 成功也不应据此启用删除。

## 本地工程

```
Sources/App.swift                  SwiftUI UI / FileDocument / 状态
Sources/Repository.swift           只读扫描 / 备份 / 拒绝删除
Tests/RepositoryTests.swift        运行时生成合成数据，不含用户归档
Config/TrollStore.entitlements     待验证权限草案
project.yml                        XcodeGen 工程定义
.github/workflows/build.yml        未来手动构建定义（现在不运行）
```

已授权开始编译，但本次检查确认：当前 Linux 没有 Swift、Xcode、XcodeGen、clang 或 gh；项目目录不是 Git 仓库，没有可用 remote；未发现 gh hosts 配置，GH_TOKEN/GITHUB_TOKEN 均未设置（未输出任何凭据）。因此无法在本地编译，也无法向指定远程仓库触发构建。未安装大型依赖、未创建仓库、未 push。Python 静态/合成检查不是 Swift 编译或 XCTest。

在安装 Xcode 的 macOS 上：安装 XcodeGen → `xcodegen generate` → 打开 `WebClipManager.xcodeproj`。系统依赖 libsqlite3/libz 已接入，第三方许可作为资源打包；无需 Ruby 或 SwiftProtobuf 下载。生成过程创建 `Config/Info.plist`。模拟器 XCTest 只使用合成数据。或由用户提供有权限的远程仓库，上传审核源码后手动执行 workflow；当前没有运行，不能报告编译通过。

## TrollStore 签名与权限（未验证）

build5 使用 `Tools/entitlement_policy.py` 中六项有限清单：platform-application、本应用 application-identifier、字符串形式的本应用 container-required、no-sandbox，以及 AppDataContainers/Notes 两项存储权限。选择明确容器而非非容器 HOME；来源、必要性假设和限制见 [build5 候选说明](Docs/BUILD5-CANDIDATE.md)。不申请 root/persona/JIT/debugger/keychain 等额外能力。**声明权限不保证它会生效**；平台身份不等于 root，静态签名通过不等于 TrollStore 安装后启动通过。

工作流始终使用 CODE_SIGNING_ALLOWED=NO 构建，默认仅产出 unsigned ZIP，**不是可直接安装的 IPA**。以后经用户授权手动运行并显式勾选 `sign_for_trollstore`，才安装 Homebrew ldid，将 entitlement 实际写入可执行文件、回读严格核验后打包 IPA；同时保留来源记录及 SHA-256。此路径尚未执行，安装和权限效果未知。不能把 entitlement 文件放进包里就认为已经签名。来源核查、可复现性限制及测试步骤见 [构建与首次测试](Docs/BUILD-AND-TEST.md)。

## 备份格式与边界

顶层：format = WebClipManagerBackup，version = 1，createdAt，entries，results。
每个 entry：directory（原目录名），directories（相对目录列表），files（相对路径 → 原始 Data）。仅记录所选目录，不包括 Safari 共享 cookies/cache/storage、SpringBoard 布局或系统注册状态；因此**不是可恢复整个系统状态的备份**。

单文件最多 64 MiB，Info.plist 最多 2 MiB，图标最多 8 MiB，备份累计原始数据最多 256 MiB；编码时内存占用会更高。超过限制逐项失败，建议分批导出。拒绝符号链接与非普通文件。并发系统写入仍可能让备份前后不一致，未提供文件系统快照或防恶意并发换链保证；请在系统没有新增/删除 WebClip 时操作。图标损坏时显示占位图。

文件导出完成仅表示系统导出器回调成功，逐项“已读取”不等于每项都保存成功；取消/导出失败不改原数据。导出文件包含敏感 URL 与原始内容，选择 iCloud 等目标将由系统同步；请自行选择可信本地目录，不要提交到公开仓库。

## 后续真机验收（尚未执行）

1. 备份少量不敏感测试 WebClip；测试普通/全屏/受管理项目、损坏 plist、拒绝权限和重启后访问。
2. 核对名称、URL、图标、重复组；导出后用 plist 工具逐字节核对原始 Info.plist 与图标。
3. 验证删除入口始终拒绝，原目录和主屏幕图标不变；确认不访问 Safari 共享数据。
4. 若未来开发系统删除，先取得 16.6 对应调用链、签名/服务权限证据，再在可丢弃设备逐项比对主屏幕删除效果；失败不得降级为目录删除，不可把方法返回值等同完整清理成功。

## 许可与隐私

MIT。源码仓库不包含用户书签、URL 列表、ZIP、设备备份或真实图标。测试只在执行时生成虚构内容。`.gitignore` 拒绝常见归档/导出文件；发布前仍应人工检查暂存区。
