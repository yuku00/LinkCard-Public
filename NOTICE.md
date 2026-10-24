# 来源、许可与独立实现声明

Swift/Python 代码采用 **GPL-3.0-or-later**，完整 GPL v3 文本见 `COPYING`。这是独立编写的 iOS 实现，不包含 APK Java/DEX、ST Android SDK 或固件原件的复制与重打包。再分发本项目及修改版时，应保留版权、来源及许可说明，并按 GPL 提供对应源码。第三方材料的原有权利归原作者。本声明不构成硬件适配、RF 可靠性或安全保证。

## 公开协议参考及归属

- 稚晖君 / peng-zhihui 的 L-ink_Card：<https://github.com/peng-zhihui/L-ink_Card>。
- 参考版本：`0c85ae1c0b84ec33eb17310229f5dc66ff0d4092`。
- 该项目公开的 `Android/L-ink_V0.2.apk`，SHA-256：`00ab6660b0c022da55a47e7029f15d6089c17d88f07886589eb2bb36654aa415`。仅作为协议参考；不随本项目分发。
- 明明 / `dz_DIY_mingming` 的公开项目：<https://oshwhub.com/dz_DIY_mingming/link_upgrade>，页面声明 GPL 3.0；公开发布 HEX，不表示本项目取得其完整固件源码。
- 该公开 HEX 的 SHA-256：`4d97805c23a9b40bb1bf607eab5b828462a29f05aa2ffbc0b97e8cb40a0fb8a3`。仅作为协议参考；不随本项目分发。
- STMicroelectronics ST25 Android SDK API 语义用于协议核对；本项目没有附带该 SDK。当前安全约束见 `BUILDING.md`。

## 平台 API

- <https://developer.apple.com/documentation/corenfc/nfciso15693tag>
- <https://developer.apple.com/documentation/corenfc/nfciso15693tag/customcommand(requestflags:customcommandcode:customrequestparameters:completionhandler:)>
- <https://github.com/opa334/TrollStore#entitlements>

Apple 框架由目标平台提供。二维码采用 Core Image；抖动采用独立 Floyd–Steinberg 实现。App 图标为项目生成的原创几何图形。GPL v3 官方文本：<https://www.gnu.org/licenses/gpl-3.0.txt>。

## 本源码分发中的调整

公开构建说明、工作流及受限结果导出策略经过整理；AX 参考模型改用独立合成几何数据，真实 UI 测试仅泛化说明性注释。应用生产代码、项目版本、单元测试及严格 fullApp 验收要求保持不变。本声明不表示已完成编译或设备验收。
