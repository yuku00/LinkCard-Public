# LinkCard 0.8.6 · build 25

LinkCard 是使用 SwiftUI、UIKit、CoreNFC 与 CoreBluetooth 的 iOS 应用，用于卡片内容排版、预览、本地管理及受支持设备的连接。应用最低部署目标为 iOS 16。

本目录提供应用源码、原创几何图标、Xcode 工程与共享 scheme、真实单元/UI 测试，以及构建所需的 Reference 和 Tools。没有附带开发者证书、描述文件或第三方 SDK 二进制。

## 快速检查

```sh
python3 Tools/validate_project.py
python3 -m unittest discover -s Reference -v
```

以上仅验证结构、参考模型及源码契约，不代表 Swift 编译、真实 UI 或硬件验证通过。

## 构建

完整步骤、运行条件、严格验收条件与公开产物范围见 [BUILDING.md](BUILDING.md)。GitHub Actions 仅允许手动 `workflow_dispatch`；不会在 push 或 pull request 时自动构建。

Release IPA 采用 ad-hoc 签名，不使用开发者证书或仓库 secrets。ad-hoc 签名不等于 Apple provisioning、正常签名分发或 CoreNFC 授权，也不保证 TrollStore 安装与真实设备兼容性。

## 验收状态

这个源码包不是成功构建证明。只有完整工作流成功、native unit 通过、四项 fullApp 全部通过且零失败/零跳过、严格 gate 通过，才可称为该次 CI 验证通过。没有运行的测试必须记为未运行。模拟器验证不能替代真实设备验收。

## 许可与来源

代码采用 GPL-3.0-or-later，见 [COPYING](COPYING)。公开协议参考、第三方归属及分发边界见 [NOTICE.md](NOTICE.md)。分发修改版或二进制时请履行 GPL 对应源码与说明义务。
