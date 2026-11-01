# 手动构建、签名与首次测试

已获得开始编译授权，但本机缺少 Swift、Xcode、XcodeGen、clang、gh。实际调用 `xcodebuild -project WebClipManager.xcodeproj -scheme WebClipManager -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 返回 `/bin/sh: xcodebuild: not found`（退出码 127），并未进入编译。工程尚需 XcodeGen 生成。目录没有 .git/remote，未发现 gh hosts 配置及 GH_TOKEN/GITHUB_TOKEN 环境变量，无法确认远程认证或触发 Actions。没有安装依赖、创建仓库、上传、发布或安装应用。

本机 `python3 Tools/static_check.py` 与 `python3 Tools/test_notes_format.py` 均 PASS；后者只运行合成 gzip/protobuf、从 Swift 源码提取的 SELECT 和只读 WAL backup，不能代替 Swift/XCTest。新增 XCTest 未运行，尚无 IPA。

继续构建需要 macOS/Xcode 环境，或用户提供有权限的远程仓库和安全认证。禁止自动创建公开仓库。系统 SQLite/zlib、第三方许可资源、模拟器 XCTest 与结果归档已接入 workflow。

## 构建流程

`.github/workflows/build.yml` 只响应 `workflow_dispatch`，仅 `contents: read`，不发布 Release。

- 默认 `sign_for_trollstore=false`：安装 XcodeGen、生成工程、运行合成 XCTest、构建设备 App、上传未签名 ZIP（不可直接安装）。
- 用户后续授权运行并选择 `true`：另外通过 Homebrew 安装 `ldid`，记录 `brew info --json=v2 ldid`，对主可执行文件写入 `Config/TrollStore.entitlements`，用 `ldid -e` 回读并逐项严格比较，随后打包 `Payload/WebClipManager.app` 为 IPA，生成 SHA-256。签名或核验失败会停止；不会降级成假成功 IPA。
- 构建产物保留 7 天。无 P12/Apple 开发者凭证、不请求发布写权限。当前目标没有扩展或额外动态 framework；未来添加它们必须单独审核嵌套签名流程。

## ldid 来源与限制

核查了 [opa334/ldid](https://github.com/opa334/ldid)（TrollStore 作者维护的 fork）、[Homebrew 核心 ldid 配方](https://github.com/Homebrew/homebrew-core/blob/master/Formula/l/ldid.rb) 以及 [TrollStore README](https://github.com/opa334/TrollStore)。本轮没有下载 ldid 二进制。

当前 Homebrew 配方指向 saurik ldid v2.1.5，固定源码 revision `a23f0faadd29ec00a6b7fb2498c3d15af15a7100` 并列有 bottle SHA-256；并非 opa334 fork，不能混称。本工作流使用 Homebrew 的校验与分发链，不从第三方网盘获取签名工具。Homebrew 配方和 Actions 的 major tags 会变化，不是完全可复现供应链；公开发布前需审核当时配方，按需求固定 Actions commit、Xcode/XcodeGen 及 ldid 来源版本。runner 若无适合的 bottle 可能从源构建，耗时/大小未承诺。本地大工具安装仍需用户确认；这里不执行。

TrollStore README 说明可以用 `ldid -S<entitlements> <binary>` 伪签并在安装时保留 entitlement；`com.apple.private.security.no-sandbox=true` 列为解除沙盒的候选权限之一。项目仅保留这一项，不申请 root/platform/keychain 等无关权限。签名回读成功不等于系统授予目录访问权，也不等于安装成功。普通开发者签名无法代替 TrollStore 权限路径。

## 首次测试清单（先只读，再逐步验证）

1. 在 macOS / 后续授权的 GitHub Actions 完成首次编译与合成 XCTest；如果失败先修复编译，不直接声称可安装。保存构建日志和 ldid 来源记录。
2. 检查 IPA 结构、SHA-256 与回读 entitlement；仅在兼容 iOS 16.6 的测试设备上用 TrollStore 安装。若启动失败，记录系统版本、安装器版本与脱敏崩溃信息；不追加高权限试错。
3. 首先进入书签页「诊断」：刷新接口诊断，查看 WebClips `notRead/reading/readable/partial/failed` 状态，导出 JSON。检查 JSON 没有 URL、标题、UUID、设备标识或原始错误。只分享这个诊断文件，不分享书签备份。
4. 使用少量不敏感测试 WebClip，验证普通/全屏、完全相同 URL 重复组、搜索、多选与隐藏项计数；筛选无结果与读取失败应不同。检查深浅色、大字体、VoiceOver、横屏与 iPad 布局。
5. 导出少量书签备份并核对原始内容。点击删除仅应返回「未删除」，主屏幕、目录和 Safari 数据不能改变。接口存在仅是后续研发线索，不能启用真实删除。
6. 自建 UTF-8 TXT/MD：含中文、emoji、多行、空文件、同名文件。到备忘录 Tab 批量导入，搜索、多选、分别导出 TXT/MD；核对正文换行与文件名。Markdown 保留原始标记；不会自动格式转换。测试超过限制、非法编码、取消选择和取消导出。禁止以真实 Notes 库或用户归档作为初次测试素材。
7. 编译和合成测试通过后，在可丢弃 iOS 16.6 测试设备创建无敏感数据的 Apple Notes：中文/emoji/多行/空正文、锁定笔记、图片与表格、删除项目。点击只读读取，核对正文、跳过计数、占位符、权限拒绝和内存清除；不要使用用户日常 Notes 数据库进行首次测试。检查读取前后原笔记内容未变，附件/表格不应被描述为完整导出。
8. 保存位置尽量选可信本地目录。确认导出器多文件命名/数量、沙盒授权文件提供者行为、批次重选与后台恢复；它们尚无真机证据。

**下一步需要测试。** 顺序是首次 Swift 编译与合成测试 → TrollStore 安装/权限诊断 → 小规模无敏感数据导入导出。没有必要先读取真实备忘录或尝试删除。
