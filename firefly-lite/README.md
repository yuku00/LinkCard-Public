# Firefly Lite / 萤光·精简版

独立重写的 RootHide Theos 源码项目，目标 iOS 16.6。MIT。包 ID 与偏好域均为 `dev.fireflylite.badgeglow`，不复用旧插件授权、二进制、包 ID、设置或颜色依赖。

**状态：已通过 GitHub Actions macOS 构建，产出真实 RootHide deb；主机测试与 Apple Foundation 断言通过。未真机验证。完整 iOS16.6 类头核验仍是缺口，见 docs/API-EVIDENCE.md。**

首次成功构建：[Actions #40444208442](https://github.com/yuku00/LinkCard-Public/actions/runs/40444208442)。编译成功不代表 SpringBoard 注入、偏好清理或真机稳定性通过。

## 功能与设计
- 应用角标为正数或非空非零文本时显示柔和静态光晕；无角标立即移除。不是独立读取通知中心，关闭角标的通知不触发。
- 总开关、RGB 颜色、0–100% 强度；首次安装默认关闭，默认蓝色，65% 强度。
- 中文原生 UIKit inset-grouped 设置，系统深浅色、Dynamic Type、VoiceOver 标签，系统 `UIColorPickerViewController`，不依赖 libCSColorPicker/Cephei。
- 不提供 SpotOn、复杂动画、文件夹单独效果、网络、遥测、下载或 shell respring。
- 每个可见图标最多一个自有 CALayer；重用更新，离屏、失去角标、强度零、关闭或卸载时移除。弱引用集合，不持有图标视图生命周期；不修改系统图标图层的 shadow 属性。
- UI 更新串行到主线程；CATransaction 禁用隐式动画。超范围、非数、错误类型参数回退/截断。
- CFPreferences 两端固定 CurrentUser + AnyHost；Darwin 通知刷新；不用直接 plist 读写混杂缓存。
- 标准 RootHide scheme；bundle 名相对查找，无绝对资源路径；不复制旧库、不破解授权。
- 私有接口检查不通过则不注入 hook，而非继续赌签名。检查通过仍不代表已验证 iOS16.6 行为。

## 构建环境
需要支持 RootHide 的 Theos、Xcode/iPhoneOS SDK、make、ldid 和 dpkg。仓库的 `Firefly Lite RootHide` 工作流可手动触发，在标准 macOS runner 上执行测试并构建；成功时上传真实 deb 和 SHA256SUMS。

SpringBoard 注入环境和 iOS16.6 真机验证仍需单独确认；Bootstrap App List 本身不等于 SpringBoard 注入。

## 在已有 Mac/Xcode 上构建
先确认 Xcode command-line tools 可用、许可已接受、SDK 已合法安装；按 RootHide 官方文档安装/更新 roothide/theos（先查看仓库/子模块体积，不执行未经审阅的 curl 管道脚本）。

```sh
export THEOS="$HOME/theos"  # 必须是支持 roothide scheme 的分支
xcrun --sdk iphoneos --show-sdk-path
# 将合法 SDK 配置到该 Theos 版本支持的 SDK 路径；不要复制旧插件 dylib。
cd firefly-lite
python3 tests/check.py
make clean
make package FINALPACKAGE=1
```

Makefile 已固定 `roothide`、`ARCHS=arm64 arm64e`、deployment target 16.0；不要改成 rootless，不要手动伪装 control 架构。若现代 arm64e、Preferences 私有 stub、substrate/RootHide stub 或签名工具不齐，先补官方开发组件，不要删除链接依赖规避。

构建成功后核查：
```sh
dpkg-deb -I packages/*.deb
dpkg-deb -c packages/*.deb
# 在临时目录解包后，以 otool -L 检查全部 Mach-O；应为系统框架及
# RootHide scheme 生成的相对 loader 路径，不应有 libCSColorPicker 或固定 /var/jb。
```
包不应包含网络工具、postinst respring、旧插件 dylib 或未知维护脚本。准确安装清单以实际 deb 为准。

## 安装、验证、回滚
1. 备份现有环境/可用包，确认设备已具备受支持的 SpringBoard 注入及恢复/安全模式能力；不要为本项目擅装未知注入方案。
2. 通过 Sileo/Zebra 打开真实构建出的 RootHide deb，正常解析 RootHide 兼容的 mobilesubstrate/PreferenceLoader 依赖，不强装、不再用 Patcher 转换这个原生 scheme 包。
3. 按现有环境的官方方式重新加载相关进程。设置 → 萤光·精简版，先确认颜色选择器正常，再手动启用。无效果可能是接口门控或没有 SpringBoard 注入，不代表需反复重启。
4. 验证：正角标→光晕；清角标→消失；开关/颜色/0%/100% 即时更新；滚动换页、Dock、图标移动、应用卸载、文件夹内图标复用；深浅色/横竖屏/VoiceOver/大字；确认父图层裁剪没有截断光晕。全项目前均未实测。
5. 回滚：在包管理器卸载 `dev.fireflylite.badgeglow`；本包普通 remove 会尝试清理自身偏好。旧插件没有被覆盖，无需迁移其设置。不用删除随机 jbroot。
6. 若桌面异常，使用已有注入环境的安全模式/禁用本包入口，再卸载；完全移除进程内代码需环境支持的 SpringBoard 重启或设备重启。项目不执行 shell respring。

详见 [卸载范围与验收](docs/UNINSTALL.md)。**未证明空 plist 一定被 cfprefsd 删除、也未证明停止通知无竞争，不能承诺“100% 干净”。**

## 测试
```sh
python3 tests/check.py
```
已执行：plist 解析、schema/依赖/禁止 API 静态检查、11 个直接编译执行的纯 C 断言、6 个 prerm 生命周期分支、清理失败不阻断卸载。
已在 CI 完成：Objective-C/Objective-C++ 编译、链接、签名、RootHide 打包、包 ID/架构与文件清单检查。
未执行：原生设置运行、SpringBoard hooks、CFPreferences 跨进程、实际 dpkg 安装/卸载、视觉效果、功耗与性能。

Apple 环境在临时目录编译 `tests/apple-logic.m` + `Shared/FLPreferences.m`，链接 Foundation/CoreFoundation；12 个角标类型断言已在 CI 通过（不写偏好）。它不能代替设备验收。

没有 HTML 截图冒充原生预览；本包暂不附虚假的 UI 实测图。
