# 当前统一构建结果

**当前工程检查点，不是全部需求最终交付；没有真实微信/真机验收。**

## 已验证版本
- 仓库 `yuku00/LinkCard-Public`，分支 `wechat-unified/initial-20261101`。
- commit `2ee2d042db7e206de1e5200bd072c102e6eabee6`。
- [CI41332322097](https://github.com/yuku00/LinkCard-Public/actions/runs/41332322097)，job124924826521，completed/success；本次首次CI通过。
- 428项发布路径与该提交一致；源码包只含自主实现、许可依赖、合成测试与构建脚本，没有原插件、反编译转储或真实用户数据。

## 本次新增与实际测试
在上一统一基线ecaa450上合入所选消息链接、复读图标/Files导出、缓存静图→宿主原生表情编辑入口；保留此前主题、统计/媒体、原生行为、收纳和分组等所有代码与测试。

- 29项原结构回归；链接/复读6项接线回归；图片入口8项接线回归。
- 新Foundation生产链接解析/风险包装拒绝/配置与工具动作测试实际执行通过。
- 完整图片入口生产模块使用真实Foundation/ImageIO、UIKit桩，六模式实际通过：normal324断言，missing15、wrong-class16、bad-init17、bad-setter17、missing-setter16。断言数量不等于独立场景数。
- 主会话合并时保留两组工具动作，修复旧结构断言错误地要求messageLinks必须排最后；没有删除断言覆盖。图片导航后允许宿主清空多选，但确认前仍严格检查；新增实际mock覆盖清空选择及确认前失效。用户图标存储/读取只规范化系统提供的根别名，自有子目录仍拒绝链接。
- 37统计XCTest与此前全部原生/文件事务/codec/ABI/P0/启动恢复回归通过。
- iOS arm64/min16.6/SDK18.5真实编译链接，严格ad-hoc签名验证成功。
- 真实iOS模拟器4项SurfaceStyle UIKit XCTest通过，xcresult逐方法核验；这是样式应用与恢复测试，不是新Safari/Files路径或微信宿主测试。

## 已取回
- Artifact13093638069；`artifacts/WeChatUnified-41332322097.zip`，621760字节。
- ZIP SHA256 `3ee55b7b0bafc819b54a5026d7a9652e2d2a9823a8ebc36ac87efefa2cc2d74e`，与GitHub digest一致；CRC通过。
- `artifacts/run-41332322097/WeChatUnified.dylib`，1223696字节。
- dylib SHA256 `b1c64ed43ea5472d699f27c6ed2a48916a60ba4ba2b0e759883fa724231df474`，与包内清单一致；本地解析arm64 MH_DYLIB。
- 当前源码包 `artifacts/WeChatUnified-current-source-2ee2d04.zip`；SHA256 `0d3ca222f3a85a07be75383cf6e0d43f81faae5a7bf969b6824a8ef210b04bc3`，428项文件及SOURCE-MANIFEST固定为该远端提交，仍非全部需求源码。
- 详细证据：`artifacts/verification-41332322097.json`、`artifacts/entries-ci-41332322097.log`。

## 实际范围与待办
- 链接是用户选中消息的手动入口，未自动改写全部气泡/文章点击；风险包装只有唯一明确HTTP(S)目标时才提取。内置Safari与系统默认浏览器明确区分。
- 复读常规发送保持原唯一提交器；本批补图标/子设置/标签长按Files下载，不扩未开启的菜单/文件类型。
- 图片仅选中的已缓存静态PNG/JPEG，可能非原图。用户确认后进入宿主原生编辑器；没有调用上传后端或宣称已入库。公众号入口、动画图入库仍未实现。
- 评论/画像及剩余native准确语义仍在独立批次推进，当前CI不能覆盖未合入代码。所有真实宿主兼容性仍需目标版本验证。

## 历史与工具
上一统一版本ecaa450 / CI41326249974及其真实失败根因修复记录已保存`artifacts/history/BUILD-ecaa450.md`；更早历史也保留，不再混作当前完成度。
发布/下载采用已验证的Python系统严格TLS；Authorization不随重定向转发，HTTPS-only及仓库范围有无网络测试。没有再启动Ghidra、上传原样本或改变main工具工作流。此次结果补记只在本地，不为文档再触发CI，源码包保留构建时文案。
