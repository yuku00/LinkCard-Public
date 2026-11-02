# 宿主样式证据与限制（2026-11-02）

- 现有 `WeToast.h` / `MMToastView.h` / `MMTipsViewController.h` 来自 Huangbai233/WeChatHeaders，固定提交 `014c32f794165acf9006cf0f6bbac0bae34dd8b2` 的 `8.0.54/` 公开声明；它们不是目标微信的运行时证明。
- `WeToast.h` 的 `@interface WeToast` **没有输出父类**。不能从该文件声称已证实它继承 UIViewController，也不能据此认定不继承。现有运行时 `isSubclassOfClass:UIViewController.class`、响应链所有者和 `toastView` 同一对象检查保留；不猜测另一种所有权路径。
- 已读取公开固定声明 https://github.com/FreeMind-LJ/WeChatHeaders/blob/bf464751f1927d4f55b54601ad44baca54b51c42/headers/EnterpriseMsgContentViewController.h ，明确写有 `@interface EnterpriseMsgContentViewController : BaseMsgContentViewController`。因此仅将聊天上下文精确类相等改为 BaseMsgContentViewController 的 isKindOfClass；首页仍精确匹配 NewMainFrameViewController。其余所有权、可见窗口、无 presentedViewController、非 loading/block/custom/icon 和真实背景后代限制不变。
- 文本引用、文本预览、快速回复已有 getter 签名/类型/后代所有权限定，本次未发现足够证据可放宽其条件。
- 下一步必须在目标版本观察 WeToast 实际父类、响应链、topViewControllerInMainWindow 返回值和背景层级；当前公开声明不足以证明这条路径在目标微信可达，编译和配置落盘通过不替代该验证。
