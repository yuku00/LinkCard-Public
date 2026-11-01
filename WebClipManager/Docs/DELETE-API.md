# 删除接口证据与启用门槛

本次仅 GET 读取公开头文件；未上传任何内容，未读取用户既有归档。

## 已实际读取

1. https://raw.githubusercontent.com/nst/iOS-Runtime-Headers/master/PrivateFrameworks/UIKitCore.framework/UIWebClip.h
   - RuntimeBrowser 生成头文件，声明 `@interface UIWebClip : NSObject`、`+webClipWithIdentifier:`、`- (bool)removeFromDisk`、`-requestIconUpdateInSpringBoard`。
   - 仓库 master 是移动引用，页面不能作为 iOS 16.6 版本证据。仅证实该公开转储存在这些声明。
2. https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/main/PrivateFrameworks/UIKitCore.framework/UIWebClip.h
   - 同样看到 `UIWebClip` 和 `- (bool)removeFromDisk` 声明。
   - 仓库名指向 iOS 17，不是 iOS 16.6；无实现体，不能推出清理语义。

## 未取得证据

- 尝试 MTACS/iOS-16.4-Runtime-Headers 对应 UIWebClip 路径返回 404，不能据此推断系统没有此类。
- 尝试 `https://developer.limneos.net/?ios=16.3&framework=UIKitCore.framework&header=UIWebClip.h`，未得到可提取的目标头文件文本，不能用作核实证据。
- 没有 iOS 16.6 runtime 导出、反汇编实现、SpringBoard 删除调用链、服务鉴权要求或本机测试。没有证明 `removeFromDisk` 会删除主屏幕注册、独立数据与关联缓存，或遵循描述文件管理约束。

## 当前决定

不导入/链接私有框架、不动态调用 selector。诊断页面仅通过 `NSClassFromString`、`class_getInstanceMethod`、`class_getClassMethod` 检查元数据；不实例化 UIWebClip、不执行 selector、不获取实现指针。Repository.delete 对每个标识返回拒绝原因。代码不存在删除目标目录、发 Darwin 通知、重启 SpringBoard 或清 Safari 数据的后备路径。界面明确显示“不可用”，不存在成功删除计数。

未来仅拿到头文件或 selector 可响应还不够：需要 16.6 的实际删除路径、调用进程/权限与错误语义证据，并在可丢弃真机验证图标、注册、单独数据及失败场景。应尊重 RemovalDisallowed 与配置描述文件管理权限。系统共享 Safari 数据不能作为所谓“清理残留”批量清除。
