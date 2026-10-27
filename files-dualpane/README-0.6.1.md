# Files DualPane 0.6.1

修复桥接确认后误退出双栏且没有报告的问题；不新增采集入口或诊断包。

## 根因与修复

0.6.0 的确认 handler 调用 `[container dismissViewControllerAnimated:completion:]`。UIAlertAction 已由 UIKit 自动关闭确认框，此时继续对呈现容器 dismiss 可能关闭双栏，而 completion 又试图从离开 window 的容器展示分享。同时成功标志在报告生成前写入，失败也消耗次数。

0.6.1 不对容器或确认框主动 dismiss。确认后回到主队列，等确认框的 window 和 presentingViewController 都清空、双栏没有 presentedViewController 或未完成 transition，再验证双栏仍在 window、未关闭，才调用原有只读 snapshot。等待最多 3 秒；失败提示且不消耗次数。闭包在等待和呈现期间强持有容器，报告控制器持有文本；不调用 close 或清理 pane。

报告是独立导航页中的不可编辑文本，分享和复制各有按钮。没有自动写剪贴板，只有用户点击复制时写入；分享的 UIActivityViewController 以分享按钮作为 iPad popover anchor。返回只关闭报告自己的导航容器。成功标志和采集按钮禁用发生在报告完成呈现且仍附着 window 后。失败保持左右目录、选择及布局，可重试。

只沿用既有匿名类/selector/签名、关系 ID、URL 对象存在性布尔值；schema 保留 0.6.0 表示采集格式没有变化。不读文件内容，不增加路径采集，不自动联网或落盘。0.6 的默认并排、列表、22pt 图标、原生操作和 QuickLook 不变。

## 验证

- `python3 tests/check_061.py`：修复前在容器 dismiss 断言失败，修复后通过；限制为源码契约检查。
- CI 把生产 `FPBridgeAfterAlert` 函数直接嵌入 Foundation 宿主测试，执行确认框仍在 window、关系尚未解绑、transition 未完成、成功呈现才消耗、失败后重试、异常、脱离 window、超时及异步强引用生命周期用例。UIKit 替身不是设备实测。
- 原有双栏、操作、0.6 契约检查及生产 preview/state 宿主测试继续运行。
- CI 编译 arm64 / arm64e RootHide deb，验证版本、双架构及嵌入 CodeDirectory 各代码页哈希。

未再运行用户采集，未新增诊断包，未声称真机测试。该次 UI 失败不计为有效报告。
