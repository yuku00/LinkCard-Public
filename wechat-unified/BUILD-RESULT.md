# 2026-11-01 语音转述两项集成：CI及产物取回完成

- commit `2792943d0804532a3be98d9c11f4ebe9c9a00525`；[CI41308827848](https://github.com/yuku00/LinkCard-Public/actions/runs/41308827848) completed/success，job124854742400。前代理在结果核验阶段中断，主会话直接接管取回，无重复发布或代码改动。
- 生产转述模块+Core Hook原生UIKit mock正常86/86、错误ABI4/4、冲突8/8通过；配置保存32检查、31项统计XCTest及原回归通过；iOS arm64编译、严格codesign验证通过。首轮错误ABI夹具误用class_replaceMethod不改类型编码，修为动态子类错误签名后通过，未放宽生产校验。
- artifact13084666082，ZIP461956字节，GitHub digest `c7a24047563c2907d937e66ba1929d8990ec4d8f5f93f3de380d112799a7e384`已实算匹配；dylib882240字节，SHA256 `a07738101beb59b1ec173f325a95f5e98858726d0be18fb7b50aa85a41f221df`匹配包内清单，本地解析arm64 MH_DYLIB。
- 补记前348/348源码路径与成功commit一致，打包 `artifacts/WeChatUnified-current-source-2792943.zip`，SHA256 `9c0aab3d2f706c958b10d39883d49f7ca40161ca34bc6aedaa0bf5d45f2ec0ce`；是当前部分工程源码，不是完整需求源码。校验记录 `artifacts/verification-41308827848.json`，构建日志 `artifacts/dictation-ci-41308827848.log`。
- 两项设置/配置/安装/布局刷新已接通；防误触为短点按先聚焦，不是业务确认弹窗。UIImageView快照的同值alpha/刷新间隙限制见DICTATION-INTEGRATION.md；真实触摸派发、输入副作用及宿主ABI未真机验收。没有运行Ghidra、上传原样本、操作真实微信或数据。仅补本文与STATUS，不为文档重复CI。

# 2026-11-01 两项P0修复（真实红→绿CI及产物核验通过）

- 红基线 commit `5478dd0c4f33e649783dd53555b252b972f9694c` / run `41305087598` / job `124843744812`：真实生产WUSaveAccountOption→WUSave→磁盘重载18检查11失败；同一构造类I/q/i/Q的复读就绪与普通语音/语音包分别失败1/5/6/6项。独立job仅在实际运行返回预期症状失败时通过，编译错误不计红。
- 修复 commit `cb772143a6b4068659d0da9b7f17f12afefcea9c`；https://github.com/yuku00/LinkCard-Public/actions/runs/41305559880 / job `124845108130` completed/success。18配置检查、每个I/q/i/Q同mock三路径1619断言、构造ABI/范围/ARC释放/替换self/异常1828断言全绿；28结构守护、31 XCTest和全部旧原生测试保留通过。断言数含fixture解析，不等于独立场景数。
- artifact `13083116943` 已下载核验：ZIP447881字节，SHA256 `9cf0ed7c79f038b32b10d3299e84f9633dcbe8d38a3707a1e17a622f4bf140db`；dylib848288字节，SHA256 `1c02f7e15c3fa70e67a4b236c8276bed89e983565dc0cb91dfdea379dc341adf`。GitHub摘要/SHA256SUMS、arm64 MH_DYLIB、iOS16.6/SDK18.5、codesign --verify --strict及本地202页CodeDirectory SHA256/特殊槽核验通过；ad-hoc不是分发身份。
- 从f4d0bfce两次非强制快进指定独立分支，补记前340/340发布路径一致，旧HEAD未reset。仅修缓存入口及共享消息构造，不猜宿主实际类型，不放宽后续语音字段/回执，不改默认或自动发送。日志与独立核验在artifacts/ci-41305559880.log、verification-41305559880.json、p0-final-audit.json。
- 本段与STATUS是成功后本地补记，源码与测试未再改动，不为文档重跑CI；产物内仍为待验文案。未执行真实微信、注入、用户数据或真实发删，仍是有限自主实现而非完整源码/完整功能验收。

# 2026-11-01 统计增量：首轮真实CI及产物独立核验通过

- commit `f4d0bfce26713c88904fec2195f5f32f492c0131`；CI https://github.com/yuku00/LinkCard-Public/actions/runs/41302211055 completed/success；job124835349691。由旧成功8f7148897e63baa07108a90e8f933644ef3b1a53一次非强制快进至既有wechat-unified/initial-20261101分支。成功补记前334/334白名单文件匹配远端，本地HEAD cb0704e4dd738be7733937889f87bb7013f07744保留未reset。
- 本地及CI 27结构检查通过，31 XCTest实际执行0失败，全部旧原生回归通过；包含日期/DST/非单调扫描、同秒边界、访问日志失败原子性/隔离/代次、排行50会话上限/共享100页预算/取消。未删旧测试，未开启生产descendingTimeVerified；无真实CI失败需要修复。iOS arm64/min16.6编译链接及codesign --verify --strict成功。生产mock与合成数据测试不是宿主验收。
- artifact `13081337713`，下载前384399字节（小于50MB）；没有安装依赖或产物。ZIP SHA256 `b4cf9ecf04314037c177d7bf0bd4a0afd2ae3c4855e9d295fdd4ce35008ac7b9`；dylib732592字节，SHA256 `adc0e353e3d31f55b021085e5278c77b2b37ae378523ebe37b57b6971dcd3b6a`。GitHub digest/SHA256SUMS匹配，64-bit arm64 MH_DYLIB；独立校验嵌入CodeDirectory SHA256 174页（每页4096字节）及特殊槽，ad-hoc不是分发身份或宿主兼容保证。
- 证据：artifacts/ci-41302211055.log、ci-artifacts-41302211055.json、verification-41302211055.json、stats-final-audit-summary.json；产物artifacts/WeChatUnified-41302211055.zip与run-41302211055/WeChatUnified.dylib。使用自己的本地api.html、环境token、严格TLS，无凭据输出或真实数据上传。
- 本轮只闭合既有统计增量，补Visits/Overview发布白名单及提交说明，原Sources/*.m iOS编译链和test_stats显式三单元链接覆盖。不扩功能、不重研codec；生产日期排序未证实，保守扫描并标部分。最多50已加载可分类会话、共享100页/20000条，不代表全账号完整历史；访问只计启用后。未执行真实微信/用户聊天/注入/收发删除。AI/Dock/红包详情/在线主题/视频解析保持排除。
- 本记录及STATUS为成功后本地补记，不为文档重跑CI；产物内STATUS为构建时待验版本，下方为历史记录。

# 2026-11-01 输入交互/可逆卡片：本轮待CI

基线b7c3e4082f740f738800dbab7b7afd6a1f25c8dd / CI41298154018。新增输入有效编辑呼吸、纯搜索真实首页header隐藏、精确文件/表情背景卡片，共四项独立配置；保持键盘/发送按钮仍明确阻塞，无伪开关。27项本地结构回归已通过；新增生产纯逻辑目标过滤/64组合输入生命周期/自有值恢复测试，全部旧测试保留。尚未运行本轮真实iOS编译，不以前轮成功替代；后续必须核对本轮head_sha、产物摘要/arm64/嵌入签名。无真实宿主、用户数据、发删或安装；不为文档重复构建。

# 2026-11-01 本地所选语音包：最终后台同步取消补强CI通过

- 最终commit `b7c3e4082f740f738800dbab7b7afd6a1f25c8dd`；CI https://github.com/yuku00/LinkCard-Public/actions/runs/41298154018 completed/success，job124823280889。新增WillResignActive主线程通知同步取消、停止AVAudioPlayer和从presenter关闭整条自有模态链，避免后台计时器暂停与只关闭确认框遗留失效管理页。未以旧包代表补强代码。
- 26项结构测试、语音包生产原生1657断言、原单次发送4991断言与全部旧回归通过；统计18项0失败。断言数含fixture解析，不等于独立测试场景数。iOS arm64/min16.6/SDK18.5严格编译链接和codesign验证通过；尚无真实宿主UI/试听/发删验收。
- artifact `13080148330`；下载前357865字节，小于50MB，无安装。ZIP SHA256 `2b79e327daf2cbdc75d8d39115ca46cee3d4d9bf8ed6bcd9d6eb888d9ba7140b`；dylib680784字节，SHA256 `d983db9359837ddccb073a5ac73158e40de932e67b7a28a574a4335e172eaa11`。GitHub摘要和SHA256SUMS匹配、64-bit arm64 MH_DYLIB、161页嵌入CodeDirectory SHA256与ad-hoc标志独立核验通过。记录artifacts/verification-41298154018.json，日志artifacts/ci-41298154018.log。
- 从指定2062fad累计非强制快进3次、14条白名单工程路径，不改其他项目/workflow；329/329发布白名单在本补记前一致。证据artifacts/voice-pack-final-audit.json；本地旧HEAD保留。三轮CI均成功，后两轮是生命周期补强而非隐藏失败；仅本地文档补记，不为文档重跑CI，归档内状态为构建时待验。
- 外部文件仅试听导入及包导出/导入未实现；不信任任意格式声明，不支持跨版本发送，无跨重启恰好一次保证。崩溃临时残留保留且有界，尚无孤项手动回收UI。未执行真实微信/用户媒体/Photos/真实发删或安装，排除范围不变。

# 2026-11-01 本地所选语音包：前轮CI及产物独立核验通过

- 最终CI https://github.com/yuku00/LinkCard-Public/actions/runs/41297846590 completed/success；commit `a071ccfca058d7fa483283197e33d26bd9f1a844`，job124822367590。首轮91123da5/CI41297524886同样成功，第二次补实模态展示前冻结所选载荷及宿主捕获异常失败关闭，不等宿主清选后再取数据。
- 从指定2062fad70cecb31b915aced85000df7450157449非强制快进2次，14条工程白名单路径；无其他项目/workflow变化，成功后补记前329/329发布白名单一致。证据artifacts/voice-pack-final-audit.json。本地旧HEAD cb0704e4dd738be7733937889f87bb7013f07744未reset。
- 26项结构测试、语音包生产原生1657断言（包含fixture逐字节解析，非1657个独立场景）、原语音发送4991断言及全部旧回归通过。新增覆盖真实所选原载荷与format保存、缺格式/版本/名称、坏媒体/61秒拒绝、账号隔离、稳定ID/重命名、跨版本拒发、两个Store实例共享试听/发送租约、切号/提交前取消、复制校验后真实rename失败保旧、坏索引拒覆、原单次提交器重复调用不双发。WUStats18项0失败；iOS arm64/min16.6/SDK18.5编译链接及严格codesign成功。日志artifacts/ci-41297846590.log。UI仅编译/结构门控，非宿主交互验收。
- artifact `13080266420`，下载前确认357247字节（小于50MB）；未安装。ZIP SHA256 `5a81a34807fad46efdcd3c207cecda877001df181a92c4312a4a73c273b844d1`；dylib680784字节，SHA256 `47d2859848eae057a6e7b66415d5c9bad78ecf9f6f986f6ca4037a150925fc7a`。GitHub ZIP digest及CI SHA256SUMS匹配、64-bit arm64 MH_DYLIB验证通过，独立核验161页嵌入CodeDirectory SHA256及ad-hoc标志。核验artifacts/verification-41297846590.json；ad-hoc不代表分发身份或宿主兼容。
- VoicePackLogic/VoicePacks及Messages真实所选入口、账号工具栏动作已接通：32条/32MiB账号独立原子索引保存原始载荷与实际format/版本配对、离线PCM系统试听、稳定ID/命名/列表/自有记录删除、租约保护、确认当前会话单次发送。复用VoiceSendLogic唯一提交器，不新增宿主发送链。复制后安全读回比较再原子rename，失败保旧；崩溃残留副本不盲删，96MiB/64文件封顶。
- 外部文件仅试听导入、自有包导出/导入未实现；跨版本本地包仅可试听，不信任导入声明、不把任意音频标format4。无跨重启发送恰好一次保证，无实际送达承诺。未执行真实微信/用户媒体/Photos/发删/安装，AI/Dock/红包详情/在线主题/视频解析继续排除。
- 使用自己的api.html浏览器标签和环境token，严格TLS未降级、凭据未输出；只上传白名单源码和合法合成fixture。此为成功后本地文档补记，不为文档重复CI；包内STATUS仍为构建时待验说明。

# 2026-11-01 所选普通语音转发：真实CI及产物核验完成

- CI https://github.com/yuku00/LinkCard-Public/actions/runs/41296334175 completed/success，commit `2062fad70cecb31b915aced85000df7450157449`，job124817854055。从指定0fa5134一次非强制快进，11条工程路径，无其他项目/workflow变动；补记前324/324白名单一致，本地旧HEAD保留。
- 25项结构测试、语音生产解码/ABI/单次提交mock通过（日志4991断言包含fixture逐字节解析检查，不能称4991个独立场景）；覆盖标准/腾讯SILK与AMR真实1秒、60秒/61秒边界、损坏/其他容器、类型/format拒绝、实际NSMethodSignature宽度冲突、缺服务、void以外返回拒绝、插入后异常、请求后异常、不双发、失效前后及不可变数据。全部旧原生回归保留通过，WUStats18/0失败；iOS arm64/min16.6/SDK18.5编译链接、codesign --verify --strict成功。
- artifact `13079267403`；下载前确认338796字节（小于50MB），无安装。ZIP SHA256 `6b692a52b5d828c01ee18ff1f16dc26b7eacce2ae3b598c5ea17402a0cc36ec5`；dylib630304字节，SHA256 `83f777e3be8a2f1832b73036f443b588748352a32dbcc22c03aac84a3ae68ea6`。GitHub digest、SHA256SUMS、64-bit arm64 MH_DYLIB头一致；独立验证嵌入CodeDirectory 149页SHA256及ad-hoc标志，非分发身份/兼容保证。日志artifacts/ci-41296334175.log，核验artifacts/verification-41296334175.json。
- 新增VoiceSendLogic生产解码、精确ABI和单次提交状态机，Messages所选入口/收件人确认、账号手动工具栏；复用Repository调用边界，仓库通用转发拒绝语音。仅已存在原format 4消息的原始SILK/AMR配对，不支持任意导入文件发送，原数据未就绪拒绝。状态未提交/失败/已请求/未知，不称送达，不沿false回退。切号/后台/代次失效取消未提交；没有跨重启账本。
- 本地语音包导入/保存/试听/删除/发送仍未实现：欠缺外部SILK/AMR载荷到宿主format与封装的映射证据，不能拿旧固定4当通用转换。无伪开关、无文件写删；既有安全媒体存储未改。未执行真实微信注入、发删、服务或用户媒体；测试只用既有合法合成音调fixture。AI/Dock/红包详情/在线主题/视频解析继续排除。
- 此为成功后本地补记，不为文档重跑CI；成功产物内STATUS是构建时待验版本。仅本地结构检查初次触发旧全局sendVoice禁令（误匹配ResendVoiceMsg），收窄为唯一已证实选择子白名单，其他旧禁令保留；首轮真实CI即成功，无掩盖编译失败。

# 2026-11-01 朋友圈缓存后台与安全回收：最终CI及产物核验完成

- 最终CI https://github.com/yuku00/LinkCard-Public/actions/runs/41295108120 completed/success；commit `0fa5134eb2a2908b4dcd536b7b0746c635b76155`。首轮41294905914/ff86ee68591a19cd9b50c6ea231c58a147f6f2ea也成功，最后增加实际在途复制排队清理原生测试再发布。
- 相对用户指定96449f8e420cacbba743565bc047ce72a072601a快进2次，11条工程白名单路径，均在wechat-unified/，无其他项目/workflow变化。成功补记前321/321白名单文件一致，证据artifacts/moments-reclaim-final-audit.json；本地HEAD仍cb0704e，未reset。
- 24项结构检查、缓存合成生产原生回归及全部旧测试实际通过；包含共享引用/浏览租约/收藏保留、真实在途复制串行互斥、代次失效、复制后提交写失败、坏/缺索引、链接拒绝、孤项重试、实际unlink和分配块统计。主线程无复制由生产入口结构断言检查，非宿主动态性能验收。iOS arm64/min16.6/SDK18.5严格编译链接成功；WUStats18/0失败，旧媒体/表情/离线编解码/仓库/分组/广告/主题/消息等测试保留，详见artifacts/ci-41295108120.log。
- artifact13078697733，ZIP330756字节，SHA256 `af498ffc4f0854fece0376b31d3596f60233538b4cf749bed977f06c5ef10228`；dylib629920字节，SHA256 `873e926aa5a0117f63f4704e26a21071a103dab92534a0cd88d5dd3e8ed78963`。ZIP digest和CI SHA256SUMS匹配，64-bit arm64 MH_DYLIB核验通过；CI codesign --verify --strict通过，独立校验149页嵌入CodeDirectory SHA256/ad-hoc签名。记录artifacts/verification-41295108120.json。ad-hoc不是开发者分发身份/目标兼容保证。
- 生产改动：仅主线程宿主不可变元数据/路径快照，模块串行队列复制/解码/摘要/读写/浏览；提交核验原子generation，不异步持有未知宿主对象。缓存媒体先提交、正文失败留下可安全清理孤项，不是跨文件原子事务。源消失不更新旧记录。清理先验证/提交索引、原子保存回收计划，再unlink专属目录无引用单链接普通UUID文件。共享引用及浏览租约受保护，复制在途通过同队列互斥。只计真实成功unlink分配块字节，不保证APFS快照/克隆时设备可用空间增量。
- 仍是部分曾见正文/静态图片缓存，不是完整防删；评论/视频保存、缺页/隐私删除推断、媒体后续补齐、未知主时间线协议不扩。宿主管理器旧代次不重绑定，配置/后台返回仍须退出重开主页。没有执行真实微信/用户数据读写/发删/注入，不碰草稿仓库和宿主文件，排除范围不变。未安装新工具，下载前检查产物小于50MB。
- 使用自己的api.html标签和环境token严格TLS；一次查询网络Load failed重试成功，未降级TLS或暴露token。上述为成功后本地文档补记，包内文档为构建时待验版本，不为文档重触发CI。

# 2026-11-01 朋友圈曾见缓存：最终CI与产物已核验

- 最终CI https://github.com/yuku00/LinkCard-Public/actions/runs/41293677586 ，completed/success；commit `96449f8e420cacbba743565bc047ce72a072601a`。从用户指定 `dfb4879e037aa4508ecd6e5e038c22f2df9bcebb` 在既有 `wechat-unified/initial-20261101` 两次非强制快进，仅13条工程白名单路径；补记前321/321文件与远端一致，证据 `artifacts/moments-cache-final-audit.json`。本地HEAD仍cb0704e，未reset，未改其他项目/workflow。
- 实际入口为WCHomepageMgr的getHomepageData返回数组与onDataUpdated真实回调；固定管理器account/generation，字段/可见性ABI不符则跳过，永不写宿主m_cache或拦删除。自有账号正文与可靠存在图片→设置/本地工具/朋友圈缓存→正文/图片浏览、收藏、保留天数、确认清理。不是独立文件导入器；仅“曾见内容”，不从缺页/隐私变化判断删除，不声称恢复未收到内容。监控账号标识手动配置，排除优先；无主动请求或永久轮询。启用前缺宿主接口则拒绝，不保存伪启用；错误诊断只对所属账号展示。
- 两轮CI均成功：首轮 `41293255156` / `cbf43a1357b5ab81538e10ab088f5f4afbf711f1`；收尾增加接口启用门槛、账号诊断隔离及配置/后台后重新进入提示，再以最终CI完整验证。没有删除测试、没有掩盖失败。
- 新增生产逻辑测试真实执行规范化/64位ID、分页不误判、重复缓存、账号隔离、收藏跨更新和保留、坏索引拒绝清理、超限/保存失败原数据保留及媒体复制失败。23项结构护栏及全部旧回归通过；保留表情71、媒体草稿51、仓库53、离线解码40057、语音5162、广告及Hook夹具、消息/主题/分组/首页/便捷朋友圈、WUStats18项0失败。iOS arm64/min16.6/SDK18.5 warnings-as-errors编译链接通过；没有执行真实宿主UI和朋友圈数据，源代码护栏不等于动态UI验收。

## 下载与独立核验

- Artifact `13078521828`，ZIP `artifacts/WeChatUnified-41293677586.zip`，**321336字节**，SHA256 `3d43f1329fd224f93e15db9e4f5abd61e71f18ece5c516c27242ad787199585b`，匹配GitHub digest。
- dylib `artifacts/run-41293677586/WeChatUnified.dylib`，**613120字节**，SHA256 `c4830e4d390575d4bef62fa626c1ea00f9d251a70a2c9eb7c198a649878101d0`，匹配CI SHA256SUMS。64-bit arm64 MH_DYLIB；CI严格codesign通过，本地独立校验145页×4096的CodeDirectory与特殊槽SHA256。签名为ad-hoc，不是分发证书。
- 元数据、完整CI日志、核验结果分别为 `ci-artifacts-41293677586.json`、`ci-41293677586.log`、`verification-41293677586.json`。首次成功产物及此前全部产物保留。
- 先查产物大小，远低于50MB；本轮未安装任何依赖、微信或注入插件。只使用自己本地api.html标签、严格TLS与环境token，未输出token，未上传原库/转储/样本用户媒体，未读真实朋友圈、未发送/发布/删除任何用户数据或原服务。

## 精确残余

仅手动访问联系人主页数据，尚未接主时间线完整采集；宿主ABI和UI/切号生命周期需隔离验收。视频、全部评论保存/合并、首批媒体不全后的补齐未实现，UI明示。正文与媒体独立提交，媒体失败不撤销正文；已存在媒体索引不覆盖。200条/正文索引1MiB/记录封装JSON10000字符；图片选择上限每张8MiB、最多9张，账号资源512MiB，超限拒绝而不自动淘汰。复制和校验目前在有界主线程任务执行，可能卡顿；源文件在复制前消失就只保留正文。

保留天数由用户确认清理触发，非自动后台清扫；收藏保留。坏正文或媒体索引禁止清理，清理只动自有索引，不unlink任何源/共享/不可变文件，**不释放文件占用空间**。配置或退后台使旧管理器generation失效，需退出重开联系人朋友圈；不自动重新绑定旧回调。未把这些限制冒称“防删全部完成”。图片转表情/公众号入库维持原精确宿主接口阻塞，不再扩大原图要求。AI/Dock/红包详情/在线主题/视频解析均未新增。

本节与STATUS为成功后本地补记，包内文档是构建时版本；不为文档重跑CI。

# 2026-11-01 图片转表情补核：无代码变更，无新增CI产物

本轮没有接通聊天图片转表情，不新增伪开关。仅补静图alloc/init、GIF NSNumber字段与delegate接收者、原图获取含缩略/中图回退的定向证据，精确接口缺口见 IMAGE-TO-EMOTICON-GAP.md。未重复图库校验，未运行/发布新构建，未重新下载旧产物；下方41291640930及hash均为前次成功结果，不是本轮验收。未reset本地旧HEAD，未安装/操作微信/写Photos/发送用户数据。

# 2026-11-01 原表情保存图库生产链交付（图片转表情/公众号入库仍未实现）

- 最终CI：https://github.com/yuku00/LinkCard-Public/actions/runs/41291640930 ，completed/success；commit `dfb4879e037aa4508ecd6e5e038c22f2df9bcebb`。现有独立分支从指定 `b00cb1d502f1f7aa99b1e6c7f23b5269f81fcd09` 快进4次，仅12条工程白名单路径；未reset本地旧HEAD，未改workflow或其他项目。补记前317/317白名单blob与远端一致（artifacts/recovery-audit.json、emoticon-remote-diff.json）。
- 实际新增：账号手动工具“所选表情保存图库”→宿主长按进入多选、仅一个47类表情→确认→证实的EmoticonUtil原路径（NO/NO，不更新时间）→只读20MiB有界原文件→GIF/PNG/JPEG结构与逐帧解码验证→Photos AddOnly→原NSData addResource→实际performChanges完成结果。没有UIImage重编码、没有全局菜单Hook或手动文件导入假入口，不自动发送、不修改原图/原消息/Dock。首次系统授权单独仅请求权限，返回后必须再次手动确认，不绕开共享generation失效规则。取消/拒绝/错误/失效不报成功，空事务和异步异常不算成功。
- macOS实际执行生产EmoticonLogic格式/文件/事务mock **71断言**，22项结构检查及全部旧回归通过；分组35、媒体草稿51、仓库53、离线解码40057、语音5162、广告14及Hook fixture、消息21、朋友圈29、首页/主题、文字草稿与图片初始化ABI、WUStats18项0失败。iOS arm64/min16.6/SDK18.5含Photos/UI生产编译链接warnings-as-errors通过。macOS权限/写入为注入mock，未运行真实Photos或宿主UI；不能据此宣称微信可用已验。

## CI失败与真实修复

1. `41290966428` 的新原生测试拒绝“合法GIF”夹具，失败发生在格式断言，非编译错误。`41291057826` 保留断言增加合成数据诊断，证实CGImageDestination对两张完全相同图像生成了第二帧仅LZW码宽后直接终止的损坏流；ImageIO却容错只识别第一帧。生产完整块检查正确拒绝，没有放宽或删测试。
2. 合成器改为不同像素的两帧并明确delay，原损坏base64保留为拒绝回归；`41291265768` 全量成功。收尾进一步核对结构帧数必须等于ImageIO帧数、增加真实超20MiB稀疏源拒绝、按页面/代次/消息集合阻止A→B→A重复点击、异步Photos异常保护。
3. 共享WillResignActive会取消generation，因此首次权限改为独立授权动作，用户再次确认才保存；没有对权限弹窗开放失效豁免，也不自动重试。最终 `41291640930` 对最终代码全量通过，旧测试全部保留。未因文档补记重跑。

## 已下载并独立核验

- Artifact `13076584417`；ZIP `artifacts/WeChatUnified-41291640930.zip`，**303318字节**，SHA256 `d8cb5d3adeff0cac14c9d6bc172b5f2de3ba6bbfdbd780a7352d9e5693b0150f`，与GitHub digest相同。
- dylib `artifacts/run-41291640930/WeChatUnified.dylib`，**578944字节**（较561296增加17648字节，约3.14%），SHA256 `69915ad70f57698a2ed8242bcd1b5e36d1bb090ebc0a96352b618c4b7fa00195`，与CI SHA256SUMS相同。
- 本地验证arm64 MH_DYLIB；CI严格codesign通过，独立检查CodeDirectory **136页×4096**及特殊槽SHA256、ad-hoc标志。不是开发者分发证书。核验见 `verification-41291640930.json`，日志 `ci-41291640930.log`，元数据 `ci-artifacts-41291640930.json`。
- ZIP远低于50MB；未安装任何新工具链/宿主或注入插件。只用独立本地api.html标签、严格TLS、环境token；未输出凭据、未上传原库/转储/用户媒体。

## 精确未完与风险

- 图片转表情、公众号图片添加表情未实现，不挂开关、不宣称不可实现。仅定向补核WCRefine 0xfc5e0c/0xfc65e8：GIF终点为EmoticonCustomManageAddLogic startAddEmoticonWithWrap:，需要AddEmoticonWrap/EmojiInfoObj/EmoticonUploadInfoObj及宿主资源目录写入；静图为EmoticonPickViewController setM_image:与PushViewController:animated:。类/选择子已定位，但初始化/整数ABI/委托完成方法、选中聊天原图和公众号图片原始NSData来源、宿主菜单动作注册仍待闭环。不能把旧WCRefine助手自身的方法误当宿主接口，不从任意网页抓取上传内容。
- 保存链只支持可获得完整原始GIF/PNG/JPEG的单个表情，WxAM特殊容器和未就绪资源拒绝；最多20MiB、500帧、单帧1600万像素/合计6400万像素。严格拒绝链接路径可能不接受部分宿主合法别名路径，不能承诺所有表情。
- 用户必须先手动选择工具，再在聊天宿主多选一个表情；原长按菜单直接增加按钮尚未做。多选模式工具菜单可见性、实际宿主ABI、系统权限提示和图库动画保留仍须真机验收，未读真实聊天/未写真实Photos。状态机mock不等于Messages完整宿主UI测试。
- 保存已提交后无法撤销；防重仅页面/账号generation内，最多100次，不跨重启持久化。失败或结果未知需用户核对图库再退出重进手动重试，不承诺恰好一次。格式验证有界但未声称能抵御同宿主进程对源文件的任意恶意并发篡改。
- AI、系统Dock/ActionBar、红包详情、在线主题、视频解析排除保持；原图、原消息、宿主资源不修改，无发送/删除用户数据。

本节与STATUS为成功后本地补记，包内文档是构建时版本；未为补记重复发布。旧成功产物全部保留。

---

# 2026-11-01 媒体草稿中断恢复交付（图片有限恢复，视频仅备份）

- 实际CI：https://github.com/yuku00/LinkCard-Public/actions/runs/41290054523 ，completed/success；commit `b00cb1d502f1f7aa99b1e6c7f23b5269f81fcd09`。基于实查远端文字草稿93b6c5a快进3次/13条工程白名单路径，未重提旧文字构建、未reset本地旧HEAD、未改其他项目或workflow。补记前314/314发布白名单blob一致；证据 artifacts/recovery-audit.json 与 media-remote-diff.json。
- macOS真实执行媒体生产事务51断言、文字存储与图片初始化ABI测试、21项结构检查及全部旧回归；仓库53、离线解码40057、语音5162、广告14及Hook fixture、消息21、分组34、朋友圈29、首页/主题测试、WUStats18项0失败全部通过。iOS arm64/min16.6/SDK18.5 warnings-as-errors编译链接成功。未把macOS mock冒充真实微信或UIKit端到端验收。
- 第一轮41289790686在媒体失败路径崩溃；第二轮41289901200加诊断，实际捕获objc_retain EXC_BAD_ACCESS。根因为生产循环内autoreleasepool使通过NSError **返回的错误先于ARC调用端writeback释放。移除内层池并加读取失败错误说明回归后第三轮全量通过；原测试未删除。另补复制写入失败与超64MiB稀疏源测试，索引/校验读取复用O_NOFOLLOW、fstat及上限读取，失败保持原索引与资源。

## 已下载并独立核验

- Artifact `13076607161`；ZIP `artifacts/WeChatUnified-41290054523.zip`，293157字节；SHA256 `0b64d6bd10831aa43105426f8cf494f41a3b474e9b8778daea859c86af4ba643`，匹配GitHub digest。
- dylib `artifacts/run-41290054523/WeChatUnified.dylib`，561296字节；SHA256 `dc1826b77280b5d9353261eef7de305f27bc980b0ed360223871f46884654e7d`，匹配CI SHA256SUMS。
- 本地解析64-bit arm64 MH_DYLIB；CI codesign --verify --strict通过，本地独立验证CodeDirectory 132页×4096及特殊槽SHA256，ad-hoc有效（不是分发证书）。日志 ci-41290054523.log、元数据 ci-artifacts-41290054523.json、核验 verification-41290054523.json 均已落盘。
- 使用自己的本地api.html标签、严格TLS和环境凭据；未打印token、未上传原库/转储/用户媒体/密钥，未安装工具链，未注入或操作真实微信。旧41288097864产物保留复用。

## 交付范围及剩余缺口

图片仅真实UIImage静态正向像素、1–9张、单张1600万像素/PNG20MiB，重建initWithImages:contacts:后选择数组与正文回读确认；没有原图元数据、位置/可见范围/联系人恢复。视频仅独立文件与正文备份，缺自有URL构造sightDraft所需类/初始化、itemAry元素类型、封面/时长/编辑状态及上传持有协议，不能恢复真实视频编辑器，不称完整图文视频草稿。

新资源独立UUID、核验后原子提交索引；同路径更新与共享/编辑中引用不unlink。坏索引禁止覆盖及清理，删除仅索引，失败副本也保留；每账号512MiB/4096文件硬限额，达到上限拒绝保存，未自动回收。账号/generation/前台检查保留。文件描述符读取有界但未声称能抵抗同一宿主进程任意并发恶意篡改；UIKit捕获/恢复及真实宿主契约仍未真机验收。无自动发表、无宿主文件删除。AI/Dock/红包详情/在线主题/视频解析继续排除。

本节及STATUS为成功核验后本地交付补记，包内文档是构建时版本；未为补记重复发布。

---

# 2026-11-01 文字草稿准确构建收尾（未重复编译）

CI 41288097864 completed/success，commit `93b6c5a71d52b670595387b79d95243a644a4821`，artifact 13075473694 已通过独立本地 api.html / 严格TLS下载。ZIP 282508字节，SHA256 `626997f42072456ca13e165be07a46026dc641a4682f353925f622e93516a93d` 与远端digest一致。dylib 544128字节，SHA256 `f135ab3bae0bf6124c480e82a396d2113266465356ad0b8010080b6991970d9e` 与SHA256SUMS一致。arm64 MH_DYLIB；CI strict codesign通过，本地独立验证嵌入ad-hoc CodeDirectory 128页×4096字节及特殊槽哈希。产物在 artifacts/run-41288097864；核验记录 verification-41288097864.json。远低于50MB，未安装或注入宿主。该产物仅文字草稿，不代表媒体完成。本地旧HEAD与工作树均保留。

# 2026-11-01 账号消息仓库：实际CI成功交付

- 最新commit `a062ce0a663999cc766790214f9441f4fb97d899`；现有独立分支 `wechat-unified/initial-20261101` 从指定 `23539a3972d64b4118c1b3dba77d1a8b30389826` 快进3次，13条自主路径；未reset旧HEAD/工作树、未强推、未改其他项目。最终306/306发布白名单blob一致（后补此文档前），审计见 `artifacts/repository-remote-diff.json` 与 `artifacts/recovery-audit.json`。未上传原库、转储、用户数据或Key，原排除项不变。
- [CI 41286051033](https://github.com/yuku00/LinkCard-Public/actions/runs/41286051033) completed/success；[artifact 13075217370](https://github.com/yuku00/LinkCard-Public/actions/runs/41286051033/artifacts/13075217370) 已下载核验。严格TLS使用本次自有api.html标签与环境token，未打印凭据。
- 实际新增：账号独立原子文件仓库，纯文本新建、助手宿主所选消息身份引用入库、备注/删除自有条目、手动工具栏入口、组合选择与冻结目标确认、逐项已请求/失败/未知。Messages复用account/session/generation；自有仓库模态例外避免正常打开就取消，原聊天导航所有权仍核验。切号/后台/停用取消未提交；无自动重试或提交后回退。原消息引用不是媒体备份，源消失不假恢复。
- macOS原生实际执行：Repository生产逻辑/宿主发送入口mock **53断言**（账号文件隔离/文件内账号双核验、坏文件、实际1MiB超限、写入失败、BOOL false非送达、异常未知且仅调用一次、错误ABI零调用、void转发）；20项结构测试；GroupLogic34断言（旧32语义全保留，另加仓库合法/去重两项）；所有旧语音/codec、Ads及生产Hook mock、Messages、Home、Moments、主题、WUStats18项0失败全部通过。源码整体iOS arm64/min16.6实际编译链接、ad-hoc签名与strict校验成功。不是再次开展codec核验任务，仅正常保留全量回归。
- 失败根因完整保留：首轮41285687845编译发现Apple UInt typedef冲突，改私有RepoUInt；第二轮41285812426旧“仓库未实现”夹具仍把repository当非法动作，保留该非法动作拒绝/去重测试但将不支持样例改为autoReply，并新增repository合法及去重测试，没有删除测试。第三轮全量成功；同时补齐模态生命周期例外及结构回归。

## 下载与独立核验

- ZIP：`artifacts/WeChatUnified-41286051033.zip`，**275119字节**；SHA256 `e3a427769f178d14b513a324632b93860e9770631296dcfdc83affc984626578`，与GitHub digest完全一致。
- dylib：`artifacts/run-41286051033/WeChatUnified.dylib`，**543568字节**，较上版508880增加34688（约6.82%）；SHA256 `a007d53e5c118f855adcf5a7ff5559e780485b853bd2743fa2cbb31d4f1cc1e6`，与CI SHA256SUMS一致。
- 64-bit arm64 MH_DYLIB、IOS/min16.6、系统依赖；CI `codesign --verify --strict` 通过，本地另逐页核验嵌入CodeDirectory **128页×4096** SHA256及特殊槽，ad-hoc标志有效。ad-hoc不等于开发者分发签名。
- 产物ZIP无测试可执行/mock库；仅dylib、验证文本/文档、既有解码依赖许可证。未安装任何新工具链或宿主；无真实微信读取/发送/删除操作。

## 精确缺口与未验边界

1. 文本仅适配已证据确认且运行时匹配的 `CMessageMgr sendMsg:toContactUsrName:`；缺此协议的宿主明确失败，不猜CMessageWrap时间/状态构造、不做AddMsg盲回退。
2. 原消息转发仅通过 `ForwardMessageLogicController ForwardMsg:ToContact:`；图片/视频/语音/文件/名片等是否被具体宿主支持、附件清理/未下载、真正送达均未验。没有独立媒体备份，没有源失效恢复或自动定位/导航助手。
3. 助手入库依赖用户先在宿主多选；尚未真机验证多选模式与聊天工具菜单同时可达性、UI弹窗/键盘/模态完整生命周期。没有伪造一个微信运行环境来声称这些通过。原生mock覆盖直接生产RepositoryLogic调用边界，不等于整段Messages宿主服务/UI集成测试。
4. 防重复仅当前面板及确认/单批，不是跨重启恰好一次；没有持久发送账本/服务端回执，崩溃或未知后需用户先在宿主核对。关闭/切号不撤销已提交的宿主请求。
5. 总量200条、每条/批50项、文本10000字、备注80字、文件1MiB，账号UTF8最多100字节；显式拒绝超限，不丢弃旧条目。文件为自有明文plist依赖宿主沙盒保护，不声称独立加密。

本节与STATUS为成功下载核验后的本地交付补记，未为文档再次触发CI。

# 2026-11-01 离线SILK/AMR生产集成交付：实际CI成功

- 成功commit `23539a3972d64b4118c1b3dba77d1a8b30389826`，分支 `wechat-unified/initial-20261101` 从指定348040c快进两次；保留本地旧HEAD与全部未提交成果，不reset、不动其他项目。
- [Actions 41284657099](https://github.com/yuku00/LinkCard-Public/actions/runs/41284657099) completed/success；artifact `13075105011` 已下载。301/301发布白名单文件与成功提交一致（后补本段文档之前）。源码仅必要固定版本decoder闭包/许可证/构建测试及合成fixture，无原插件、逆向转储、真实媒体或凭据。
- 主工程WUVoiceDecode实际接入标准/腾讯SILK、AMR-NB；SILK明确请求16kHz、AMR-NB8kHz，mono signed-int16 Apple小端，数值转换float计算真实波形与时长，沿用seek/UI。8MiB文件、5120字节SILK包、9000包、180秒、受限内存，错误/截断/超限/取消不返回部分成功。NSProgress逐包取消与既有request/account/generation交付检查并存。
- macOS runner实际执行：19项结构检查；生产C入口40057断言（完整PCM指纹、峰值、真实时长、错误输入、取消、180秒边界）；WUVoiceDecode/VoiceLogic 5162断言（含保留的52项旧断言和合成波形/seek）；Ads14及运行期Hook fixture、Message21、Group32、Moments29、Home、主题ZIP、WUStats18/0失败全部通过。iOS arm64 decoder静态库及dylib实际编译链接通过，平台IOS/min16.6/SDK18.5；未在iOS或真实微信执行。
- 首轮CI `41284108859` 没有跳过失败：暴露旧AMR固定点代码GCC -O2与Clang/GCC -O0/-Os输出差异。最终固定`-Os -fwrapv -fno-strict-aliasing`，采用全部PCM FNV64及精确峰值（SILK b33249e300d33e5b/12595；AMR 66b16db954fbb6aa/2992）替代任意振幅阈值；保留所有测试。独立现有FFmpeg在同一合成AMR的峰值3300，与不同实现有差异，不把旧smoke的9960当跨编译器金标准；不宣称穷尽codec符合性。

## 已下载产物及独立核验

- ZIP `artifacts/WeChatUnified-41284657099.zip`：259069字节，SHA256 `98a74c5c32c4678ccfe6e769558234b721dc56f78d607c79a474b75f0c8b0d17`，与GitHub digest完全一致。
- dylib `artifacts/run-41284657099/WeChatUnified.dylib`：508880字节，SHA256 `7d2a39d838246343221774e7208a617ff370492c3b2f5e5c300cd1be174e142e`，与SHA256SUMS一致；原376016字节，增加132864字节（35.33%）。ZIP由160802增至259069字节（含新增测试证据与许可证）。
- 本地Mach-O解析为64-bit arm64 MH_DYLIB；CI严格codesign验证通过，本地独立验证119个4096字节嵌入CodeDirectory代码页及特殊槽SHA256。签名ad-hoc，非商店/分发证书。
- SILK许可证、AMR Apache LICENSE及完整NOTICE随包，逐字节与源码一致。Skype BSD式条件保留，不作专利保证。只构建54个SILK+76个AMR单元，无encoder，无安装下载，无多余iOS架构。
- 精确源码ZIP `artifacts/WeChatUnified-source-23539a3.zip`：301个已审计文件、721599字节；SHA256 `1c8c7f4586cdbaf67dfcd0d2417c4e0e33d87a9f63363d0b304a879e62f95f5b`。此包与成功提交一致，本段为之后本地补记，不为文档重复触发CI。

限制：AMR-WB、坏质量/NO_DATA与保留FT拒绝；无一般完整性校验的合法帧位翻转、恰好帧边界截短无法普遍识别。宿主路径/ABI仍须运行时匹配；未执行真机注入、真实媒体、宿主播放seek兼容和性能验收。全部AI、ActionBar/Dock、红包详情、在线主题、视频解析继续排除。

---

# 历史：语音显示链增量（当时SILK完整链仍缺）

- 最新commit `348040c4a8fb4de331536f09717822632b07c5d0`；在既有 `wechat-unified/initial-20261101` 分支从55b1eb4快进两次，未reset本地旧HEAD、未动其他项目。
- [CI 41280295233](https://github.com/yuku00/LinkCard-Public/actions/runs/41280295233) completed/success；[artifact 13072693084](https://github.com/yuku00/LinkCard-Public/actions/runs/41280295233/artifacts/13072693084)。第一次CI 41280169716因AudioToolbox既有Size类型与本地回调同名而编译失败；改为VoiceDataSize后全量重新通过，无删测试或忽略-Werror。
- 19项结构检查、新增Voice52项原生断言通过，包含实际生成WAV→生产AudioToolbox解码→实际帧时长/48桶峰值、静音/双声道/非有限值/边界、整数毫秒seek与生产lease生命周期判定。全部旧Ads14与运行Hook fixture、Message21、Group32、Moments29、Home、主题ZIP、WUStats18/0失败均通过。iOS arm64严格编译链接与codesign验证成功。
- 发布白名单49/49 blob与远端一致，机器记录 `artifacts/remote-audit-41280295233.json`（本地后补交付文档之前）；仅自主源码、测试和构建说明，不含逆向库/转储/用户媒体/凭据。所有网络经自己的本地api.html桥和原生严格TLS，token只从环境引用。

## 产物独立核验

- ZIP `artifacts/WeChatUnified-41280295233.zip`，160802字节；SHA256 `91361ef414bae8b0f76a254e4ba6a69d54b4c1d59593c8eed7877bce699f3fef`，等于GitHub artifact digest。
- dylib `artifacts/run-41280295233/WeChatUnified.dylib`，376016字节；SHA256 `bd59077d2ce248506336201d7f3387e2d0fb7b2ba102577a4cdab6e7a6a6b54e`，等于包内SHA256SUMS。
- 本地解析确认64-bit arm64 MH_DYLIB；CI codesign --verify --strict通过；本地独立核对嵌入CodeDirectory的87个4096字节代码页及特殊槽SHA256，ad-hoc标志正确，非分发证书签名。
- 记录 `artifacts/verification-41280295233.json`、`ci-artifacts-41280295233.json`、完整 `ci-41280295233.log`。先查160802字节体积后下载；没有安装工具包或注入微信。

## 执行链与准确缺口

真实播放器currentPlayTime读取和seekToTime:均运行时验ABI，旧导出证明32位毫秒；不是浮点秒。显示层不改任何原消息/模型时长，不自动播放/发送，不访问网络。系统已识别WAV/CAF/M4A容器才解码PCM并计算真实时长/真实波形；拖动仅在当前播放、成功解码和账号/消息/代次/服务实例有效时松手调用seek，进度只由随后真实时钟读取更新。单显示计时器，后台/关闭/复用/离页取消；无随机波形、无假进度、无抢键盘。

**尚未满足所有普通微信语音的完整链：SILK/AMR没有当前宿主PCM布局/采样率可靠契约，不冒险猜24kHz。** 对这类消息只显示宿主真实已播放时间，明确标记总时长/波形不可用且禁止seek。保持键盘无可靠入口，未加入。真实UIKit布局、手势与聊天滚动冲突、宿主时间语义/实际seek命中、切号与后台等仍需隔离真机验收；现有模拟测试不是宿主验收。没有真实收发删或真机通过结论，不称全项目完成。全部AI/ActionBar Dock/红包详情/在线主题/视频解析继续排除。

本说明及STATUS为成功后的本地交付补记，不为文档再次触发CI；归档内STATUS保留构建时状态。

---

# 2026-11-01 独立广告：真实CI通过与产物核验

本轮只收敛朋友圈广告有效性和小程序非激励开屏两个独立模块，公众号五入口保持不变。默认关闭；精确运行签名门控；朋友圈仅广告validator且dataItem精确WCDataItem、参数完整才改原YES为NO；小程序只canShow双门控且两处完整可用。不吞JS事件、不伪造激励完成/奖励、不全局改URL、不清空广告存储。不是全项目完成；目标微信真实命中与生命周期未验收。

- commit `55b1eb447321d73cd1c94c64f526da14442172f2`，从`16ca9c7398906dceda9863f8abdecc1ba04ab1bb`在现有独立分支快进1次，仅12条自主源码/测试/STATUS/构建路径，无workflow或其他项目变化。未reset主工程旧HEAD。
- [CI 41279290907](https://github.com/yuku00/LinkCard-Public/actions/runs/41279290907)：completed/success，首次构建成功，无删测试或忽略错误。
- [Artifact 13072367167](https://github.com/yuku00/LinkCard-Public/actions/runs/41279290907/artifacts/13072367167)，head_sha与远端/发布状态一致。
- 18项结构检查、AdsLogic14项原生断言、直接编译生产Ads.m的真实ObjC方法Hook fixture通过（签名错误/缺门控/未知与nil模型/开关回退/原IMP次数/激励及JS事件原路径）。原MessageLogic21、GroupLogic32、MomentsLogic29、HomeLogic、主题ZIP与WUStats18项/0失败均通过；严格-Werror编译链接和签名验证通过。
- 发布43/43白名单blob与远端完全一致（文档后补之前）；证据`artifacts/remote-audit-41279290907.json`。仅白名单自主文件公开，无原库、转储、素材或凭据。

## 下载与独立核验

- ZIP：`artifacts/WeChatUnified-41279290907.zip`，146011字节。
- ZIP SHA256：`30477812d4d7291a838bbb5f666beb699df59d66b346b0550bbda3d5a0d3f8f7`，等于GitHub digest。
- dylib：`artifacts/run-41279290907/WeChatUnified.dylib`，356720字节。
- dylib SHA256：`c5e935f9758b62376346dca43b4a5eb2803e2033eb7e0cd894f9e43355ee30b0`，等于包内SHA256SUMS。
- 本地确认64-bit arm64 MH_DYLIB；CI codesign --verify --strict通过；本地独立解析LC_CODE_SIGNATURE/SuperBlob/CodeDirectory核对82个4096字节代码页和嵌入特殊槽SHA256，ad-hoc标记正确，不是分发身份签名。
- 证据`artifacts/verification-41279290907.json`、`ci-artifacts-41279290907.json`与完整`ci-41279290907.log`。自己的本地api.html桥，原生严格TLS，环境token不输出。已先查体积，未安装任何工具包或注入微信。

未加入表情图库/图片转表情：没有补齐原始动态数据→Photos及权限/完成反馈链，不把静图当GIF；未重复猜拍一拍接口。AI/ActionBar Dock/红包详情/在线主题/视频解析继续排除。没有真实收发删、原远程认证或目标宿主验收；小程序正常状态机、朋友圈缓存及实际广告过滤效果仍须隔离设备验证。此段及STATUS为成功后本地交付补记，归档STATUS保留构建时状态，不为文档再次提交。以下为历史。

---

# 2026-11-01 半屏朋友圈：实际发布、测试与签名核验闭合

最新commit `16ca9c7398906dceda9863f8abdecc1ba04ab1bb`，从 `f031091092f7cf7e2a7e79cecc8a3a605e7f4a0d` 在既有独立分支 `wechat-unified/initial-20261101` 快进1次。只变更13个 `wechat-unified/` 自主路径，没有其他项目/workflow/原库/逆向转储/附件/凭据。主工程未reset；38项发布白名单在后补文档前逐blob与远端完全一致，审计存于 `artifacts/remote-audit-41278387645.json`。

## 真实CI与新增实现

- [CI 41278387645](https://github.com/yuku00/LinkCard-Public/actions/runs/41278387645)：completed / success，首次构建即成功，无删测试、无失败绕过。
- [Artifact 13072167405](https://github.com/yuku00/LinkCard-Public/actions/runs/41278387645/artifacts/13072167405)。run与artifact的head_sha均与远端一致。
- `Sources/Moments.m`：签名门控创建真实WCTimeLineViewController；自有UIPresentationController固定半屏、导航子控制器containment、关闭自有展示链、保留聊天布局；精确聊天输入对象消费完整小写rp且清空同步通知宿主delegate，未调用任何发送接口；已接账号手动工具菜单和真实开关，默认关闭。
- `Sources/MomentsLogic.h/.m`：rp/组合输入/编辑状态/归属、账号会话代次失效及半屏几何判断；`tests/moments_logic.m`真实原生29项断言全部通过。
- 17项结构检查、原MessageLogic21断言、GroupLogic32断言、HomeLogic与主题ZIP原生测试、WUStats18项XCTest/0失败全部通过。arm64/iOS16.6最低部署、严格-Werror编译链接通过。

## 已下载及独立核验

- ZIP：`artifacts/WeChatUnified-41278387645.zip`，143607字节。
- ZIP SHA256：`d1838d8fd4c388c841ca66aca8044ed6f18da91d0d87757ee951fb56dc0cfb15`，与GitHub artifact digest相等。
- dylib：`artifacts/run-41278387645/WeChatUnified.dylib`，356528字节。
- dylib SHA256：`f3171d1aa33d56c98e3b01322ad5b8f2f11b213ec2dd3cf5b48d7cbe42e4e835`，与包内SHA256SUMS相等。
- 本地核验64-bit arm64 MH_DYLIB；CI `codesign --verify --strict`、valid on disk、Designated Requirement通过；另外本地解析LC_CODE_SIGNATURE、SuperBlob、CodeDirectory，独立逐一核对82个4096字节SHA256代码页及嵌入特殊槽摘要，ad-hoc标记正确。不是开发者分发签名，也不代表宿主兼容。
- 机器证据：`artifacts/verification-41278387645.json`；完整日志：`artifacts/ci-41278387645.log`。全程自己的本地api.html标签、原生严格TLS；凭据仅环境取用，无输出、无上传、无大型安装。

## 精确残余与风险

拍一拍仍未完成：现有定向引用只闭合同步BOOL发送路径，头像单击/插件自身手势候选未证为可冻结目标的发送前动作；没有假成功、异步重放或空开关。半屏朋友圈源码/CI完成不等于微信8.0.70真机验收：输入结构不匹配时rp绑定不可用；宿主自己的导航、媒体/评论、在途网络取消、旋转、切号和键盘实际布局需隔离设备验收。自己的关闭只在用户明确关闭、原账号会话代次有效、原输入仍在原窗口且无其他第一响应者时恢复键盘；失效/后台取消不抢焦点。没有真实宿主注入、发送、撤回或数据删除；不称全部项目完成。AI/ActionBar Dock/红包详情/在线主题/视频解析保持排除。

此段及STATUS的CI结果为成功后本地交付补记；归档STATUS保留编译时状态，不为文档再次提交/重复构建。以下均为旧版本历史。

---

# 2026-11-01 首页分组同步加固：历史发布闭合

**最新工作树生产代码已发布，CI真实成功，产物已下载核验；仍无真机验收。以下最新结论覆盖所有历史章节。**

- 首次实查远端 head 仍为 `82bf8e04567323380539117832021639a8f79055`，与 release-state 一致，无他人新增提交；34个白名单文件中33个 blob 相同，唯一未发布差异为 `Sources/HomeGroups.m`。旧本地git HEAD没有作为依据。
- 仅将这一个文件快进发布为 `f031091092f7cf7e2a7e79cecc8a3a605e7f4a0d`；未强推、reset、重复发布旧成果或修改其他项目/workflow。发布后34/34白名单blob一致，之后STATUS仅追加本地交付说明，不再为文档重跑CI。
- 仓库 `yuku00/LinkCard-Public`，分支 `wechat-unified/initial-20261101`；release-state、实查分支head、run head_sha及artifact head_sha一致。
- CI：https://github.com/yuku00/LinkCard-Public/actions/runs/41277007885 ，completed / success；编译与上传均成功。
- 产物：https://github.com/yuku00/LinkCard-Public/actions/runs/41277007885/artifacts/13071840910 。本地ZIP：`artifacts/WeChatUnified-41277007885.zip`；dylib：`artifacts/run-41277007885/WeChatUnified.dylib`。

## 同步加固已纳入

HomeGroups.m 已包含 setNormalSessions 返回前同步投影、置顶计数setter同步apply、配置/页签变化调用签名门控的 MainSessionMgr.onNeedReload 重建宿主派生缓存，以及会话getter解码异常返回nil的回退。未扩展功能、未删除或削弱测试。首页分组最小生产链已编码并编译通过，历史“未实现/待CI”不再代表当前状态；宿主实际行为仍未验收。

## 核验结果

- 15项结构检查；MessageLogic 21条原生断言；GroupLogic 32条原生断言；HomeLogic分类、原对象索引、折叠置顶、计数、恢复、自定义删除及账号隔离测试；主题ZIP原生测试；WUStats XCTest18项、0失败：实际CI全部通过。
- 严格 `-Werror` 编译链接通过，arm64 MH_DYLIB，iOS最低16.6 / SDK18.5。
- ZIP 134858字节，SHA256 `054f6046f199c70f8a7eeaefe7eceed7c0e02d00bd3e600e6f43fade6de0497a`，本地实算匹配GitHub digest，ZIP CRC检查通过。
- dylib 321792字节，SHA256 `eb2f8e6128a5b05ec9018ca81f3838be1f9e718e626584237b9a992f1578d5d3`，匹配包内SHA256SUMS；本地二进制头确认64-bit arm64 MH_DYLIB。
- CI实际执行 `codesign --verify --strict` 成功；日志及包内signature.txt含 valid on disk / satisfies its Designated Requirement / Signature=adhoc。不是Linux本地codesign或分发签名。
- 证据：`artifacts/recovery-audit.json`、`ci-artifacts-41277007885.json`、`ci-41277007885.log`、`verification-41277007885.json`及runs.json。归档只含dylib、文档与检查日志，不含测试可执行/mock库。
- 全部网络经自己的本地tools/api.html标签及严格TLS桥；凭据仅环境引用，无-k、无密钥输出、无大型工具安装。

## 未验收边界

未执行TrollFools注入、微信宿主加载、真实收发/撤回/删除；未验证关闭恢复、切号、复用、后台更新/原地数组变更、折叠置顶与点击索引一致性及性能。源码/纯逻辑测试/签名通过不能代替iOS16.6、微信8.0.70真机兼容验收。AI、ActionBar/Dock、在线主题、红包详情、视频解析继续排除；不宣称全项目完成。

---

# 历史：2026-11-01 0.3.1 分组与手动工具栏：中断恢复交付

## 最新结论

**确切增量CI已成功，产物已下载并核验；不是全项目完成，未做微信宿主真机验收。** 前任务在提交严格编译修复与生命周期补丁后无文本结束，不代表构建失败。本轮只恢复查询、核对增量源码与成功产物、更新交付文档；没有重做实现、重跑成功构建、reset或重复发布。

- 仓库：`yuku00/LinkCard-Public`，独立分支：`wechat-unified/initial-20261101`。
- 远端分支头、release-state、Actions head_sha、artifact workflow_run.head_sha均为 `54e770622e4eff757685a424e35292d594fa3a8f`。
- CI：https://github.com/yuku00/LinkCard-Public/actions/runs/41274413299 ，实际 `completed / success`，编译及上传步骤成功。旧runs.json记录的68899e3b…失败已被本次实查更新，不能用旧记录判定新commit失败。
- GitHub产物：https://github.com/yuku00/LinkCard-Public/actions/runs/41274413299/artifacts/13070760778 （可能需要登录）。
- 相对0.3.0成功commit `9d09db169be76b49bca0b60c7585b3c318e3ffd3` 为2个快进commit、11条变更路径，全在发布白名单与wechat-unified/目录；未修改他项目或workflow，无强推。29项发布源码/测试/README/workflow与成功commit逐项Git blob一致；STATUS仅因本轮后补交付说明不同。本地旧HEAD和未提交成果完整保留。
- 使用自己的tools/api.html标签及现有环境凭据，原生严格TLS；无Key输出、无-k、未安装工具链。上传白名单不含原库、转储或凭据；本轮没有上传。

## 增量真实接入与功能边界

1. **官方添加的单个表情分组已编码并接入**：Core安装Groups，设置页可进入账号分组管理；Hook真实EmoticonBoardCrossCollectionEmoticonPageCell列表及窄生命周期，所有签名先检查。只有原列表含custom_emoticon_pid且全列表可解码MD5时才筛选；全部/未分组/自定义组、MD5移动、删组映射及账号原子配置有实际路径。未知结构/整包/最近使用保持原样，不写宿主列表、数据库或媒体。预览图选择、改名排序等未实现。
2. **关闭/切号保护有源码路径，不等于真机验收**：总开关关闭返回原列表；独立分组关闭筛选保留全部项，移除自有按钮；inset仅仍等于自有预期值时恢复，避免覆盖宿主后续修改。账号不明/切换使旧页失效，复用/章节切换清标识等待新列表；操作校验账号、代次、可见及前台条件。切号后即时刷新、布局与真实点击索引仍需宿主验证。
3. **手动工具栏已接入**：账号配置仅允许搜索/统计/设置，默认不选；聊天页头“工具”菜单只显示选择且签名可用动作，执行前重验账号、会话、代次及前台。关闭/不选移除自有工具按钮，保留宿主按钮；没有仓库/朋友圈/语音包/Dock假入口。注意原有独立统计按钮仍随总开关出现，独立搜索仍按旧开关；“默认不选”仅指新工具菜单，不意味着所有旧按钮都隐藏。
4. **首页电报分组仍未实现**：现有MainSessionMgr数组及计数证据不足以闭合原生session用户名、私信/其他分类及点击索引/置顶计数协议；没有修改首页数组、表头或手势，没有伪开关。默认全部/私信/群聊/其他及自定义分组需求仍保留。
5. 全部AI、ActionBar/系统键盘Dock、在线主题、红包详情、抖音/B站视频解析继续排除。其余既有未实现项以STATUS完整表为准，本轮不扩大范围。

## 构建与产物证据

- 实际CI：13项结构检查通过；GroupLogic 32条原生断言通过（筛选/占位/删组/隔离/校验/工具白名单）；MessageLogic 21条原生断言、主题ZIP原生测试、WUStats XCTest 18项/0失败均保留且通过。
- arm64 iOS dylib严格warnings-as-errors编译链接成功；平台记录IOS minos16.6 / SDK18.5；仅系统框架/库依赖，归档不含测试可执行或mock库。
- Artifact ID `13070760778`；ZIP `artifacts/WeChatUnified-41274413299.zip`，116552字节。
- ZIP SHA256 `3e36b74b19947fe46d315d3d9b2b699ac021d1bc18f1696ba61365112d52d1ee`，本地实算与GitHub digest一致。
- dylib `artifacts/run-41274413299/WeChatUnified.dylib`，287584字节。
- dylib SHA256 `35b07707c25f4bdfe5701ff235150a4ff9daa2f573ed37c8e56672e8ee80e581`，本地实算与CI SHA256SUMS一致；解析本地头确认64-bit arm64 MH_DYLIB。
- CI真实执行codesign --verify --strict成功；日志及归档signature.txt均为valid on disk / satisfies its Designated Requirement / Signature=adhoc。此处是核对CI签名证据，不是声称Linux本地运行了codesign，也不是开发者分发签名或兼容保证。
- 证据：`artifacts/ci-41274413299.log`、`ci-artifacts-41274413299.json`、`remote-audit-41274413299.json`、`runs.json`及成功归档。包内STATUS保留构建当时版本，本文与本地STATUS是核验后的说明，未额外发布。
- 未进行TrollFools注入、宿主加载、真实收发/撤回/删除、关闭恢复/切号/复用真机测试或性能验收。未重复旧产物核验及全项目逆向。

---

# 历史记录：2026-11-01 0.3.0 主题 / 日月 / 美化交付结果

## 最新结论（中断恢复后实查）

**成功构建、下载和核验；未做真机验收，不是全项目完成。** 恢复自己的本地 api.html 标签后，原有严格 TLS 传输桥正常，未更换凭据、未降级 TLS。此前 poll 工具中断不是最新 CI 编译失败；不需要重复发布已成功的源码。

- 仓库 `yuku00/LinkCard-Public`，独立分支 `wechat-unified/initial-20261101`。
- 实查远端分支头及成功 Actions head_sha 均为 `9d09db169be76b49bca0b60c7585b3c318e3ffd3`。
- CI：https://github.com/yuku00/LinkCard-Public/actions/runs/41270961089 ，`completed / success`；编译、上传均成功。
- 相对0.2.0交付 `6efc7696…` 为3个快进commit、13个变更路径，全部在 `wechat-unified/` 白名单，未改变其他项目或workflow。核验时全部26项发布白名单文件（包括workflow）本地Git blob哈希与远端逐一相等。随后仅更新本地本报告和STATUS交付说明，未再上传；包内STATUS是成功构建时版本。
- 本地git HEAD仍为 `cb0704e`，有保留的未提交/未跟踪成果；发布走受限GitHub API而非本地git push，不能以本地HEAD误判远端版本。本次没有reset、清理或重写源码。

## 本轮实际新增与完整链核查

- 本地PNG/ZIP导入：系统文件选择、有界ZIP32 stored/deflate与CRC、路径/链接/重叠/尺寸检查、PNG解码校验、自有UUID目录事务发布、预览/名称排序/删除确认均有实际源码链。
- 主题与气泡独立选择已接配置和资源读取；共5个资源Hook（3个MMThemeManager实例方法、2个UIImage类方法），先取原IMP，缺图或不可用回原图。缓存含尺寸、scale、明暗、拉伸帽及渲染模式；内存警告清缓存。关闭/配置变化清缓存并恢复可见标准UIImageView及UIButton已映射原图。
- 日月外观限整合设置与NewSettingViewController；绘制太阳/云/月/星，点按/拖动只在值变化时对原UISwitch发送一次ValueChanged，取消零发送；保留原业务target及可访问性，关闭移除外观和附加target。不是微信明暗模式切换。
- 美化实际接入搜索栏、消息引用、聊天时间标签、首页右上角加号菜单、Toast、首页左滑菜单；原布局先行，保存/恢复背景、裁剪及圆角。
- 缺口：完整资源别名、BubbleInfo显式暗色上下文、宿主自有缓存/自绘视图即时热刷新未实现，可能要重新进入页面；SVG/CAR/XML/CSS不渲染；表情/文件专项、发送/发表按钮、完整弹窗、聊天附件加号、左滑首尾精细几何未实现。日月未复刻弹簧参数。本轮未引入AI、ActionBar/Dock、红包详情、在线主题、视频解析。

## 编译、测试和产物证据

- Xcode16.4 / iPhoneOS SDK18.5，arm64、最低iOS16.6，warnings-as-errors编译链接成功。
- 本地重新运行11项结构检查全部通过；成功CI同样11项通过。MessageLogic原生21断言、主题ZIP原生测试（stored/deflate、UTF-8、路径、符号链接、CRC、边界/截断/名称/大小）、WUStats XCTest18项/0失败均见实际日志。没有删除原生测试。
- 前两次主题CI真实失败分别为发布脚本存在性假设（41270666249）与 `Style` 冲突系统MacTypes符号（41270798221）；原代理已修为仅在发布脚本存在时检查白名单，以及使用 `WUStyleSurface`。最新成功版本仍保留主题原生测试与源码存在/构建接入检查。
- Artifact ID `13069043195`；ZIP `artifacts/WeChatUnified-41270961089.zip`，99433字节。
- ZIP SHA256 `0351b60196564c02f9df7f10e220bda42aeeaa9ebfb6ed9c47b41ad8efa56b89`，实算匹配GitHub digest。
- dylib `artifacts/run-41270961089/WeChatUnified.dylib`，253168字节。
- dylib SHA256 `d09793940b72c18d9d57945aec0c53935a170372cbb582124494e7a54bc5449b`，实算匹配CI SHA256SUMS。
- 本地解析Mach-O头确认64-bit arm64 / MH_DYLIB。CI日志与归档signature.txt均记录 `valid on disk`、`satisfies its Designated Requirement`、`Signature=adhoc`。平台日志为IOS minos16.6/sdk18.5；依赖仅系统框架/库。归档无测试可执行或mock库。
- 证据：`artifacts/ci-41270961089.log`、`artifacts/ci-artifacts-41270961089.json`、`artifacts/remote-audit-41270961089.json`、`artifacts/runs.json`。
- 仍未执行目标微信加载、TrollFools注入、真实开关回退/复用/切号/性能验收。源码检查、macOS原生测试、ad-hoc签名均不能替代宿主真机验证。

---

# 历史记录：0.2.0 消息交互增量


## 当前结论

0.2.0消息交互增量已实际编码、集成、上传、编译并下载核验。**这是全项目的开发增量，不是全清单完成；没有执行真实宿主、发消息、撤回/删除消息或领取红包。**

- 仓库：yuku00/LinkCard-Public
- 独立分支：wechat-unified/initial-20261101
- 最终commit：`6efc7696e1e87dfa5ff26f17bfeb3edd094d3d30`
- 最终Actions：https://github.com/yuku00/LinkCard-Public/actions/runs/41269652364
- 结论：completed / success，head_sha与上述commit一致。
- 发布审计：相对上一交付6197cfc…新增3个快进commit，实际变更15个路径，全部位于wechat-unified/白名单；未修改其他项目、未强推、未发布原库/转储/用户数据/密钥。workflow原有隔离配置未改变。

## 本轮实际功能diff

1. 当前会话搜索：聊天页头追加按钮，调用经签名检查的宿主onSearchItem；不是设置页手动链接搜索，不保存搜索历史。
2. 回拨确认：只拦通话消息onClicked；冻结账号、会话、cell/wrap、消息身份及通话内容，确认后原IMP只调用一次；取消、关闭、复用、离页、后台或代次改变均取消。
3. 防撤回：严格XML、ID、会话与真实发送者检查，保留已收到的他人本地消息；自己的撤回放行；无提示插入、无恢复未收到内容的承诺。
4. 多选撤回：独立“撤回所选”入口，读取宿主选择集；仅自身有效120秒内消息，长/短宿主撤回接口签名核验后二选一，逐条已请求/跳过/未知；绝不DelMsg、不替换宿主最后一个按钮、不自动重试。
5. WCRefine语义表情复读部分：仅47型表情，25×25图片按钮、透明度1、圆角6；确认后新建并重置消息对象，仅一次AddEmoticonMsg，没有通用AddMsg/HBHelper回退。
6. 消息合并显示：群/私聊开关、同发送者相邻分组、时间/系统节点断组、头像置底；只影响头像/名称显示，复用、布局和停用恢复，不改消息ID/正文/数据库。
7. 红包提醒部分：宿主入站处理后识别红包，前台按会话显示名提醒，账号/会话/服务器ID有界去重；已加载同会话cell可定位；不自动领取、不查询金额/人数。
8. 非AI统计：合入并行代理源码后，已补真实生产binding，不是不可用菜单。接当前账号/会话/generation、CMessageMgr、wrap解码及静态证据0/0起始游标。先独立核对对象/32位参数及输出指针语义，再钉住实际encoding；200条/页、20000上限、无推进停止；最终排序/热词/汇总转后台不可变快照。当前会话总数/类型、时间分布、发言榜、回复/开场/破冰/连发/热词等有实际读取链。

## 编译与测试

- Xcode 16.4 / iPhoneOS SDK 18.5，arm64，最低iOS16.6，warnings-as-errors编译链接成功。
- 9项本地/CI结构防护通过：针对非预期删除、排除功能、密钥、重复Hook等；不再全局禁止AddMsg一类需求接口。
- MessageLogic真实macOS原生可执行测试：21个断言通过（XML/ID、身份、撤回窗口、相邻分组）。
- WUStats真实独立XCTest bundle：18项通过、0失败；含分页、去重、群时间差、DST、取消、切号、错误签名、零游标启动、后台汇总取消。mock CMessageMgr只在测试bundle，不进入dylib。
- 首轮CI 41269020855失败于原生XCTest宏数组逗号拆参；已实际修复并增加异步等待，未删测试。
- 第二轮41269321941已成功；最后加入确认弹窗生命周期、红包前台覆盖和两项回归后，41269652364再次成功。
- ad-hoc签名及codesign --verify --strict通过；不等于开发者分发签名或真机兼容验收。

## 已下载并核验的产物

- Artifact ID：13068144002
- ZIP：`artifacts/WeChatUnified-41269652364.zip`，76533字节。
- ZIP SHA256：`ad6980f4b1dcbb9abf59602e3c7bb7adff893a76afb28d523b6a601692ad7865`，与GitHub digest相等。
- dylib：`artifacts/run-41269652364/WeChatUnified.dylib`，215552字节。
- dylib SHA256：`0a3c8923c5f7930d6fbdf293d2b5e9bc797ad349b9f3328bb676a61714ed43db`，与CI SHA256SUMS一致。
- 本地Mach-O头核验64-bit arm64 / MH_DYLIB；平台日志IOS minos16.6；依赖仅系统框架及系统库。归档没有测试可执行/mock库。
- 日志：`artifacts/ci-41269652364.log`；远端路径审计：`artifacts/remote-audit-41269652364.json`。
- 全程本地api.html原生严格TLS桥，凭据仅环境变量；未安装大型工具链。

## 明确未完成及下一步

- 拍一拍发送前确认：sendPat:已证为同步BOOL；缺安全冻结目标的发送前UI动作协议，不能靠返回假成功或异步重放补齐。未实现，无开关。
- 表情复读：长按下载、用户主题图标、持久崩溃操作账本未实现；不能称完整WCRefine语义，也不保证跨重启恰好一次。
- 红包提醒：跨会话导航、未加载消息定位、系统后台通知未实现。
- 统计：全账号排行/访问榜、共同群/画像、App消息补页及完整历程等未完成；普通消息分页不能冒充全部历史或全部统计。
- 便捷朋友圈半屏+rp、伪集赞本地、激励广告与一般去广告等仍完整保留在STATUS，本轮未擅自删改这些模块。
- 目标微信完整构建号、TrollFools加载、开关回退实效、服务端撤回/送达、真实统计页语义及性能仍需隔离设备验收。CI通过不能替代这些检查。

主工程所有修改已持久落盘；实现接口依据与专项交接另记于workspace/wechat-unified/implementation-message-20261101.md。

## 0.3.0 中断恢复即时核验（2026-11-01）
已重建自己的本地 api.html 标签并恢复严格 TLS 查询。远端独立分支头为 `9d09db169be76b49bca0b60c7585b3c318e3ffd3`；对应 Actions `41270961089` 实际 completed/success，编译和上传步骤成功。此前 poll 中断不是本次编译失败。Artifact `13069043195`，99433 字节。正在核对下载内容和本轮源码；旧版0.2.0报告保留为历史，不代表最新产物。未进行真机验收。

## 最新：美化增量 CI 修复交付（2026-11-01）
- commit `8f7148897e63baa07108a90e8f933644ef3b1a53`；run `41300366511` / job `124829847490`：completed/success；artifact `13080254890`。本轮一次构建成功。
- 已修旧 run 41299546175 的 `Sources/WU.h:24–25 unknown type name 'UIView'`：Foundation-only Ads hook 测试缺前向声明。仅发布已有 WU.h 声明、Appearance.m 自有图层恢复/可见性增量，移除未使用变量；测试不删改，本地 27/27 通过，CI 原生测试通过。
- 下载 `artifacts/WeChatUnified-41300366511.zip`（365672 字节），SHA256 `60e46b5cae1c8191a4a0f9ab896ac3a47e74b9ca7aae554a952b1e92d9ba8467`，与 GitHub digest 一致。
- 产物 `artifacts/run-41300366511/WeChatUnified.dylib`（698736 字节），SHA256 `f10e7339074818eb4faf158e40c85430e2eb9c9866ece64c74a6c7d4973ee981`，已核对 SHA256SUMS、arm64 MH_DYLIB、CI 严格 ad-hoc 签名验证及本地 165 页 CodeDirectory 哈希。
- 补记前 332/332 发布文件与远端一致。本段和 RECOVERY-NOTE 为成功后本地记录，不触发额外 CI；无 reset/强推/跨项目修改。
- 未扩功能：保持输入呼吸灯、文件/表情卡片、首页 header 隐藏；键盘发送按钮未做。未接触真实微信/用户数据、未执行真实发删、未作真机验收。
