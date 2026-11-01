# 当前统一构建结果

**这是当前工程检查点，不是全部需求最终交付。未执行真实微信/真机验收。**

## 实际成功版本
- 仓库：`yuku00/LinkCard-Public`；分支：`wechat-unified/initial-20261101`。
- commit：`ecaa450336a4c4277b528a57557bdc962efc23fa`。
- [Actions 41326249974](https://github.com/yuku00/LinkCard-Public/actions/runs/41326249974)，job124906685225，completed/success。
- 发布与补记之间核对412/412白名单文件与远端Git blob一致。只发布自主工程、许可依赖与合成测试；未上传原插件/私有反编译输出/用户数据。

## 真实执行的验证
- iOS arm64全部生产源SDK语法检查、完整编译链接、严格ad-hoc codesign验证通过；最低iOS16.6，SDK18.5。
- 主题目录/追加/资源规则/字面色表/ZIP和原子目录事务原生测试通过。
- 生产拍前确认、游戏选择、局部保持键盘、真实Core Hook、异常/取消/重入/克隆身份，以及独立启动守卫的原生UIKit mock测试通过；32/64位正常与真正错误ABI分别编译验证。
- 配置生产保存/重载45检查；单一i/I/q/Q消息构造器复读与语音/包共存回归；既有解码、消息、广告、草稿、分组、回收等旧回归保留通过。
- 新媒体/视频恢复工厂、语音文件交换和评论规范化存储的生产mock/文件事务测试通过。
- 统计XCTest实际37项（原31+新增6），0失败。
- **真实iOS模拟器UIKit XCTest 4/4通过**，从xcresult逐方法验证，没有把本机自检、跳过或编译通过当UIKit运行。覆盖真实属性应用/禁用恢复、宿主新值不被覆盖、主题色与显式样式优先级、重复布局基线不丢失。不是微信真机测试。
- 原生mock不是宿主业务协议证明；完整功能范围见唯一当前`STATUS.md`，不以断言数代替场景覆盖。

## 下载与版本核验
- Artifact13091996177，`artifacts/WeChatUnified-41326249974.zip`，584844字节。
- ZIP SHA256：`542763b30c84d442dcdb3de0b5ea996f2b75b4de47f952ecf091f4bce37fe064`，与GitHub digest一致；ZIP CRC通过。
- dylib：`artifacts/run-41326249974/WeChatUnified.dylib`，1138976字节。
- dylib SHA256：`fc761cb30b21317059ed0f7c391ff50f7f4d994398dc434582504edae31f4bc3`，匹配包内清单；本地解析arm64 MH_DYLIB。
- 对应源码检查点：`artifacts/WeChatUnified-current-source-ecaa450.zip`；SHA256 `fcefe4dee9afd8d73b2bfd13dacad157aeccb42b4372e55068f2384b14777577`。包含412个准确发布路径和SOURCE-MANIFEST，不得称完整需求源码。
- 证据：`artifacts/verification-41326249974.json`、`source-manifest-ecaa450.json`、`completion-ci-41326249974.log`；包内`uikit-verified-tests.json`记录实际四方法成功。

## 本批真实失败及根因修复
1. ThemeCatalog的id.pathExtension编译类型错误，改为已验证NSString键。
2. SurfaceStyle的font选择子与CoreText CFTypeRef歧义，改为类型明确的UIKit文本协议。
3. 评论生产/测试函数名与macOS Carbon Comment类型冲突，改为带前缀名称。
4. NativeSettings中断留下重复尾部、未使用weakAlert，修复语法并用弱引用避免捕获循环。
5. 启动守卫C源码的严格POSIX宏隐藏Darwin O_NOFOLLOW/mkdtemp，显式启用Darwin声明，未删文件安全校验。
6. 错误ABI夹具误以为class_replaceMethod能改已有类型编码；改为独立编译真正错误声明，先断言其编码确实不同，再执行原拒绝测试。未放宽生产门控。

## 开发工具与历史
浏览器进程暂停阻塞发布后，已实际验证Python系统TLS直接认证200；`tools/github_native.py`现在用严格证书/主机校验，限制目标仓库，Authorization不随重定向转发，HTTPS-only跳转有无网络回归。不再要求常驻浏览器，不打印token。不触碰Ghidra工作流，Ghidra仍仅手动、仅已授权自制样本。

旧长篇状态/构建历史已存本地`artifacts/history/`，不再混入当前完成度。本文件和STATUS属于成功后本地补记，未为文档重复构建；相应已发布源码包保留构建时文案。当前尚有三组独立补齐任务，未完项不能冒充最终验收。
