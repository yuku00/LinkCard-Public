# 公众号单图 → 微信原生表情编辑

## 真实入口与范围

在已有「微信整合」设置启用总开关及「公众号单图 → 表情编辑（手动确认）」。默认关闭。生产 `Core.m` 安装 `WKWebView.layoutSubviews` 公开生命周期桥；非文章仅检查原生 URL，不运行脚本、扫描页面或读取图片。仅当前导航顶层、已在微信打开、URL 为 HTTPS `mp.weixin.qq.com/s` 或 `/s/...` 的 WKWebView 才安装局部被动长按观察器。

1. 用户实际长按命中已加载 IMG，固定脚本通过单次 `elementFromPoint` 取该图 `currentSrc`，不枚举页面图片。
2. 优先用现有 `UIContextMenuInteraction.updateVisibleMenuWithBlock` 追加动作，原 children 原对象保留。不替换 delegate、不吞原手势、不关闭原菜单。没有可更新的公开菜单时，在原导航按钮数组后追加 12 秒「所选图→表情」按钮，只移除自己的按钮。
3. 点明确动作后展示文章/图片地址来源；再次确认才读取数据或建立临时请求。请求中有独立「取消所选图」按钮。
4. 显示所选静图预览；用户再确认后重验 DOM，复用 `WUImageEntry.m` 原有 `EmoticonPickViewController init → setM_image: → push` 链。
5. 微信原生 UI 负责确认/取消。打开编辑器不代表表情入库完成；插件无后台上传/发送、无自造 delegate、无成功回执。

## 身份、隐私与拒绝边界

- 固定代码在命名 WKContentWorld 内执行；无 WKScriptMessageHandler。页面消息不能建立原生手势令牌或触发读取。
- 绑定真实手势、WKWebView 对象、文章 URL、账号、generation、当前 IMG 对象/currentSrc、时间、DOM 文档/timeOrigin、图像 rect、滚动与视口。原生 URL/loading/几何 KVO 与脚本局部滚动/加载/变更观察器使变化不可逆地失效；滚走再返回也不能复用旧选择。
- 只支持能逐项核验的未缩放布局：native/visualViewport 尺寸和滚动一致、缩放为1、零 adjusted/content inset、无原生/DOM 变换，DOM 祖先最多64级。iframe、shadow DOM、blob、未知布局不猜；这些情况下入口可能不出现。
- 内嵌 PNG/JPEG data URL 在用户确认后读取原始字节。公开 WebKit 无可核验的原始 HTTP 图片缓存字节接口，因此远程 src 不走 canvas，不把动画静默转成首帧；只能在用户明确确认后请求绑定地址。重新请求的结果可能不是页面缓存或原图，文案明确告知。
- 请求仅允许 HTTPS、默认端口或443、无 URL user/password，精确主机 `mmbiz.qpic.cn`、`mmbiz.qlogo.cn` 或文章同源 `mp.weixin.qq.com`；其他域名/端口/协议、图片 fragment 拒绝。最多2次白名单内重定向，每次重建干净 GET。
- ephemeral URLSession；Cookie storage、credential storage、cache 全为 nil；不携带 Cookie、Authorization、Referer、账号头或 request body；认证挑战除系统标准 server-trust 校验外全部拒绝。无第三方解析/AI服务，无登录、付费权限绕过。
- 只接受200及 PNG/JPEG MIME；不接受压缩 Content-Encoding；声明长度与流式累计均受20MiB限制，单请求8秒/总时长15秒；取消后丢弃晚到回调，无额外任务重试。
- 复用现有 WUEmoticonType/StaticImage 完整字节、CRC/格式、帧数、像素上限和解码校验。GIF/APNG/多帧明确拒绝，没有「动画添加成功」冒充。
- 停用、后台、换号、generation变化、离页清除自己的工具、回调、数据和精确拥有的编辑控制器；不 pop 其他页面，不更改原图，不记录 URL/内容日志。非聊天 owner 不调用 WUChatSession，也不读取聊天选择。

## 文件与集成

新增 `Sources/WUArticleImage.{h,m}`、`WUArticleImageDOM.inc`、`WUArticleImageFetch.{h,m}`。`WUImageEntry.{h,m}` 只增加已确认数据入口和来源守卫，并共用原有编辑/校验/取消实现。原聊天单图测试文件不改。

`Core.m`、`Settings.m`、`tools/build.sh`、`tools/release.py` 已给出精确接线补丁。旧全局 NSURLSession blanket 断言只对 `WUArticleImageFetch.{h,m}` 豁免，其他模块仍禁网；新测试明确约束用户确认、请求目的与零凭据。

## 验证与真实剩余

本隔离环境可运行 Python 结构测试与 Node 合成 DOM：文章结构8项、既有聊天单图结构8项、全局结构29项；固定生产 JS 67项合成断言。它们不是 WebKit/真机证明。

已提供、需 Apple CI 实际运行：

- `python3 tests/test_image_entry_native.py`：原聊天套件不变。
- `python3 tests/test_article_image_native.py`：真实 Foundation NSURLProtocol 全拦截合成网络测试、真实 ImageIO/现有 UIKit hostmock 下共享编辑路径及六种签名模式。
- `python3 tools/test_article_image_ios.py NEW_RESULT_DIRECTORY`：复用既有 unsigned UIKit XCTest 宿主，8项 UIKit 测试，手势/URL/JS回复均合成，不加载用户网页；逐项核验 xcresult，不用退出码或测试计数冒充全部通过。只使用已安装模拟器，不安装依赖/SDK。

当前无 xcrun/Apple SDK：以上 Apple 编译和运行均 **NOT RUN**。仅验证了生成的工程结构，不能声称 Apple CI 通过。目标微信、真实文章、原菜单交互和入库结果均未验收。公开 API 路线不依赖未知原菜单 delegate，但真实微信是否暴露符合上述零 inset/未缩放条件的 WKWebView、可见公开菜单更新时机及原生编辑器签名，仍须目标机验证；条件不满足时拒绝，不宣称覆盖所有公众号/微信70以上版本。

未启用 Photos、旧库、用户内容下载/上传、AI、Dock、伪点赞、红包详情、在线主题或视频解析。源码发布脚本只补白名单，本批未执行上传或触发 CI。
