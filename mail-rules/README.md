# Mail Probe 0.1.0 — 只读接口探针

适用：iOS 16.6 **20G75**、RootHide、Mail bundle `com.apple.mobilemail`；包架构 `iphoneos-arm64e`，dylib 同时包含 arm64/arm64e。运行时通过 `kern.osversion` 精确校验 20G75；其他 build 不激活。此包不实现过滤、建邮箱或移动功能。

## 最短操作
1. 用 RootHide 包管理器安装 `dev.mailrules.probe_0.1.0_iphoneos-arm64e.deb`，从任务切换器结束 Mail 后重开。
2. 在普通主收件箱找到左下方的小条「采集 0/8 / 报告」。它距安全区底部 56pt，不替换或 hook 发信按钮；会覆盖少量列表内容。
3. 点「采集」，等数字更新。可在原有更多菜单出现时再点一次；取消菜单后再点一次。每次都是用户显式采样，最多8阶段，合在同一报告。菜单挡住按钮时不需强行操作；取消后采集即可，并注明菜单阶段缺失。
4. 点「报告」→「查看 / 分享报告」→右上分享。报告是内存里的 JSON 文本，由系统分享面板交给你选择的目的地；探针不自动保存/上传。可点「清空内存报告」开始新流程；退出 Mail 丢弃内存报告。

不必打开任何私人正文。会话/预览控制器只有已经自然加载在 UIKit 树里才会记录；未加载的目标类标记 missing，不主动打开正文、展开线程或执行菜单动作。若系统菜单在另一个 window，其对象不采集，也不会遍历其他窗口来追踪它。

## 采集内容
- 当前主屏前台 key normal window 的 UIKit 对象关系：root/child/presented/parent controller、已加载 view、subview、nextResponder、公开 table/collection datasource/delegate/layout、interaction。
- 对象只给会话内匿名 `o1` 等 ID 和运行时类名，不输出对象地址、description 或属性值；可通过 collection→dataSource 与 nextResponder/控制器树定位实际主列表所属实例，不以私有 mailbox 值断言其为收件箱。
- 定向 EMMessage、EMMessageListItem、EMConversation、EMMessageList、发件人 predicate、mailbox/create/change/transfer/repository/undo、账号能力声明及 future/scheduler/operation 候选。
- 只按 Mail delegate、EMMessage、ECEmailAddress、EFFuture 锚点所在的最多4个已加载 image 枚举类名，按 Message/Mailbox/Conversation/Thread/Query/Repository/Selection/Action/Operation/Predicate/Future/Promise/Scheduler/Queue/Permission/Capability 定向扩展；不扫描全进程 class list、不加载私有 framework。每次显式采样在串行后台队列重建元数据，以补足后加载的类。
- 所有命中的类及完整父类链的实例/类方法 selector、原始 type encoding、返回类型和含 self/_cmd 的参数编码、实例/类 property attributes。
- 协议完整继承及 required/optional × instance/class 方法与属性；每类/协议每份报告只出现一次。不截断关键类方法。类别方法在运行时已经合并，无法由 runtime 恢复原 category 出处。Swift-only 声明不在此能力范围内。
- 图上限：1800已处理节点、深度24、6000边/排队项；报告含 visited/pending/depthBoundaryNodes/edgeLimitHit/graphTruncated。接口元数据不做方法数/字符串长度截断，有 classCount/protocolCount/imageDiscovery/missing。总JSON大小由系统实际类声明决定，报告可能较长。

## 明确不采集、不执行
不读取账号实例、邮箱地址、发件人姓名、主题、正文、附件、URL、token、密码或用户文件名；声明里出现 `senderAddress`、`subject` 等 selector/属性名称并不是其值。没有私有 getter 调用、KVC、ivar读取、Swift offset、私有方法 hook、原生 action 执行、数据库写入、网络代码、自动上传、定时器、后台持续追踪、持久日志或设置偏好。启动观察器只负责安装小入口，不触发采集。

报告只证明声明和公开 UIKit 关系。`@` 不能证明 sender 接受的具体类型，`@?` 不能恢复 block 参数签名；createMailbox 的 parent/root/权限语义、线程展开行为、repository/selection/query 的真实私有实例归属、native queue 完成/逐封失败与服务器结果仍需下一步证据。此包从未为验证签名调用建文件夹或移动操作。

## 验证与卸载
本工程有静态隐私/范围检查及 macOS 上执行真实 Metadata.m 的 fixture：精确 build 门禁、完整父类、协议继承、可选类方法、block ABI与JSON序列化；fixture 的 getter/action 一旦被调用会 abort。CI编译UIKit入口及两架构，验证真实deb字段和 Mach-O slices。主机测试/编译通过不等于真机注入、按钮可点击、菜单层级或 Mail 20G75 兼容性已经验证。

在包管理器卸载 **Mail Probe / dev.mailrules.probe**，结束并重开 Mail。包 payload 只应有 `MailProbe.dylib` 与 `MailProbe.plist`；无 prefs、守护进程或安装脚本。RootHide前缀由包管理器管理，不手动删除整个注入目录。用户主动分享到外面的报告需自行删除。卸载不会更改邮件数据。

公开仓库只提交本工程明确白名单的源码、测试、说明、构建配置及独立workflow；不上传 research/public-headers dumps、设备报告、凭据或其他并行工程。
