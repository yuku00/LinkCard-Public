# 苹果备忘录导出：开源接入与边界

## 2026-11-01 实质检索结论

GitHub repository search 已查询 `Apple Notes export TrollStore`、`Apple Notes export TrollStore language:Objective-C`、`notes exporter ios language:Swift`、`apple notes export ios jailbreak`、`apple notes exporter language:Swift` 和 `notesutils`，随后读取以下项目自己的 README、许可证、协议及实现源码。

- [Bascter-Main/NotesExporter](https://github.com/Bascter-Main/NotesExporter/tree/2c539be3f2b725d4038a8a74460848e214b558ac)：确有原生 Objective-C/Theos 源码，但属于 TrollFools 注入 Notes 进程的 dylib，README 主要针对 iOS 17.0，不是本工程独立 iOS 16.6 SwiftUI 应用。该修订无 LICENSE，GitHub license 字段为 null；公开可见不代表获准复制分发，因此没有复制其代码或二进制。
- [kzaremski/apple-notes-exporter](https://github.com/kzaremski/apple-notes-exporter)：Swift macOS 11+ 应用，GPL-3.0，不可当作现有 MIT iOS 工程的即插即用依赖；本次没有移植其代码。
- [dunhamsteve/notesutils](https://github.com/dunhamsteve/notesutils)：Python 3 Notes 导出脚本，Unlicense/public domain，不是 iOS 原生项目。可作为格式研究补充，但未另引入 Python 运行时。
- **采用** [threeplanetssoftware/apple_cloud_notes_parser](https://github.com/threeplanetssoftware/apple_cloud_notes_parser/tree/4754a2b62686570cca46690d101079e80cf6ae66)，MIT，Copyright (c) 2019 Three Planets Software。固定修订下的 [proto/notestore.proto](https://github.com/threeplanetssoftware/apple_cloud_notes_parser/blob/4754a2b62686570cca46690d101079e80cf6ae66/proto/notestore.proto)、[AppleNote.rb](https://github.com/threeplanetssoftware/apple_cloud_notes_parser/blob/4754a2b62686570cca46690d101079e80cf6ae66/lib/AppleNote.rb) 和 [AppleNoteStore.rb](https://github.com/threeplanetssoftware/apple_cloud_notes_parser/blob/4754a2b62686570cca46690d101079e80cf6ae66/lib/AppleNoteStore.rb) 提供 gzip → protobuf → document.note.note_text 的映射和关系表字段。保留完整协议参考副本、MIT 授权与 NOTICE，并打包进 App。仅移植正文格式映射；没有运行或照搬 Ruby 工具的数据库写入、解密或完整附件框架。

## 实现路径

1. 用户点「读取 Apple Notes」并确认后，在后台枚举 `/var/mobile/Containers/Shared/AppGroup` 的容器元数据，仅匹配 `MCMMetadataIdentifier = group.com.apple.notes`，不硬编码 UUID、不扫描其他容器内容。拒绝重复候选、符号链接、非普通数据库。
2. 使用 `SQLITE_OPEN_READONLY` 打开 `NoteStore.sqlite`；读取事务固定视图，SQLite backup API 复制到 `:memory:`，完成后只查询内存快照。没有复制/分别拼接 sqlite、wal、shm，没有 immutable=1，没有 checkpoint 或原库写入 SQL。SQLite 的 WAL 共享内存协调仍由系统库完成，不承诺 shm 字节完全不变。参考 [SQLite Backup](https://www.sqlite.org/backup.html)、[WAL read-only](https://www.sqlite.org/wal.html#read_only_databases)。权限/WAL 不可读或 backup busy/超时即失败，不继续导出残缺快照。
3. 检查表与必需字段，`ZICNOTEDATA.ZNOTE = ZICCLOUDSYNCINGOBJECT.Z_PK` 联表；保护标记或已知加密字段存在时跳过，删除标记跳过。gzip 校验和/流完整性、解压大小、protobuf varint/长度边界及 UTF-8 均检查；路径为字段 2 → 3 → 2，绝不拿标题/snippet 伪造正文。
4. 批量文本进入现有原生卡片列表，可搜索、多选并导出 TXT/MD；新增清除内存入口。读取失败保留旧批次，成功替换。显示锁定、删除、未下载、解析失败和含嵌入对象占位符计数。原有 UTF-8 文件导入保留。

## 明确限制

只面向 iOS 16 常规、未锁定、已有本地 ZICNOTEDATA 记录的正文；尚未进行 iOS 16.6 真机验证。完全没有本地正文行的云端项目不在联表结果中，也不计入未下载数，不声称已扫描全部云端笔记。未下载计数仅覆盖现有行的空 ZDATA。未知结构 fail closed。

锁定笔记不解锁、不导出；不下载附件、不重建表格、图片、扫描件、手写、富文本、账户/文件夹层次、共享权限或历史版本。U+FFFC 嵌入对象占位符保留，不伪造附件文字；MD 只是文本文件格式，不是富文本转换。没有 Share Extension 或恢复能力，不是全库备份。

内存快照上限 128 MiB（实际进程开销更高）；单篇压缩和解压分别最多 2 MiB；批次正文最多 16 MiB / 1000 篇，最多处理 10000 行，超限明确标记。SQLite backup 单轮总体目标 10 秒，busy timeout 250ms。无磁盘临时数据库、无网络请求、无数据日志。退出后需重新读取；用户自行选择 iCloud 导出位置仍可能触发系统同步。元数据/文件检查不承诺防恶意并发换链攻击，应在受信任设备使用。

## 测试与编译状态

`Tests/AppleNotesTests.swift` 使用自行生成的虚构 Unicode/gzip/protobuf 和临时 WAL 数据库，测试正文、损坏数据、锁定/删除/未下载过滤、原 DB/WAL 不变、容器识别与符号链接拒绝、缺失保护字段拒绝。没有使用上游或用户真实备忘录样本。

本机只能运行 Python 静态/合成检查；`Tools/test_notes_format.py` 检验合成压缩/协议样本并直接提取 Swift SELECT 在合成 SQLite WAL 数据上运行。它不是 Swift 执行。新增 XCTest 尚未编译执行，真机权限尚未验证。project.yml 已链接系统 SQLite/zlib、打包第三方许可；workflow 已接线静态检查、合成检查、模拟器 XCTest 和设备构建。没有 Xcode/Swift、没有 git remote/gh 认证，因此本轮没有 IPA、没有成功构建结果。

下一步需要可用 macOS/Xcode，或用户指定有权限的 GitHub 仓库；不要自动创建公开仓库或上传。先通过编译/XCTest，再在可丢弃 iOS 16.6 测试笔记上核对内容与权限。WebClip 删除功能仍不可用。
