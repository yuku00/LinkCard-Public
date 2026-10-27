# 安装文件、卸载与升级

## 所有安装载荷（路径相对 RootHide 虚拟根）
- `/Library/MobileSubstrate/DynamicLibraries/FireflyLite.dylib`
- `/Library/MobileSubstrate/DynamicLibraries/FireflyLite.plist`
- `/Library/PreferenceBundles/FireflyLitePrefs.bundle/`，内含设置可执行文件及 Info.plist；如 Theos 生成签名元数据，也由包追踪。
- `/Library/PreferenceLoader/Preferences/FireflyLite.plist`
- `/usr/libexec/firefly-lite-cleanup`
- dpkg 控制元数据及 `prerm`（非额外守护进程）。

实际最终清单必须在成功构建后用 `dpkg-deb -c` 检查；目前没有 deb，因此以上是预期载荷，不是假造的已安装列表。工具链/RootHide 自动生成的 `.jbroot` 链接由平台管理。

## 运行产生的状态
只有 mobile 用户 `dev.fireflylite.badgeglow` 的 CFPreferences 域：Enabled、Red、Green、Blue、Intensity。通常对应 mobile 的 Library/Preferences 下同名 plist，但 RootHide/cfprefsd 实际映射必须以设备为准；源码不猜其磁盘位置。核心只读偏好，设置页只在用户修改时写。

无本插件日志、缓存、数据库、下载文件、后台服务、LaunchDaemon、网络请求、遥测、root 用户偏好或其他插件偏好。Apple 系统自身的日志/缓存不属于本包承诺的清理范围。

## 实际清理机制
1. 普通卸载和已安装状态的 purge 都先经过 dpkg `prerm remove`。
2. 仅 `prerm` 恰好一个参数 `remove` 才调用清理工具。upgrade、failed-upgrade、deconfigure、remove in-favour 均不清偏好。
3. 帮助工具解析系统 mobile 账户；root 调用时 initgroups/setgid/setuid 降权。身份不符立即失败，绝不清 root/其他用户域。
4. 发送独立 Darwin uninstall 通知。已加载核心在主线程永久停止，移除所有自有图层和 Darwin observer；已打开的设置控制器停止写入、禁用交互并移除 observer。
5. 等待 300ms 尽力让通知执行，使用相同 CFPreferences CurrentUser/AnyHost 域删除本域全部键并同步，再验证本进程看到的键列表为空。无 killall cfprefsd、无 rm 通配、无随机 jbroot 猜测。
6. 清理失败仅向包管理器 stderr 给出警告，不阻塞卸载。其余安装载荷由 dpkg 删除。

## 必须诚实保留的限制
- Darwin 通知不是确认应答。Settings/SpringBoard 若暂停、卡住或没有收到通知，300ms 不保证停止完成；卸载前关闭设置页面可减少晚到写入竞争。
- CFPreferences 同步清空域，优于直接删文件而不清缓存，但**尚未证明本设备 cfprefsd 会删除空 plist，也不能保证暂停中的写入者不会重建偏好**。因此不承诺“100% 无残留”。不通过猜物理路径 unlink 或杀全局 cfprefsd 掩盖问题。
- 若普通 remove 清理失败，之后在仅残留 dpkg 配置状态执行 purge，帮助工具已被移除，无法自动重试。应在卸载前先执行清理工具，或重新安装此独立包后重试；没有 postrm 隐藏下载/复制常驻清理器。
- 卸载通知无法从已注入进程卸载 dylib 的机器码及 hook。收到通知后的 hook 只保留调用原实现/移除本包图层的无效果路径；完全清理内存需当前环境支持的 SpringBoard 重启或设备重启。工程没有自动 shell respring。
- 通知“永久停止”之后重装，需要重启相关进程才能加载新库；不要把仍驻留旧库的进程作为重装成功证据。

## 真机卸载验证（尚未执行）
1. 先确认 SpringBoard 注入和恢复/安全模式可用；保存当前已知可用环境。
2. 安装、启用、改变颜色强度，记录设置值；退出 Settings。
3. 用包管理器升级同包 ID 的较高版本；确认三项值保留且 `prerm upgrade` 不清理。
4. 开启一个有角标应用和一个无角标应用；普通卸载，确认已加载核心停止发光；查看清理警告。
5. 用平台可信偏好工具以 mobile 身份检查本域键为空；核对实际映射位置是否仍有空 plist。不能用 root 的 defaults 结果代表 mobile。
6. `dpkg -L dev.fireflylite.badgeglow`/包管理器确认无该包载荷；核对设置入口消失；确认其他插件偏好不变。
7. 通过环境提供的安全方式重启相关进程/设备，确认图层/注入代码不再在内存。没有自动执行这一步。
8. 再安装，应默认关闭、默认蓝色、强度 65%；否则清理验收失败。覆盖 Settings 打开/关闭、SpringBoard 暂停、帮助工具失败、直接 purge、先 remove 再 purge 等情形。

## 已执行的主机测试
`python3 tests/check.py` 用临时假帮助工具执行真实 prerm 分支；已通过 remove、upgrade、failed-upgrade、remove in-favour、deconfigure、无参数六种情况；帮助工具返回失败也不阻止卸载。它只验证脚本控制流，不能代替 dpkg 真机安装、mobile 身份或 cfprefsd 行为测试。
