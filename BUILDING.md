# 构建与验收规范

## 环境

- macOS、Xcode（包含 iPhoneOS SDK）、Python 3、Swift 编译器及 Xcode 命令行工具。
- 工作流使用 GitHub 托管 `macos-15`；不得改为带个人数据的 self-hosted runner。
- 只使用 runner 已安装的 iPhone simulator runtime；缺失时失败关闭，不自动下载 runtime。
- 不依赖 CocoaPods、第三方 Python 包、签名证书、Apple 账号或仓库 secrets。
- `LinkCard.xcodeproj` 和共享 `LinkCard` scheme 已包含 app、unit 和 UI test targets。当前版本为 0.8.6，build 为 25。

## 结构及 Reference 测试

```sh
python3 Tools/validate_project.py
python3 -m unittest discover -s Reference -v
```

Python 测试覆盖编码参考模型、安全约束、UI 源码契约及公开结果 schema。AX 参考模型使用独立构造的合成矩形，不依赖诊断采样。它们不代替真实 Swift/XCTest 执行。

## 完整 Release 流程

只在干净、没有个人数据的环境中运行：

```sh
bash Tools/build_ipa.sh
python3 Tools/require_ui_gates.py
```

构建器顺序执行 host Swift 协议与会话检查、iPhoneOS Release 构建、ad-hoc 签名/打包、真实 native unit 测试和完整四项 fullApp UI 测试，最后执行严格 gate。

- unit 必须为 `passed`。
- fullApp 必须为 `passed`，scope 必须是 `fullApp`。
- 计数必须精确为 `passedTests=4, failedTests=0, skippedTests=0, totalTestCount=4`。
- 不接受 sidebar-only、缺结果、超时、跳过或用 Reference 模型代替 UI。
- 保留默认动画/quiescence、真实 frame 中心触摸、真实滑块拖动、值变化及恢复断言。新增纵拖、选图取消、偏好隔离与重启检查合并在原四项内；suite 上限为 1200 秒，单次触摸响应上限仍为 15 秒。
- NFC 测试仅打开确认再取消，不发送；保留无设备读取禁用断言。

IPA 可能先在构建目录生成；这不等于可交付。工作流严格 gate 在上传前执行；失败不能上传 IPA。最终还须检查 workflow `completed / success`、本次源码版本以及 IPA 内 bundle、版本、架构和 SHA-256。自动测试不构成硬件兼容性保证。

## 协议安全约束

生产协议保持不变。ST25DV 识别综合 UID 产品字段与容量，使用 CoreNFC 的实际块数和 4 字节块长；不能确定时不强行定型。动态邮箱只写 MB_EN 控制值，不把状态快照回写，不清空已占用邮箱，操作后读回验证。BLE 型号与适配器检查不能由显示名称绕过；未知协议不发送试探命令。授权范围与设备安全由使用者负责。

## 公开 CI 与结果策略

`.github/workflows/build-ipa.yml` 仅 `workflow_dispatch`，只授予 `contents: read`；checkout 不持久保存凭据，Action 固定到完整提交 SHA。不使用 secrets、缓存、第三方服务、自动 release 或 repository 写权限。

仅上传四个精确路径，保留 7 天：

1. `build/export/LinkCard-TrollStore.ipa`
2. `build/export/LinkCard-TrollStore.ipa.sha256`
3. `build/public/result.json`
4. `build/public/build.log`

前两项仅在构建与严格 gate 成功后上传。后两项由 `Tools/public_build_result.py` 重新生成，只允许固定状态枚举和有界测试计数；`build.log` 另外只含固定编译分类枚举（不含原始错误、符号、源码位置或诊断行）。不复制原始错误字符串、路径、模拟器 UDID 或环境变量。报告的 `artifact_upload=not-attested` 表示它不是上传成功证明；最终状态以 Actions 页面为准。

原始构建日志、xcresult、截图、AX 树、系统日志、附件、dSYM 和 simulator inventory 均不上传。源码测试以默认 UI、生成纹理及程序化数据为输入；截图与 AX 附件仍可能反映运行环境，不能无条件宣称它们永远只是合成内容。因此初版不公开任何测试附件，也不将其作为 IPA 通过证明的替代品。失败时仅有受限阶段/状态信息，若需更多诊断须单独审查后调整。

## 仓库设置

将本目录作为全新仓库的文件根，启用 Actions 并允许本工作流固定的 GitHub 官方 checkout/upload-artifact Action，默认 workflow permissions 使用只读，禁止 Actions 创建/批准 PR。不添加 secrets、个人文件、额外 Actions 或大范围上传路径。手动执行工作流前仍须单独获得构建授权。
