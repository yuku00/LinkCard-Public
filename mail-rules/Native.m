#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/sysctl.h>
#import "NativeCore.h"
#import "Theme.h"
#import "Trace.h"

static NSString *const Domain=@"dev.mailrules.native5";
static char StateKey, CreateKey, MoveKey, StartedKey, DiagnosticGuardKey;
static BOOL Supported;

static __thread id ReloadOwner;
static __thread NSDictionary *ReloadFrame;
static BOOL Ready, MoveReady, CreateReady;
static BOOL ABI(id o,NSString *name,const char *type) {
    Method m=class_getInstanceMethod(object_getClass(o),NSSelectorFromString(name));
    BOOL ok=m && !strcmp(method_getTypeEncoding(m),type);
    if(!ok) MRD(@"abi",@"failed",m?@"abi_mismatch":@"method_missing",o,MRDABIFields(name,type,m?method_getTypeEncoding(m):NULL));
    return ok;
}
static id Get(id o,NSString *name) {
    return ABI(o,name,"@16@0:8")?((id(*)(id,SEL))objc_msgSend)(o,NSSelectorFromString(name)):nil;
}
static BOOL Flag(id o,NSString *name) {
    return ABI(o,name,"B16@0:8") && ((BOOL(*)(id,SEL))objc_msgSend)(o,NSSelectorFromString(name));
}
static id One(id o,NSString *name,id arg) {
    return ABI(o,name,"@24@0:8@16")?((id(*)(id,SEL,id))objc_msgSend)(o,NSSelectorFromString(name),arg):nil;
}
static BOOL Set(id o,NSString *name,id arg) {
    if(!ABI(o,name,"v24@0:8@16")) return NO;
    ((void(*)(id,SEL,id))objc_msgSend)(o,NSSelectorFromString(name),arg); return YES;
}
static void Void(id o,NSString *name) {
    if(ABI(o,name,"v16@0:8")) ((void(*)(id,SEL))objc_msgSend)(o,NSSelectorFromString(name));
}
static NSArray *Array(id value) {
    return [value isKindOfClass:NSArray.class]?value:([value isKindOfClass:NSSet.class]?[value allObjects]:@[]);
}
static NSString *Identity(id x) {
    if(![x isKindOfClass:NSClassFromString(@"EMObjectID")] || !ABI(x,@"isEphemeral","B16@0:8") || Flag(x,@"isEphemeral")) return nil;
    return MR5Identity(Get(x,@"serializedRepresentation"));
}
static NSString *BoxID(id box) { return Identity(Get(box,@"objectID")); }
static NSString *AccountID(id box) {
    if(![box isKindOfClass:NSClassFromString(@"EMMailbox")] || !ABI(box,@"isSmartMailbox","B16@0:8") || Flag(box,@"isSmartMailbox")) return nil;
    return Identity(Get(box,@"accountIdentifier"));
}
static NSArray *Boxes(id owner) { return Array(Get(owner,@"mailboxes")); }
static NSArray *BoxKeys(id owner) {
    NSMutableArray *keys=[NSMutableArray array];
    NSMutableDictionary *accounts=[NSMutableDictionary dictionary];
    for(id box in Boxes(owner)) {
        NSString *a=AccountID(box),*b=BoxID(box);
        if(!a || !b || (accounts[b] && ![accounts[b] isEqual:a])) {MRD(@"scope.resolve",@"failed",@"scope_invalid",owner,@{@"accountID":MRDAccount(a)});return @[];}
        MRD(@"scope.resolve",@"success",@"ok",box,@{@"accountID":MRDAccount(a)});
        accounts[b]=a;
        [keys addObject:@[a,b]];
    }
    if(!keys.count)MRD(@"scope.resolve",@"skipped",@"no_items",owner,nil);
    return keys;
}
static NSMutableDictionary *Load(void) {
    CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("configuration"),(CFStringRef)Domain);
    NSMutableDictionary *d=[raw && [(id)raw isKindOfClass:NSDictionary.class]?(id)raw:@{@"enabled":@NO,@"rules":@[]} mutableCopy];
    if(raw) CFRelease(raw); return [d autorelease];
}
static BOOL Save(NSDictionary *d) {
    CFPreferencesSetAppValue(CFSTR("configuration"),(CFPropertyListRef)d,(CFStringRef)Domain);
    BOOL synced=CFPreferencesAppSynchronize((CFStringRef)Domain);
    BOOL equal=[Load() isEqual:d];
    MRD(@"rule.save",synced&&equal?@"success":@"failed",!synced?@"sync_failed":(!equal?@"readback_mismatch":@"ok"),nil,@{@"saved":@(synced),@"enabled":@([d[@"enabled"] boolValue]),@"count":@([d[@"rules"] count])});
    return synced && equal;
}
static id Address(NSString *s) { return One(NSClassFromString(@"ECEmailAddress"),@"emailAddressWithString:",s); }
static NSString *ReadAddress(id x) {
    if([x isKindOfClass:NSString.class]) return MR5Address(x);
    id address=Get(x,@"emailAddressValue");
    return MR5Address(Get(address?:x,@"stringValue"));
}
static NSPredicate *Sender(NSString *s) {
    s=MR5Address(s); if(!s) {MRD(@"sender.selftest",@"failed",@"invalid_input",nil,nil);return nil;}
    static NSMutableDictionary *cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSMutableDictionary new];});
    @synchronized(cache) {
        id saved=cache[s];if(saved) {if(saved!=NSNull.null)MRDAST(saved);MRD(@"sender.selftest",saved==NSNull.null?@"failed":@"success",@"cache",nil,nil);return saved==NSNull.null?nil:saved;}
        for(NSUInteger mode=0;mode<2;mode++) {
            @try {
                id arg=mode?Address(s):(id)s;if(!arg) continue;
                NSPredicate *p=One(NSClassFromString(@"EMMessageListItemPredicates"),@"predicateForMessagesWithSender:",arg);
                MRD(@"sender.factory",p?@"success":@"failed",mode?@"address_arg":@"string_arg",p,nil);MRDAST(p);
                if(MR5SenderContract(p,s,^id(NSString *value){return Address(value);},^id(NSArray *senders){
                    id model=[[[NSClassFromString(@"EMMessage") alloc] init] autorelease];
                    return Set(model,@"setSenderList:",senders)?model:nil;
                })) {MRD(@"sender.selftest",@"success",@"ok",p,nil);cache[s]=p;return p;}
                MRD(@"sender.selftest",@"failed",@"model_contract",p,nil);
            } @catch(__unused NSException *e) {MRD(@"sender.selftest",@"failed",@"exception",nil,nil);}
        }
        cache[s]=NSNull.null;return nil;
    }
}
static NSPredicate *InBoxes(NSArray *boxes) {
    id p=One(NSClassFromString(@"EMMessageListItemPredicates"),@"predicateForMessagesInMailboxes:",boxes);
    return [p isKindOfClass:NSPredicate.class]?p:nil;
}
static UIAlertAction *MRDAction(NSString *title,UIAlertActionStyle style,void (^handler)(UIAlertAction *)) {
    // Never record the title: rule/account picker titles contain private values.
    NSDictionary *codes=@{@"诊断会话（手动开始 / 停止）":@"diagnostics",@"开始诊断（新一轮，清空旧记录）":@"start",@"停止并查看 / 分享":@"stop",@"查看上轮报告 / 分享":@"report",@"清空诊断内存":@"clear",@"从选中邮件的发件人添加":@"selected_sender",@"输入发件人添加规则":@"input_sender",@"管理规则 / 同发件人整理":@"manage",@"关闭隐藏，恢复原始列表":@"hide_off",@"开启发件人隐藏":@"hide_on",@"预览已加载邮件并选择移动…":@"move_loaded",@"在此账号新建邮箱…":@"create",@"结束整理，返回规则列表":@"preview_end",@"修改地址与范围":@"edit",@"打开同发件人整理预览":@"preview",@"删除规则":@"delete",@"停用规则":@"rule_off",@"启用规则":@"rule_on",@"保存：此邮箱":@"save_mailbox",@"保存：此账号各邮箱":@"save_account",@"选择同账号目标…":@"move_picker",@"关闭简洁外观":@"theme_off",@"开启简洁外观":@"theme_on",@"恢复安全模式（禁止提交）":@"safe_mode",@"仅测试邮件：申请允许原生提交…":@"request_submit",@"我确认，仅测试邮件允许执行":@"allow_submit"};
    NSString *code=style==UIAlertActionStyleCancel?@"cancel":(codes[title]?:@"choice");
    return [UIAlertAction actionWithTitle:title style:style handler:^(UIAlertAction *action){
        MRD(@"ui.click",style==UIAlertActionStyleCancel?@"cancelled":@"success",style==UIAlertActionStyleCancel?@"user_cancel":@"entered",nil,@{@"action":code,@"path":style==UIAlertActionStyleCancel?@"cancel":@"view"});
        if(handler)handler(action);
    }];
}
static void MRDAfterAlert(UIViewController *owner,void (^next)(void)) {
    if(!NSThread.isMainThread) {dispatch_async(dispatch_get_main_queue(),^{MRDAfterAlert(owner,next);});return;}
    UIViewController *alert=owner.presentedViewController;
    if([alert isKindOfClass:UIAlertController.class]) {
        MRD(@"ui.transition",@"pending",@"entered",alert,nil);
        if(alert.isBeingDismissed && alert.transitionCoordinator) {
            BOOL queued=[alert.transitionCoordinator animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context){MRD(@"ui.transition",@"success",@"ok",owner,nil);next();}];
            if(queued)return;
        }
        [alert dismissViewControllerAnimated:YES completion:^{MRD(@"ui.transition",@"success",@"ok",owner,nil);next();}];
        return;
    }
    if(alert){MRD(@"ui.transition",@"skipped",@"presentation_busy",owner,nil);return;}
    next();
}
static void MRDPresent(UIViewController *owner,UIViewController *controller) {
    MRDAfterAlert(owner,^{
        if(!owner.viewIfLoaded.window || owner.presentedViewController){MRD(@"ui.transition",@"failed",owner.presentedViewController?@"presentation_busy":@"not_visible",owner,nil);return;}
        MRD(@"ui.transition",@"pending",@"entered",controller,nil);
        [owner presentViewController:controller animated:YES completion:^{MRD(@"ui.transition",@"success",@"ok",controller,nil);}];
    });
}
static void Notice(UIViewController *owner,NSString *message) {
    MRD(@"ui.transition",@"pending",@"guard",owner,nil);
    if(!owner.viewIfLoaded.window) return;
    UIViewController *p=owner; while(p.presentedViewController) p=p.presentedViewController;
    if([p isKindOfClass:UIAlertController.class]) p=owner;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Mail 规则与整理" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:MRDAction(@"好",UIAlertActionStyleCancel,nil)];
    MRDPresent(p,a);
}
@interface MRDReportController : UIViewController {
    NSString *_reportText;
}
@property(nonatomic,copy) NSString *reportText;
@end
@implementation MRDReportController
@synthesize reportText=_reportText;
- (void)dealloc {[_reportText release];[super dealloc];}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Mail 0.5.1 诊断报告";
    UITextView *text=[[[UITextView alloc] initWithFrame:self.view.bounds] autorelease];
    text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    text.editable=NO;text.selectable=YES;text.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];text.text=_reportText;self.view=text;
    self.navigationItem.leftBarButtonItem=[[[UIBarButtonItem alloc] initWithTitle:@"关闭报告" style:UIBarButtonItemStylePlain target:self action:@selector(closeReport)] autorelease];
    self.navigationItem.rightBarButtonItems=@[[[[UIBarButtonItem alloc] initWithTitle:@"分享文本" style:UIBarButtonItemStylePlain target:self action:@selector(shareReport)] autorelease],[[[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clearReport)] autorelease]];
}
- (void)closeReport {MRDControl(@"success",@"ok",@"view");[self.navigationController dismissViewControllerAnimated:YES completion:nil];}
- (void)clearReport {MRDClear();self.reportText=@"诊断内存已清空。未改变规则或邮箱。";((UITextView *)self.view).text=self.reportText;}
- (void)shareReport {
    if(self.presentedViewController)return;
    MRDControl(@"pending",@"entered",@"share");
    UIActivityViewController *share=[[[UIActivityViewController alloc] initWithActivityItems:@[_reportText?:@""] applicationActivities:nil] autorelease];
    share.excludedActivityTypes=@[UIActivityTypeCopyToPasteboard];
    NSUInteger generation=[MRDSnapshot()[@"generation"] unsignedIntegerValue];
    share.completionWithItemsHandler=^(__unused UIActivityType activity,BOOL completed,__unused NSArray *items,NSError *error){
        if([MRDSnapshot()[@"generation"] unsignedIntegerValue]!=generation)return;
        MRDControl(error?@"failed":(completed?@"success":@"cancelled"),error?@"native_exception":(completed?@"ok":@"user_cancel"),@"share");
        MRDShareError(error);
    };
    share.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:share animated:YES completion:nil];
}
@end

@interface MR5State : NSObject {
@public
    UIViewController *owner;
    UIBarButtonItem *button;
    NSPredicate *local;
    NSArray *context;
    NSDictionary *configuration;
    NSString *reason;
    NSDictionary *preview;
    NSArray *previewContext;
    BOOL busy;
    BOOL movePanelPending;
}
- (void)show;
- (void)diagnostics;
- (void)report;
- (void)reload;
- (void)edit:(NSDictionary *)rule box:(id)box sender:(NSString *)sender;
- (void)manage;
- (void)beginPreview:(NSDictionary *)rule;
- (void)moveLoaded;
- (void)createMailbox;
- (void)mailboxEditingControllerDidFinish:(UIViewController *)controller;
@end
static MR5State *State(id owner,BOOL create) {
    MR5State *s=objc_getAssociatedObject(owner,&StateKey);
    if(!s && create) {
        s=[[[MR5State alloc] init] autorelease];s->owner=owner;
        objc_setAssociatedObject(owner,&StateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return s;
}
static void Reason(MR5State *s,NSString *text) { [s->reason release];s->reason=[text copy]; }
static NSPredicate *BuildLocal(MR5State *s) {
    if(Flag(s->owner,@"isSearchViewController") || Flag(s->owner,@"isSearching")) {
        MRD(@"reload.local",@"skipped",@"search",s->owner,nil);Reason(s,@"搜索查询保留 Mail 原生范围；请退出搜索后使用发件人规则和整理。");return nil;
    }
    NSArray *keys=BoxKeys(s->owner);
    if(!keys.count) {MRD(@"reload.local",@"skipped",@"scope_invalid",s->owner,nil);Reason(s,@"当前包含非实体邮箱或临时标识：保留原生列表。");return nil;}
    if(s->preview && ![keys isEqual:s->previewContext]) {
        [s->preview release];s->preview=nil;[s->previewContext release];s->previewContext=nil;
    }
    if(s->preview) {
        NSMutableArray *scope=[NSMutableArray array];
        for(id box in Boxes(s->owner)) if([AccountID(box) isEqual:s->preview[@"account"]] && ([s->preview[@"scope"] isEqual:@"account"] || [BoxID(box) isEqual:s->preview[@"mailbox"]])) [scope addObject:box];
        NSPredicate *p=Sender(s->preview[@"sender"]),*b=scope.count?InBoxes(scope):nil;
        if(!p || !b) {MRD(@"reload.local",@"failed",@"model_contract",s->owner,nil);Reason(s,@"整理查询验证失败：未修改原生列表，不能移动。");return nil;}
        Reason(s,@"整理预览：精确发件人、单封邮件、当前来源邮箱。未移动任何邮件。");
        return MR5And(b,p);
    }
    NSDictionary *d=Load();
    if(![d[@"enabled"] boolValue]) {MRD(@"reload.local",@"skipped",@"disabled",s->owner,nil);Reason(s,@"隐藏总开关关闭：原始列表。规则与移动互相独立。");return nil;}
    NSMutableArray *hidden=[NSMutableArray array];
    for(id box in Boxes(s->owner)) {
        for(NSDictionary *rule in MR5RulesForBox(Array(d[@"rules"]),AccountID(box),BoxID(box))) {
            NSPredicate *p=Sender(rule[@"sender"]), *b=InBoxes(@[box]);
            if(!p || !b) {MRD(@"reload.local",@"failed",@"model_contract",s->owner,nil);Reason(s,@"此列表规则未通过原生合成模型自检：保留原始列表。");return nil;}
            [hidden addObject:MR5And(b,p)];
        }
    }
    if(!hidden.count) {MRD(@"reload.local",@"skipped",@"no_rules",s->owner,nil);Reason(s,@"当前范围没有启用规则：原始列表。");return nil;}
    Reason(s,@"隐藏生效于本列表的消息查询；以单封显示，保留系统筛选与原生消息ID。");
    return [NSCompoundPredicate notPredicateWithSubpredicate:[NSCompoundPredicate orPredicateWithSubpredicates:hidden]];
}
static id BatchRead(id item,NSString *key) {
    if([key isEqual:@"isMessage"]) return @([item isKindOfClass:NSClassFromString(@"EMMessage")]);
    if([key isEqual:@"itemID"]) return Get(item,@"itemID");
    if([key isEqual:@"boxes"]) {
        NSMutableArray *out=[NSMutableArray array];
        for(id box in Array(Get(item,@"mailboxes"))) [out addObject:@{@"account":AccountID(box)?:@"",@"mailbox":BoxID(box)?:@""}];
        return out;
    }
    return nil;
}
static NSSet *PreviewBoxes(MR5State *s) {
    NSMutableSet *ids=[NSMutableSet set];
    for(id box in Boxes(s->owner)) if([AccountID(box) isEqual:s->preview[@"account"]] && ([s->preview[@"scope"] isEqual:@"account"] || [BoxID(box) isEqual:s->preview[@"mailbox"]])) if(BoxID(box)) [ids addObject:BoxID(box)];
    return ids;
}
static BOOL ValidItems(MR5State *s,NSArray *items,NSArray *ids) {
    return !Flag(s->owner,@"isSearchViewController") && !Flag(s->owner,@"isSearching") && s->preview && s->local && MR5Context(s->owner,s->owner,BoxKeys(s->owner),s->previewContext) && MR5Batch(items,ids,s->preview[@"account"],PreviewBoxes(s),Sender(s->preview[@"sender"]),^id(id x,NSString *k){return BatchRead(x,k);});
}
static NSString *BoxTitle(id box) {
    NSString *name=Get(box,@"name"), *account=Get(Get(box,@"account"),@"name");
    return [NSString stringWithFormat:@"%@ · %@",account?:@"邮箱账号",name?:@"当前邮箱"];
}
static void PresentSheet(MR5State *s,UIAlertController *a) {
    a.popoverPresentationController.barButtonItem=s->button;
    MRDPresent(s->owner,a);
}
static void ChooseBox(MR5State *s,void (^chosen)(id)) {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"选择规则所属账号与邮箱" message:@"不同账号单独保存；账号范围规则仅影响该账号自己的邮箱。" preferredStyle:UIAlertControllerStyleActionSheet];
    for(id box in Boxes(s->owner)) if(AccountID(box) && BoxID(box)) [a addAction:MRDAction(BoxTitle(box),UIAlertActionStyleDefault,^(__unused UIAlertAction *action){chosen(box);})];
    [a addAction:MRDAction(@"取消",UIAlertActionStyleCancel,nil)];PresentSheet(s,a);
}
@implementation MR5State
- (void)diagnostics {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Mail 0.5.1 · mail051-trace-r2" message:@"默认不采集。开始后仅在内存保留有限脱敏事件；退出/被系统杀死即丢失。默认阻止本插件最终新建/移动提交；只用 1–3 封专门测试邮件，原生界面推荐取消。停止后可查看/分享文本；不会上传、写日志或复制剪贴板。" preferredStyle:UIAlertControllerStyleActionSheet];
    if(!MRDActive())[a addAction:MRDAction(@"开始诊断（新一轮，清空旧记录）",UIAlertActionStyleDefault,^(__unused UIAlertAction *x){
        MRDStart();
        MRD(@"install.bundle",@"success",@"ok",nil,@{@"filterMatches":@([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobilemail"]),@"schema":@1});
        MRD(@"ui.entry",@"success",@"entered",owner,@{@"ready":@(Ready),@"moveReady":@(MoveReady),@"createReady":@(CreateReady)});
        MRD(@"ui.click",@"success",@"started",owner,@{@"path":@"start"});
        Notice(owner,@"诊断已开始，安全模式默认开启。请逐个操作规则、预览、新建/移动（取消），然后回这里停止并查看。不会自动重放操作。");
    })];
    if(MRDActive()) {
        [a addAction:MRDAction(@"停止并查看 / 分享",UIAlertActionStyleDefault,^(__unused UIAlertAction *x){MRDStop();[self report];})];
        for(NSString *tag in @[@"rules",@"preview",@"move",@"create",@"theme"]) {
            NSDictionary *labels=@{@"rules":@"规则",@"preview":@"预览",@"move":@"移动",@"create":@"新建",@"theme":@"外观"};
            [a addAction:MRDAction([@"打阶段标记：" stringByAppendingString:labels[tag]],UIAlertActionStyleDefault,^(__unused UIAlertAction *x){MRDTag(tag);})];
        }
        [a addAction:MRDAction(MRDCanSubmit()?@"恢复安全模式（禁止提交）":@"仅测试邮件：申请允许原生提交…",UIAlertActionStyleDestructive,^(__unused UIAlertAction *x){
            if(MRDCanSubmit()){MRDAllowTestSubmit(NO);return;}
            UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"仅限专门测试邮件" message:@"确认你仅选择 1–3 封可丢弃的测试邮件。允许后原功能可真实新建/移动并同步其他设备；不会自动执行。之前已打开的安全面板仍被拦截，请取消后重开。推荐保持安全模式。" preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:MRDAction(@"保持禁止，取消",UIAlertActionStyleCancel,nil)];
            [confirm addAction:MRDAction(@"我确认，仅测试邮件允许执行",UIAlertActionStyleDestructive,^(__unused UIAlertAction *y){MRDAllowTestSubmit(YES);})];MRDPresent(owner,confirm);
        })];
    } else {
        [a addAction:MRDAction(@"查看上轮报告 / 分享",UIAlertActionStyleDefault,^(__unused UIAlertAction *x){[self report];})];
    }
    [a addAction:MRDAction(@"清空诊断内存",UIAlertActionStyleDestructive,^(__unused UIAlertAction *x){MRDClear();})];
    [a addAction:MRDAction(@"返回（不退出 Mail）",UIAlertActionStyleCancel,nil)];PresentSheet(self,a);
}
- (void)report {
    MRDControl(@"pending",@"entered",@"view");
    UIViewController *presenter=owner; // Retained by copied dispatch blocks under MRC.
    NSDictionary *snapshot=[MRDSnapshot() retain];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSString *text=MRDText(snapshot);
        dispatch_async(dispatch_get_main_queue(),^{
            NSDictionary *now=MRDSnapshot();
            if(![now[@"generation"] isEqual:snapshot[@"generation"]] || ![now[@"start"] isEqual:snapshot[@"start"]])return;
            MRDReportController *report=[[[MRDReportController alloc] init] autorelease];report.reportText=text;
            UINavigationController *nav=[[[UINavigationController alloc] initWithRootViewController:report] autorelease];MRDPresent(presenter,nav);
        });
        [snapshot release];
    });
}

- (void)dealloc {
    [button release];[local release];[context release];[configuration release];[reason release];[preview release];[previewContext release];[super dealloc];
}
- (void)reload {MRD(@"reload.request",busy?@"skipped":@"pending",busy?@"busy":@"entered",owner,nil);if(!busy)Void(owner,@"_reloadDataSource");}
- (void)show {
    MRD(@"ui.entry",@"success",@"entered",owner,@{@"ready":@(Ready),@"moveReady":@(MoveReady),@"createReady":@(CreateReady)});
    if(owner.presentedViewController) return;
    NSString *info=[NSString stringWithFormat:@"%@\n地址按 Mail 原生规则忽略大小写，不合并点或 +标签。新邮件随原生查询加载；不承诺未下载历史。",reason?:@"准备就绪"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Mail 0.5.1 · 规则与诊断" message:info preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:MRDAction(@"诊断会话（手动开始 / 停止）",UIAlertActionStyleDefault,^(__unused UIAlertAction *action){[self diagnostics];})];
    if(Ready && [NSStringFromClass(owner.class) isEqual:@"MessageListViewController"]) {
        [a addAction:MRDAction(@"从选中邮件的发件人添加",UIAlertActionStyleDefault,^(__unused UIAlertAction *action){
            MRD(@"ui.click",@"success",@"entered",owner,@{@"path":@"selected"});
            id selection=Get(Get(owner,@"messageListSelectionModel"),@"currentMessageListItemSelection");
            NSArray *items=Array(Get(selection,@"messageListItems"));
            id message=items.count==1?items.firstObject:nil;
            if(message && ![message isKindOfClass:NSClassFromString(@"EMMessage")]) {
                id display=Get(message,@"displayMessage");
                message=[display isKindOfClass:NSClassFromString(@"EMMessage")]?display:Get(display,@"resultIfAvailable");
            }
            NSString *sender=ReadAddress(Get(message,@"senderAddress"));
            MRD(@"selection.map",sender?@"success":@"failed",sender?@"ok":@"invalid_items",message,@{@"count":@(items.count)});
            if(!sender) {Notice(owner,@"请先在原生列表选择一封邮件，再打开插件；也可直接输入精确邮箱地址。");return;}
            ChooseBox(self,^(id box){[self edit:nil box:box sender:sender];});
        })];
        [a addAction:MRDAction(@"输入发件人添加规则",UIAlertActionStyleDefault,^(__unused UIAlertAction *action){MRD(@"ui.click",@"success",@"entered",owner,@{@"path":@"input"});ChooseBox(self,^(id box){[self edit:nil box:box sender:nil];});})];
        [a addAction:MRDAction(@"管理规则 / 同发件人整理",UIAlertActionStyleDefault,^(__unused UIAlertAction *action){[self manage];})];
        [a addAction:MRDAction([Load()[@"enabled"] boolValue]?@"关闭隐藏，恢复原始列表":@"开启发件人隐藏",UIAlertActionStyleDefault,^(__unused UIAlertAction *action){
            NSMutableDictionary *d=Load();d[@"enabled"]=@(![d[@"enabled"] boolValue]);MRD(@"rule.toggle",@"pending",@"entered",owner,@{@"enabled":d[@"enabled"]});BOOL saved=Save(d);MRD(@"rule.toggle",saved?@"success":@"failed",saved?@"ok":@"sync_failed",owner,@{@"enabled":d[@"enabled"]});
            [preview release];preview=nil;[previewContext release];previewContext=nil;[self reload];
        })];
        if(preview) {
            [a addAction:MRDAction(@"预览已加载邮件并选择移动…",UIAlertActionStyleDefault,^(__unused UIAlertAction *action){[self moveLoaded];})];
            [a addAction:MRDAction(@"在此账号新建邮箱…",UIAlertActionStyleDefault,^(__unused UIAlertAction *action){[self createMailbox];})];
            [a addAction:MRDAction(@"结束整理，返回规则列表",UIAlertActionStyleDefault,^(__unused UIAlertAction *action){MRD(@"preview.end",@"success",@"ok",owner,nil);[preview release];preview=nil;[previewContext release];previewContext=nil;[self reload];})];
        }
    }
    [a addAction:MRDAction(MRThemeEnabled()?@"关闭简洁外观":@"开启简洁外观",UIAlertActionStyleDefault,^(__unused UIAlertAction *action){MRThemeSetEnabled(!MRThemeEnabled());})];
    [a addAction:MRDAction(@"关闭",UIAlertActionStyleCancel,nil)];PresentSheet(self,a);
}
- (void)edit:(NSDictionary *)rule box:(id)box sender:(NSString *)sender {
    MRD(@"rule.edit",@"pending",@"entered",box,@{@"accountID":MRDAccount(AccountID(box))});
    NSString *account=AccountID(box),*mailbox=BoxID(box); if(!account || !mailbox) return;
    __block UIAlertController *a=[UIAlertController alertControllerWithTitle:rule?@"编辑规则":@"添加发件人规则" message:[BoxTitle(box) stringByAppendingString:@"\n仅隐藏，不会自动移动。输入纯邮箱地址，不含显示名。"] preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"sender@example.com";f.text=sender?:rule[@"sender"];f.keyboardType=UIKeyboardTypeEmailAddress;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    for(NSString *scope in @[@"mailbox",@"account"]) [a addAction:MRDAction([scope isEqual:@"mailbox"]?@"保存：此邮箱":@"保存：此账号各邮箱",UIAlertActionStyleDefault,^(__unused UIAlertAction *action){
        NSString *value=MR5Address(a.textFields.firstObject.text);
        MRD(@"ui.click",@"success",@"entered",owner,@{@"path":@"save"});
        MRD(@"rule.save",@"pending",@"entered",owner,@{@"path":scope,@"accountID":MRDAccount(account)});
        if(!value || !Sender(value)) {MRD(@"rule.save",@"failed",@"model_contract",owner,nil);dispatch_async(dispatch_get_main_queue(),^{Notice(owner,@"地址格式或原生精确匹配验证失败，未保存。支持 ASCII 邮箱地址；国际化域名请使用 punycode。");});return;}
        NSMutableDictionary *d=Load();NSMutableArray *rules=[[Array(d[@"rules"]) mutableCopy] autorelease];
        NSDictionary *entry=@{@"id":rule[@"id"]?:NSUUID.UUID.UUIDString,@"account":account,@"mailbox":mailbox,@"sender":value,@"scope":scope,@"enabled":rule[@"enabled"]?:@YES,@"label":BoxTitle(box)};
        NSIndexSet *old=[rules indexesOfObjectsPassingTest:^BOOL(id x,NSUInteger idx,BOOL *stop){return [x[@"id"] isEqual:entry[@"id"]];}];
        [rules removeObjectsAtIndexes:old];[rules addObject:entry];d[@"rules"]=rules;Save(d);[self reload];
    })];
    [a addAction:MRDAction(@"取消",UIAlertActionStyleCancel,nil)];MRDPresent(owner,a);
}
- (void)manage {
    MRD(@"rule.manage",@"success",@"entered",owner,nil);
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"已保存规则" message:@"点击可修改、停用、删除；整理为独立的手动操作，不依赖隐藏开关。" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *rules=Array(Load()[@"rules"]);
    for(NSDictionary *rule in rules) {
        NSString *title=[NSString stringWithFormat:@"%@ %@ · %@",[rule[@"enabled"] boolValue]?@"开":@"停",rule[@"sender"],rule[@"label"]?:@"账号"];
        [a addAction:MRDAction(title,UIAlertActionStyleDefault,^(__unused UIAlertAction *action){
            UIAlertController *b=[UIAlertController alertControllerWithTitle:rule[@"sender"] message:[NSString stringWithFormat:@"%@\n范围：%@",rule[@"label"]?:@"保存的账号",[rule[@"scope"] isEqual:@"account"]?@"此账号各邮箱":@"指定邮箱"] preferredStyle:UIAlertControllerStyleActionSheet];
            id current=nil;for(id box in Boxes(owner)) if([AccountID(box) isEqual:rule[@"account"]] && ([rule[@"scope"] isEqual:@"account"] || [BoxID(box) isEqual:rule[@"mailbox"]])) {current=box;break;}
            if(current) {
                [b addAction:MRDAction(@"修改地址与范围",UIAlertActionStyleDefault,^(__unused UIAlertAction *x){[self edit:rule box:current sender:nil];})];
                [b addAction:MRDAction(@"打开同发件人整理预览",UIAlertActionStyleDefault,^(__unused UIAlertAction *x){[self beginPreview:rule];})];
            }
            for(NSString *op in @[@"toggle",@"delete"]) [b addAction:MRDAction([op isEqual:@"delete"]?@"删除规则":([rule[@"enabled"] boolValue]?@"停用规则":@"启用规则"),[op isEqual:@"delete"]?UIAlertActionStyleDestructive:UIAlertActionStyleDefault,^(__unused UIAlertAction *x){
                NSMutableDictionary *d=Load();NSMutableArray *out=[NSMutableArray array];
                for(NSDictionary *r in Array(d[@"rules"])) {
                    if(![r[@"id"] isEqual:rule[@"id"]]) {[out addObject:r];continue;}
                    if([op isEqual:@"toggle"]) {NSMutableDictionary *copy=[[r mutableCopy] autorelease];copy[@"enabled"]=@(![r[@"enabled"] boolValue]);[out addObject:copy];}
                }
                MRD([op isEqual:@"toggle"]?@"rule.toggle":@"rule.delete",@"pending",@"entered",owner,nil);d[@"rules"]=out;BOOL saved=Save(d);MRD([op isEqual:@"toggle"]?@"rule.toggle":@"rule.delete",saved?@"success":@"failed",saved?@"ok":@"sync_failed",owner,nil);[self reload];
            })];
            [b addAction:MRDAction(@"取消",UIAlertActionStyleCancel,nil)];PresentSheet(self,b);
        })];
    }
    [a addAction:MRDAction(@"关闭",UIAlertActionStyleCancel,nil)];PresentSheet(self,a);
}
- (void)beginPreview:(NSDictionary *)rule {
    MRD(@"preview.begin",@"pending",@"entered",owner,@{@"moveReady":@(MoveReady),@"accountID":MRDAccount(rule[@"account"])});
    if(!MoveReady) {MRD(@"preview.begin",@"skipped",@"abi_mismatch",owner,nil);Notice(owner,@"原生移动交互边界不可用，未开启整理。隐藏规则仍可使用。");return;}
    if(busy){MRD(@"preview.begin",@"skipped",@"busy",owner,nil);return;}
    if(!BoxKeys(owner).count || Flag(owner,@"isSearchViewController") || Flag(owner,@"isSearching")) {MRD(@"preview.begin",@"failed",@"scope_invalid",owner,nil);Notice(owner,@"当前搜索或邮箱身份范围无法核验，未开启整理。请返回实体邮箱列表。");return;}
    Void(Get(owner,@"messageListSelectionModel"),@"clearAll");
    Void(Get(owner,@"messageListSelectionModel"),@"disableSelectAll");
    [preview release];preview=[rule copy];[previewContext release];previewContext=[BoxKeys(owner) copy];[self reload];
    MRD(@"preview.begin",local?@"success":@"failed",local?@"ok":@"model_contract",owner,@{@"hasLocal":@(local!=nil)});
    if(local) Notice(owner,@"已进入精确发件人单封列表。通过「插件 → 预览已加载邮件并选择移动」核对数量，再由原生移动面板选择目标。同账号新建邮箱也是独立操作，不自动移动。退出整理会恢复原生查询，不回放旧账号状态。");
}
- (void)moveLoaded {
    MRD(@"selection.map",@"pending",@"entered",owner,nil);
    if(!MoveReady) {MRD(@"move.open",@"skipped",@"abi_mismatch",owner,nil);Notice(owner,@"原生移动保护接口未安装，不能安全打开移动面板；未提交移动。请导出诊断报告。");return;}
    if(busy || !preview || !local || ![BoxKeys(owner) isEqual:previewContext]) {MRD(@"selection.map",@"failed",@"scope_changed",owner,nil);return;}
    id ds=Get(owner,@"dataSource");
    id snapshot=Get(Get(ds,@"dataSource"),@"snapshot");
    NSArray *allIDs=MRDActive()?Array(Get(Get(owner,@"messageListSelectionModel"),@"itemIDs")):Array(Get(snapshot,@"itemIdentifiers"));
    if(MRDActive() && (!allIDs.count || allIDs.count>3)){MRD(@"selection.map",@"skipped",@"diagnostic_dry_run",owner,@{@"count":@(allIDs.count)});Notice(owner,@"诊断只接受你手动选中的 1–3 封专门测试邮件；不会替你选择全部真实邮件。请取消此提示，回列表选择后重试。");return;}
    NSMutableArray *items=[NSMutableArray array],*ids=[NSMutableArray array];
    // No synchronous future.result: never block the Mail UI waiting for the daemon.
    for(id itemID in allIDs) {
        id future=One(ds,@"messageListItemForItemID:",itemID);
        id item=[future isKindOfClass:NSClassFromString(@"EMMessage")]?future:Get(future,@"resultIfAvailable");
        BOOL valid=item && ValidItems(self,@[item],@[itemID]);
        MRD(@"selection.item",valid?@"success":(item?@"failed":@"pending"),valid?@"ok":(item?@"invalid_items":@"future_pending"),item,@{@"resultPresent":@(item!=nil),@"sourceMatches":@(valid),@"accountID":MRDAccount(preview[@"account"])});
        if(valid) {[items addObject:item];[ids addObject:itemID];}
    }
    MRD(@"selection.map",items.count?@"success":@"skipped",items.count?@"only_loaded":@"no_items",owner,@{@"expectedCount":@(allIDs.count),@"actualCount":@(items.count)});
    if(!items.count) {Notice(owner,@"暂无已加载且通过逐封核对的匹配邮件。没有提交移动；可等待列表自然加载后重试。");return;}
    NSArray *capturedContext=[[previewContext copy] autorelease];
    NSDictionary *capturedRule=[[preview copy] autorelease];
    NSString *text=[NSString stringWithFormat:@"发件人：%@\n来源：%@（仅当前列表范围）\n已核对 %lu 封；尚未加载的邮件不包含。\n下一步由 Mail 原生面板选择同账号目标，选择目标会执行移动并可能同步其他设备。不会移动整个混合会话。",preview[@"sender"],preview[@"label"],(unsigned long)items.count];
    if(MRDActive() && !MRDCanSubmit()) text=[NSString stringWithFormat:@"无写入演练：已核对 %lu 封手动选中的测试邮件。下一步只查看 Mail 原生目标面板，然后点取消；安全模式拦截最终移动提交，不会替你选择全部邮件。规则保存与外观开关仍会保存插件自身设置。",(unsigned long)items.count];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"核对批量移动" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:MRDAction(@"选择同账号目标…",UIAlertActionStyleDefault,^(__unused UIAlertAction *action){
        if(![preview isEqual:capturedRule] || ![BoxKeys(owner) isEqual:capturedContext] || !ValidItems(self,items,ids)) {Notice(owner,@"来源或邮件集合已变化，未移动。请重新预览。");return;}
        id model=Get(owner,@"messageListSelectionModel");
        if(!ABI(model,@"clearAll","v16@0:8") || !ABI(model,@"disableSelectAll","v16@0:8") || !ABI(model,@"selectItemWithItemID:","@24@0:8@16") || !ABI(owner,@"_showTransferPickerForNonPredictiveMoveOfMessages:","v24@0:8@16")) {Notice(owner,@"原生选择/移动接口不匹配，未提交。");return;}
        Void(model,@"clearAll");Void(model,@"disableSelectAll");
        for(id itemID in ids) One(model,@"selectItemWithItemID:",itemID);
        NSArray *selected=Array(Get(Get(model,@"currentMessageListItemSelection"),@"messageListItems"));
        if(Flag(model,@"isSelectAll") || !ValidItems(self,selected,ids)) {Void(model,@"clearAll");Notice(owner,@"原生选择尚未稳定，未打开移动；请在列表加载完成后重试。");return;}
        movePanelPending=YES;MRD(@"move.open",@"pending",@"entered",owner,@{@"count":@(selected.count),@"safeMode":@(!MRDCanSubmit())});
        MRDAfterAlert(owner,^{Set(owner,@"_showTransferPickerForNonPredictiveMoveOfMessages:",selected);});
        Reason(self,@"已打开原生目标选择；尚未确认执行。仅接受同账号且逐封精确匹配的选择。");
    })];
    [a addAction:MRDAction(@"取消",UIAlertActionStyleCancel,nil)];MRDPresent(owner,a);
}
- (void)createMailbox {
    MRD(@"create.open",@"pending",@"entered",owner,@{@"createReady":@(CreateReady)});
    if(!CreateReady) {MRD(@"create.open",@"skipped",@"abi_mismatch",owner,nil);Notice(owner,@"原生新建边界不可用；可以继续使用规则和已有目录移动。");return;}
    if(!preview || !local || Flag(owner,@"isSearchViewController") || Flag(owner,@"isSearching") || !MR5Context(owner,owner,BoxKeys(owner),previewContext)) {MRD(@"create.open",@"failed",@"scope_invalid",owner,nil);Notice(owner,@"当前来源范围无效或已变化，未打开新建界面。");return;}
    id box=nil;for(id b in Boxes(owner)) if([AccountID(b) isEqual:preview[@"account"]]) {box=b;break;}
    id account=One(Get(owner,@"accountsProvider"),@"legacyMailAccountForObjectID:",Get(box,@"accountIdentifier"));
    Class cls=NSClassFromString(@"MailboxEditingController");
    id raw=[cls alloc];
    if(!account || !ABI(raw,@"initWithMailbox:account:validAccounts:","@40@0:8@16@24@32")) {MRD(@"create.open",@"failed",@"not_available",owner,nil);[raw release];Notice(owner,@"该账号的原生新建邮箱接口不可用；未创建也未移动。");return;}
    UIViewController *editor=((id(*)(id,SEL,id,id,id))objc_msgSend)(raw,NSSelectorFromString(@"initWithMailbox:account:validAccounts:"),nil,account,@[account]);
    if(!Set(editor,@"setDelegate:",self)) {[editor release];return;}
    objc_setAssociatedObject(editor,&CreateKey,account,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(editor,&DiagnosticGuardKey,@(!MRDCanSubmit()),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MRD(@"create.open",@"success",@"ok",editor,@{@"accountID":MRDAccount(preview[@"account"]),@"safeMode":@(!MRDCanSubmit())});
    UINavigationController *nav=[[[UINavigationController alloc] initWithRootViewController:editor] autorelease];
    MRDPresent(owner,nav);[editor release];
    Reason(self,@"原生新建界面：保存由 Mail 自身队列执行。创建后请等待目录出现，再重新选择移动目标。");
}
- (void)mailboxEditingControllerDidFinish:(UIViewController *)controller {
    if(!objc_getAssociatedObject(controller,&CreateKey)) return;
    BOOL submitted=[objc_getAssociatedObject(controller,&StartedKey) boolValue];
    MRD(@"create.completion",submitted?@"pending":@"cancelled",submitted?@"pending_sync":@"user_cancel",controller,nil);
    [controller.navigationController dismissViewControllerAnimated:YES completion:nil];
    Reason(self,@"新建界面已结束，不等于服务端创建完成。请确认邮箱已出现；本插件未自动移动任何邮件。");
}
@end
static void (*Reload)(id,SEL);
static BOOL (*Threaded)(id,SEL);
static MR5ListFactory Simple;
static void MRDObserveList(id owner) {
    NSUInteger session=MRDSession();if(!session)return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.25*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if(MRDSession()!=session)return;
        id view=Get(owner,@"collectionView");
        if(![view isKindOfClass:UICollectionView.class]){MRDAt(session,@"list.refresh",@"skipped",@"not_available",owner,nil);return;}
        UICollectionView *collection=view;NSInteger sections=collection.numberOfSections,total=0;
        for(NSInteger i=0;i<MIN(sections,8);i++)total+=[collection numberOfItemsInSection:i];
        MRDAt(session,@"list.refresh",@"success",@"observed_snapshot",owner,@{@"section":@(sections),@"actualCount":@(total),@"count":@(collection.visibleCells.count),@"resultPresent":@(collection.window!=nil)});
    });
}
static void ReloadHook(id vc,SEL cmd) {
    MRD(@"reload.enter",@"pending",@"entered",vc,@{@"hasTLS":@(ReloadFrame!=nil)});
    id previous=ReloadOwner;ReloadOwner=vc;
    NSDictionary *previousFrame=ReloadFrame;ReloadFrame=nil;
    @try {
        if(!Ready || ![NSStringFromClass([vc class]) isEqual:@"MessageListViewController"] || !NSThread.isMainThread) {MRD(@"reload.local",@"skipped",!NSThread.isMainThread?@"off_main":(!Ready?@"abi_mismatch":@"subclass"),vc,nil);Reload(vc,cmd);return;}
        MR5State *s=State(vc,YES);
        NSPredicate *next=nil;
        @try {next=BuildLocal(s);}
        @catch(__unused NSException *e) {MRD(@"reload.local",@"failed",@"exception",vc,nil);Reason(s,@"原生模型验证异常：仅清理插件状态，保留当前原生上下文。");}
        if(![s->local isEqual:next] && (s->local || next)) {
            Void(Get(vc,@"messageListSelectionModel"),@"clearAll");
            Void(Get(vc,@"messageListSelectionModel"),@"disableSelectAll");
        }
        [s->local release];s->local=[next retain];
        [s->context release];s->context=[BoxKeys(vc) copy];
        [s->configuration release];s->configuration=[Load() copy];
        if(next) MRD(@"reload.local",@"success",@"ok",vc,@{@"hasLocal":@YES});
        if(next) ReloadFrame=[@{@"owner":vc,@"boxes":Boxes(vc),@"keys":s->context,@"local":next} copy];
        Reload(vc,cmd);
        MRD(@"list.refresh",@"pending",@"original_returned",vc,@{@"hasLocal":@(next!=nil)});MRDObserveList(vc);
    } @finally {
        MRD(@"reload.exit",@"success",@"original_returned",vc,@{@"hasTLS":@(ReloadFrame!=nil)});
        [ReloadFrame release];ReloadFrame=previousFrame;
        ReloadOwner=previous;
    }
}
static BOOL ThreadedHook(id vc,SEL cmd) {
    MRD(@"thread.path",@"success",@"entered",vc,nil);
    MR5State *s=State(vc,NO);
    return s && s->local && !Flag(vc,@"isSearchViewController") && !Flag(vc,@"isSearching") && [s->context isEqual:BoxKeys(vc)]?NO:Threaded(vc,cmd);
}
static id FactoryHook(id cls,SEL cmd,id boxes,id repository,BOOL oldest,BOOL display,id sort,MR5PredicateTransform transform,id ignore) {
    NSDictionary *frame=ReloadFrame;
    MRD(@"factory.hit",@"success",@"entered",ReloadOwner,@{@"hasTLS":@(frame!=nil),@"ownerMatches":@(frame && ReloadOwner==frame[@"owner"])});
    NSPredicate *local=nil;
    if(frame && MR5Context(ReloadOwner,frame[@"owner"],BoxKeys(ReloadOwner),frame[@"keys"]) && [Array(boxes) isEqual:frame[@"boxes"]]) local=frame[@"local"];
    MRD(@"factory.transform",local?@"pending":@"skipped",local?@"entered":(frame?@"context_mismatch":@"no_tls"),ReloadOwner,@{@"hasLocal":@(local!=nil),@"boxesMatch":@(frame && [Array(boxes) isEqual:frame[@"boxes"]])});
    return MR5InvokeFactory(Simple,cls,cmd,boxes,repository,oldest,display,sort,transform,ignore,local);
}
static BOOL Hook(Class cls,NSString *name,const char *type,IMP replacement,IMP *original) {
    SEL sel=NSSelectorFromString(name);Method m=class_getInstanceMethod(cls,sel);
    MRDDeclare(@"abi",name,type,m?method_getTypeEncoding(m):NULL,m && !strcmp(method_getTypeEncoding(m),type));
    if(!m || strcmp(method_getTypeEncoding(m),type)) return NO;
    if(original) *original=method_getImplementation(m);
    if(!class_addMethod(cls,sel,replacement,type)) method_setImplementation(m,replacement);
    return YES;
}
static void (*Move)(id,SEL,id),(*MoveDelegate)(id,SEL,id);
static void MoveDelegateHook(id interaction,SEL cmd,id delegate) {
    MoveDelegate(interaction,cmd,delegate);
    MRD(@"move.delegate",@"success",@"original_returned",interaction,nil);
    MR5State *s=State(delegate,NO);
    if(s && s->preview && !objc_getAssociatedObject(interaction,&MoveKey)) {
        NSDictionary *stamp=@{@"rule":s->preview,@"context":s->previewContext?:@[],@"owner":[NSValue valueWithNonretainedObject:delegate],@"dryRun":@(!MRDCanSubmit())};
        objc_setAssociatedObject(interaction,&MoveKey,stamp,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Never erase an existing stamp when a native interaction loses its delegate.
}
static void MoveHook(id interaction,SEL cmd,id completion) {
    NSUInteger session=MRDSession();
    MRD(@"move.perform",@"pending",@"entered",interaction,nil);
    id vc=Get(interaction,@"delegate");MR5State *s=State(vc,NO);
    NSDictionary *stamp=objc_getAssociatedObject(interaction,&MoveKey);
    if(!stamp && (!s || !s->preview)) {
        if(!MRDRequireSubmit(@"move.perform",interaction,NO)){if(completion)((void(^)(id,BOOL))completion)(interaction,NO);return;}
        MRD(@"move.perform",@"skipped",@"guard",interaction,nil);Move(interaction,cmd,completion);return;}
    if(s)s->movePanelPending=NO;
    if(!NSThread.isMainThread || !s || !s->preview || !stamp || [stamp[@"owner"] nonretainedObjectValue]!=vc || ![s->preview isEqual:stamp[@"rule"]] || ![BoxKeys(vc) isEqual:stamp[@"context"]]) {
        MRD(@"move.perform",@"failed",@"scope_changed",interaction,nil);
        if(completion) ((void(^)(id,BOOL))completion)(interaction,NO);
        if(vc) dispatch_async(dispatch_get_main_queue(),^{Notice(vc,@"移动来源已变化或已退出整理，未执行。请重新预览。");});
        return;
    }
    // Native completion contract is (interaction, didPerform), not server sync.
    void (^done)(id,BOOL)=completion;
    BOOL valid=NO;
    @try {
        id model=Get(vc,@"messageListSelectionModel"),selection=Get(interaction,@"messageListItemSelection");
        NSArray *items=Array(Get(selection,@"messageListItems"));
        NSArray *ids=Array(Get(model,@"itemIDs"));
        id explicitSelection=nil;
        if(ABI(model,@"isSelectAll","B16@0:8") && Flag(model,@"isSelectionValid") && !Flag(model,@"isSelectAll") && !Flag(model,@"isPerformingDataSourceUpdates") && !Array(Get(model,@"itemIDsPendingConfiguration")).count && !Array(Get(model,@"itemIDsMissingMessageListItem")).count && ABI(model,@"selectionWithMessageListItems:mailboxes:","@32@0:8@16@24")) explicitSelection=((id(*)(id,SEL,id,id))objc_msgSend)(model,NSSelectorFromString(@"selectionWithMessageListItems:mailboxes:"),items,nil);
        id target=Get(interaction,@"targetMailbox");
        MRD(@"move.validate",@"pending",@"entered",target,@{@"accountID":MRDAccount(s->preview[@"account"]),@"targetAccountID":MRDAccount(AccountID(target)),@"sameAccount":@([AccountID(target) isEqual:s->preview[@"account"]]),@"targetDifferent":@(![PreviewBoxes(s) containsObject:BoxID(target)]),@"count":@(items.count),@"selectionValid":@(explicitSelection!=nil)});
        valid=explicitSelection && object_getClass(explicitSelection)==object_getClass(selection) && [AccountID(target) isEqual:s->preview[@"account"]] && ![PreviewBoxes(s) containsObject:BoxID(target)] && ValidItems(s,items,ids);
    } @catch(__unused NSException *e) {valid=NO;MRD(@"move.validate",@"failed",@"exception",interaction,nil);}
    MRD(@"move.validate",valid?@"success":@"failed",valid?@"ok":@"invalid_items",interaction,nil);
    if(!MRDRequireSubmit(@"move.perform",interaction,[stamp[@"dryRun"] boolValue])) {if(done)done(interaction,NO);Notice(vc,@"诊断安全模式已阻止最终移动提交。未移动邮件；推荐在原生面板取消。仅专门测试邮件可以另外明确授权。");return;}
    if(valid) {
        @synchronized(interaction) {
            if(objc_getAssociatedObject(interaction,&StartedKey)) {if(done) done(interaction,NO);return;}
            objc_setAssociatedObject(interaction,&StartedKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    NSDictionary *reportRule=s->preview;
    NSArray *reportContext=s->previewContext;
    if(valid)MRD(@"move.perform",@"userSubmitted",@"user_submit",interaction,nil);
    MR5Perform(valid,interaction,^(void (^wrapped)(id,BOOL)){Move(interaction,cmd,wrapped);},^(NSString *state){
        MRDAt(session,@"move.completion",[state isEqual:@"blocked"]?@"failed":([state isEqual:@"notPerformed"]?@"cancelled":@"pending"),[state isEqual:@"blocked"]?@"invalid_items":([state isEqual:@"notPerformed"]?@"not_performed":([state isEqual:@"handedOff"]?@"native_handoff":@"pending_sync")),interaction,nil);
        NSDictionary *messages=@{@"blocked":@"移动已拦截：必须是当前来源、明确单封选择、精确发件人和同账号不同目标。未提交任何移动。",@"handedOff":@"已交给 Mail 原生执行队列；尚不能认定提交或服务器同步完成。",@"pendingSync":@"原生交互已执行／待同步；无逐封服务器完成回执，请查看 Mail 的活动与错误。",@"notPerformed":@"原生交互未执行或已取消；未报告移动成功。"};
        dispatch_async(dispatch_get_main_queue(),^{
            if(s->preview!=reportRule || ![BoxKeys(vc) isEqual:reportContext]) return;
            Reason(s,messages[state]);if([state isEqual:@"blocked"]) Notice(vc,s->reason);
        });
    },done);
}
static void (*Create)(id,SEL);
static void CreateHook(id editor,SEL cmd) {
    MRD(@"create.commit",@"pending",@"entered",editor,nil);
    id account=objc_getAssociatedObject(editor,&CreateKey);
    if(account && Get(editor,@"account")!=account) {MRD(@"create.commit",@"failed",@"scope_changed",editor,nil);Notice(editor,@"创建账号发生变化，未提交。请在原账号重新打开新建界面。");return;}
    if(!MRDRequireSubmit(@"create.commit",editor,account && [objc_getAssociatedObject(editor,&DiagnosticGuardKey) boolValue])) {Notice(editor,@"诊断安全模式已阻止最终新建提交。请点原生取消；没有创建邮箱。");return;}
    if(account){objc_setAssociatedObject(editor,&StartedKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);MRD(@"create.commit",@"userSubmitted",@"user_submit",editor,nil);}
    Create(editor,cmd);
}
__attribute__((constructor)) static void InstallNativeRules(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobilemail"]) return;
        char build[64]={0};size_t len=sizeof(build);
        Supported=!sysctlbyname("kern.osversion",build,&len,NULL,0) && !strcmp(build,"20G75");
        MRDDeclare(@"install.build",@"kern.osversion","20G75",build,Supported);
        Class c=NSClassFromString(@"MessageListViewController"),list=object_getClass(NSClassFromString(@"EMMessageList"));
        NSString *factory=@"simpleMessageListForMailboxes:withRepository:shouldTrackOldestItems:shouldUpdateDisplayDate:sortDescriptor:transformPredicate:ignoreMessageAdditionsPredicate:";
        // Preflight the complete query adapter before changing any implementation.
        Method r=class_getInstanceMethod(c,NSSelectorFromString(@"_reloadDataSource")),t=class_getInstanceMethod(c,NSSelectorFromString(@"isThreaded")),f=class_getInstanceMethod(list,NSSelectorFromString(factory));
        if(Supported && r && t && f && !strcmp(method_getTypeEncoding(r),"v16@0:8") && !strcmp(method_getTypeEncoding(t),"B16@0:8") && !strcmp(method_getTypeEncoding(f),"@64@0:8@16@24B32B36@40@?48@56")) {
            Hook(c,@"_reloadDataSource","v16@0:8",(IMP)ReloadHook,(IMP *)&Reload);
            Hook(c,@"isThreaded","B16@0:8",(IMP)ThreadedHook,(IMP *)&Threaded);
            Hook(list,factory,"@64@0:8@16@24B32B36@40@?48@56",(IMP)FactoryHook,(IMP *)&Simple);Ready=YES;
        }
        MRDDeclare(@"install.query",@"_reloadDataSource","v16@0:8",r?method_getTypeEncoding(r):NULL,Ready);
        MRDDeclare(@"install.query",@"isThreaded","B16@0:8",t?method_getTypeEncoding(t):NULL,Ready);
        MRDDeclare(@"install.query",factory,@"@64@0:8@16@24B32B36@40@?48@56".UTF8String,f?method_getTypeEncoding(f):NULL,Ready);
        Class moveClass=NSClassFromString(@"MFMoveMessageTriageInteraction");
        Method md=class_getInstanceMethod(moveClass,NSSelectorFromString(@"setDelegate:")),mp=class_getInstanceMethod(moveClass,NSSelectorFromString(@"performInteractionWithCompletion:"));
        if(Supported && md && mp && !strcmp(method_getTypeEncoding(md),"v24@0:8@16") && !strcmp(method_getTypeEncoding(mp),"v24@0:8@?16")) {
            Hook(moveClass,@"setDelegate:","v24@0:8@16",(IMP)MoveDelegateHook,(IMP *)&MoveDelegate);
            MoveReady=Hook(moveClass,@"performInteractionWithCompletion:","v24@0:8@?16",(IMP)MoveHook,(IMP *)&Move);
        }
        MRDDeclare(@"install.move",@"setDelegate:","v24@0:8@16",md?method_getTypeEncoding(md):NULL,MoveReady);
        MRDDeclare(@"install.move",@"performInteractionWithCompletion:","v24@0:8@?16",mp?method_getTypeEncoding(mp):NULL,MoveReady);
        CreateReady=Supported && Hook(NSClassFromString(@"MailboxEditingController"),@"_applyChangesAndDismissView","v16@0:8",(IMP)CreateHook,(IMP *)&Create);
        Method createMethod=class_getInstanceMethod(NSClassFromString(@"MailboxEditingController"),NSSelectorFromString(@"_applyChangesAndDismissView"));
        MRDDeclare(@"install.create",@"_applyChangesAndDismissView","v16@0:8",createMethod?method_getTypeEncoding(createMethod):NULL,CreateReady);
        SEL appear=@selector(viewDidAppear:);Method m=class_getInstanceMethod(c,appear);
        MRDDeclare(@"install.ui",@"viewDidAppear:","v20@0:8B16",m?method_getTypeEncoding(m):NULL,m && !strcmp(method_getTypeEncoding(m),"v20@0:8B16"));
        if(!m || strcmp(method_getTypeEncoding(m),"v20@0:8B16")) return;
        IMP original=method_getImplementation(m);
        IMP replacement=imp_implementationWithBlock(^(UIViewController *vc,BOOL animated){
            ((void(*)(id,SEL,BOOL))original)(vc,appear,animated);
            MRD(@"ui.lifecycle",@"success",@"original_returned",vc,nil);
            if(![NSStringFromClass(vc.class) isEqual:@"MessageListViewController"]) {MRD(@"ui.lifecycle",@"skipped",@"subclass",vc,nil);return;}
            MR5State *s=State(vc,YES);
            if(s->movePanelPending && !vc.presentedViewController){s->movePanelPending=NO;MRD(@"move.completion",@"cancelled",@"not_observed",vc,nil);}
            MRDInstallButton(vc);
            if(!s->button) s->button=[[UIBarButtonItem alloc] initWithTitle:@"Mail 0.5.1" style:UIBarButtonItemStylePlain target:s action:@selector(show)];
            NSArray *items=vc.navigationItem.rightBarButtonItems?:@[];
            if(![items containsObject:s->button]) vc.navigationItem.rightBarButtonItems=[items arrayByAddingObject:s->button];
            if(!Ready) Reason(s,@"此系统的查询ABI不匹配，保留原始列表；外观仍可单独使用。");
            else if(![s->configuration isEqual:Load()] || ![s->context isEqual:BoxKeys(vc)]) [s reload];
        });
        Hook(c,@"viewDidAppear:","v20@0:8B16",replacement,NULL);
    }
}

void MRDInstallButton(id controller) {
    if(!NSThread.isMainThread || ![controller isKindOfClass:UIViewController.class])return;
    UIViewController *vc=controller;
    if(![@[@"MessageListViewController",@"MailboxPickerOutlineController"] containsObject:NSStringFromClass(vc.class)])return;
    MR5State *s=State(vc,YES);
    if(!s->button)s->button=[[UIBarButtonItem alloc] initWithTitle:@"Mail 0.5.1" style:UIBarButtonItemStylePlain target:s action:@selector(show)];
    NSArray *items=vc.navigationItem.rightBarButtonItems?:@[];
    if(![items containsObject:s->button])vc.navigationItem.rightBarButtonItems=[items arrayByAddingObject:s->button];
    MRD(@"ui.lifecycle",@"success",@"ok",vc,@{@"ready":@(Ready)});
}
