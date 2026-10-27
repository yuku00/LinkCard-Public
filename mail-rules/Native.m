#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/sysctl.h>
#import "NativeCore.h"
#import "Theme.h"

static NSString *const Domain=@"dev.mailrules.native5";
static char StateKey, CreateKey, MoveKey, StartedKey;
static __thread id ReloadOwner;
static __thread NSDictionary *ReloadFrame;
static BOOL Ready, MoveReady, CreateReady;
static BOOL ABI(id o,NSString *name,const char *type) {
    Method m=class_getInstanceMethod(object_getClass(o),NSSelectorFromString(name));
    return m && !strcmp(method_getTypeEncoding(m),type);
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
        if(!a || !b || (accounts[b] && ![accounts[b] isEqual:a])) return @[];
        accounts[b]=a;
        [keys addObject:@[a,b]];
    }
    return keys;
}
static NSMutableDictionary *Load(void) {
    CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("configuration"),(CFStringRef)Domain);
    NSMutableDictionary *d=[raw && [(id)raw isKindOfClass:NSDictionary.class]?(id)raw:@{@"enabled":@NO,@"rules":@[]} mutableCopy];
    if(raw) CFRelease(raw); return [d autorelease];
}
static void Save(NSDictionary *d) {
    CFPreferencesSetAppValue(CFSTR("configuration"),(CFPropertyListRef)d,(CFStringRef)Domain);
    CFPreferencesAppSynchronize((CFStringRef)Domain);
}
static id Address(NSString *s) { return One(NSClassFromString(@"ECEmailAddress"),@"emailAddressWithString:",s); }
static NSString *ReadAddress(id x) {
    if([x isKindOfClass:NSString.class]) return MR5Address(x);
    id address=Get(x,@"emailAddressValue");
    return MR5Address(Get(address?:x,@"stringValue"));
}
static NSPredicate *Sender(NSString *s) {
    s=MR5Address(s); if(!s) return nil;
    static NSMutableDictionary *cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSMutableDictionary new];});
    @synchronized(cache) {
        id saved=cache[s];if(saved) return saved==NSNull.null?nil:saved;
        for(NSUInteger mode=0;mode<2;mode++) {
            @try {
                id arg=mode?Address(s):(id)s;if(!arg) continue;
                NSPredicate *p=One(NSClassFromString(@"EMMessageListItemPredicates"),@"predicateForMessagesWithSender:",arg);
                if(MR5SenderContract(p,s,^id(NSString *value){return Address(value);},^id(NSArray *senders){
                    id model=[[[NSClassFromString(@"EMMessage") alloc] init] autorelease];
                    return Set(model,@"setSenderList:",senders)?model:nil;
                })) {cache[s]=p;return p;}
            } @catch(__unused NSException *e) { /* Only synthetic models were accessed. */ }
        }
        cache[s]=NSNull.null;return nil;
    }
}
static NSPredicate *InBoxes(NSArray *boxes) {
    id p=One(NSClassFromString(@"EMMessageListItemPredicates"),@"predicateForMessagesInMailboxes:",boxes);
    return [p isKindOfClass:NSPredicate.class]?p:nil;
}
static void Notice(UIViewController *owner,NSString *message) {
    if(!owner.viewIfLoaded.window) return;
    UIViewController *p=owner; while(p.presentedViewController) p=p.presentedViewController;
    if([p isKindOfClass:UIAlertController.class]) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Mail 规则与整理" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [p presentViewController:a animated:YES completion:nil];
}
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
}
- (void)show;
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
        Reason(s,@"搜索查询保留 Mail 原生范围；请退出搜索后使用发件人规则和整理。");return nil;
    }
    NSArray *keys=BoxKeys(s->owner);
    if(!keys.count) {Reason(s,@"当前包含非实体邮箱或临时标识：保留原生列表。");return nil;}
    if(s->preview && ![keys isEqual:s->previewContext]) {
        [s->preview release];s->preview=nil;[s->previewContext release];s->previewContext=nil;
    }
    if(s->preview) {
        NSMutableArray *scope=[NSMutableArray array];
        for(id box in Boxes(s->owner)) if([AccountID(box) isEqual:s->preview[@"account"]] && ([s->preview[@"scope"] isEqual:@"account"] || [BoxID(box) isEqual:s->preview[@"mailbox"]])) [scope addObject:box];
        NSPredicate *p=Sender(s->preview[@"sender"]),*b=scope.count?InBoxes(scope):nil;
        if(!p || !b) {Reason(s,@"整理查询验证失败：未修改原生列表，不能移动。");return nil;}
        Reason(s,@"整理预览：精确发件人、单封邮件、当前来源邮箱。未移动任何邮件。");
        return MR5And(b,p);
    }
    NSDictionary *d=Load();
    if(![d[@"enabled"] boolValue]) {Reason(s,@"隐藏总开关关闭：原始列表。规则与移动互相独立。");return nil;}
    NSMutableArray *hidden=[NSMutableArray array];
    for(id box in Boxes(s->owner)) {
        for(NSDictionary *rule in MR5RulesForBox(Array(d[@"rules"]),AccountID(box),BoxID(box))) {
            NSPredicate *p=Sender(rule[@"sender"]), *b=InBoxes(@[box]);
            if(!p || !b) {Reason(s,@"此列表规则未通过原生合成模型自检：保留原始列表。");return nil;}
            [hidden addObject:MR5And(b,p)];
        }
    }
    if(!hidden.count) {Reason(s,@"当前范围没有启用规则：原始列表。");return nil;}
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
    [s->owner presentViewController:a animated:YES completion:nil];
}
static void ChooseBox(MR5State *s,void (^chosen)(id)) {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"选择规则所属账号与邮箱" message:@"不同账号单独保存；账号范围规则仅影响该账号自己的邮箱。" preferredStyle:UIAlertControllerStyleActionSheet];
    for(id box in Boxes(s->owner)) if(AccountID(box) && BoxID(box)) [a addAction:[UIAlertAction actionWithTitle:BoxTitle(box) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){chosen(box);}]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];PresentSheet(s,a);
}
@implementation MR5State
- (void)dealloc {
    [button release];[local release];[context release];[configuration release];[reason release];[preview release];[previewContext release];[super dealloc];
}
- (void)reload { if(!busy) Void(owner,@"_reloadDataSource"); }
- (void)show {
    if(owner.presentedViewController) return;
    NSString *info=[NSString stringWithFormat:@"%@\n地址按 Mail 原生规则忽略大小写，不合并点或 +标签。新邮件随原生查询加载；不承诺未下载历史。",reason?:@"准备就绪"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Mail 0.5.0 · 规则与整理" message:info preferredStyle:UIAlertControllerStyleActionSheet];
    if(Ready) {
        [a addAction:[UIAlertAction actionWithTitle:@"从选中邮件的发件人添加" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
            id selection=Get(Get(owner,@"messageListSelectionModel"),@"currentMessageListItemSelection");
            NSArray *items=Array(Get(selection,@"messageListItems"));
            id message=items.count==1?items.firstObject:nil;
            if(message && ![message isKindOfClass:NSClassFromString(@"EMMessage")]) {
                id display=Get(message,@"displayMessage");
                message=[display isKindOfClass:NSClassFromString(@"EMMessage")]?display:Get(display,@"resultIfAvailable");
            }
            NSString *sender=ReadAddress(Get(message,@"senderAddress"));
            if(!sender) {Notice(owner,@"请先在原生列表选择一封邮件，再打开插件；也可直接输入精确邮箱地址。");return;}
            ChooseBox(self,^(id box){[self edit:nil box:box sender:sender];});
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"输入发件人添加规则" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){ChooseBox(self,^(id box){[self edit:nil box:box sender:nil];});}]];
        [a addAction:[UIAlertAction actionWithTitle:@"管理规则 / 同发件人整理" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self manage];}]];
        [a addAction:[UIAlertAction actionWithTitle:[Load()[@"enabled"] boolValue]?@"关闭隐藏，恢复原始列表":@"开启发件人隐藏" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
            NSMutableDictionary *d=Load();d[@"enabled"]=@(![d[@"enabled"] boolValue]);Save(d);
            [preview release];preview=nil;[previewContext release];previewContext=nil;[self reload];
        }]];
        if(preview) {
            [a addAction:[UIAlertAction actionWithTitle:@"预览已加载邮件并选择移动…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self moveLoaded];}]];
            [a addAction:[UIAlertAction actionWithTitle:@"在此账号新建邮箱…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self createMailbox];}]];
            [a addAction:[UIAlertAction actionWithTitle:@"结束整理，返回规则列表" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[preview release];preview=nil;[previewContext release];previewContext=nil;[self reload];}]];
        }
    }
    [a addAction:[UIAlertAction actionWithTitle:MRThemeEnabled()?@"关闭简洁外观":@"开启简洁外观" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){MRThemeSetEnabled(!MRThemeEnabled());}]];
    [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];PresentSheet(self,a);
}
- (void)edit:(NSDictionary *)rule box:(id)box sender:(NSString *)sender {
    NSString *account=AccountID(box),*mailbox=BoxID(box); if(!account || !mailbox) return;
    __block UIAlertController *a=[UIAlertController alertControllerWithTitle:rule?@"编辑规则":@"添加发件人规则" message:[BoxTitle(box) stringByAppendingString:@"\n仅隐藏，不会自动移动。输入纯邮箱地址，不含显示名。"] preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"sender@example.com";f.text=sender?:rule[@"sender"];f.keyboardType=UIKeyboardTypeEmailAddress;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    for(NSString *scope in @[@"mailbox",@"account"]) [a addAction:[UIAlertAction actionWithTitle:[scope isEqual:@"mailbox"]?@"保存：此邮箱":@"保存：此账号各邮箱" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        NSString *value=MR5Address(a.textFields.firstObject.text);
        if(!value || !Sender(value)) {dispatch_async(dispatch_get_main_queue(),^{Notice(owner,@"地址格式或原生精确匹配验证失败，未保存。支持 ASCII 邮箱地址；国际化域名请使用 punycode。");});return;}
        NSMutableDictionary *d=Load();NSMutableArray *rules=[[Array(d[@"rules"]) mutableCopy] autorelease];
        NSDictionary *entry=@{@"id":rule[@"id"]?:NSUUID.UUID.UUIDString,@"account":account,@"mailbox":mailbox,@"sender":value,@"scope":scope,@"enabled":rule[@"enabled"]?:@YES,@"label":BoxTitle(box)};
        NSIndexSet *old=[rules indexesOfObjectsPassingTest:^BOOL(id x,NSUInteger idx,BOOL *stop){return [x[@"id"] isEqual:entry[@"id"]];}];
        [rules removeObjectsAtIndexes:old];[rules addObject:entry];d[@"rules"]=rules;Save(d);[self reload];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[owner presentViewController:a animated:YES completion:nil];
}
- (void)manage {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"已保存规则" message:@"点击可修改、停用、删除；整理为独立的手动操作，不依赖隐藏开关。" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *rules=Array(Load()[@"rules"]);
    for(NSDictionary *rule in rules) {
        NSString *title=[NSString stringWithFormat:@"%@ %@ · %@",[rule[@"enabled"] boolValue]?@"开":@"停",rule[@"sender"],rule[@"label"]?:@"账号"];
        [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
            UIAlertController *b=[UIAlertController alertControllerWithTitle:rule[@"sender"] message:[NSString stringWithFormat:@"%@\n范围：%@",rule[@"label"]?:@"保存的账号",[rule[@"scope"] isEqual:@"account"]?@"此账号各邮箱":@"指定邮箱"] preferredStyle:UIAlertControllerStyleActionSheet];
            id current=nil;for(id box in Boxes(owner)) if([AccountID(box) isEqual:rule[@"account"]] && ([rule[@"scope"] isEqual:@"account"] || [BoxID(box) isEqual:rule[@"mailbox"]])) {current=box;break;}
            if(current) {
                [b addAction:[UIAlertAction actionWithTitle:@"修改地址与范围" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){[self edit:rule box:current sender:nil];}]];
                [b addAction:[UIAlertAction actionWithTitle:@"打开同发件人整理预览" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){[self beginPreview:rule];}]];
            }
            for(NSString *op in @[@"toggle",@"delete"]) [b addAction:[UIAlertAction actionWithTitle:[op isEqual:@"delete"]?@"删除规则":([rule[@"enabled"] boolValue]?@"停用规则":@"启用规则") style:[op isEqual:@"delete"]?UIAlertActionStyleDestructive:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){
                NSMutableDictionary *d=Load();NSMutableArray *out=[NSMutableArray array];
                for(NSDictionary *r in Array(d[@"rules"])) {
                    if(![r[@"id"] isEqual:rule[@"id"]]) {[out addObject:r];continue;}
                    if([op isEqual:@"toggle"]) {NSMutableDictionary *copy=[[r mutableCopy] autorelease];copy[@"enabled"]=@(![r[@"enabled"] boolValue]);[out addObject:copy];}
                }
                d[@"rules"]=out;Save(d);[self reload];
            }]];
            [b addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];PresentSheet(self,b);
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];PresentSheet(self,a);
}
- (void)beginPreview:(NSDictionary *)rule {
    if(!MoveReady) {Notice(owner,@"原生移动交互边界不可用，未开启整理。隐藏规则仍可使用。");return;}
    if(busy) return;
    if(!BoxKeys(owner).count || Flag(owner,@"isSearchViewController") || Flag(owner,@"isSearching")) {Notice(owner,@"当前搜索或邮箱身份范围无法核验，未开启整理。请返回实体邮箱列表。");return;}
    Void(Get(owner,@"messageListSelectionModel"),@"clearAll");
    Void(Get(owner,@"messageListSelectionModel"),@"disableSelectAll");
    [preview release];preview=[rule copy];[previewContext release];previewContext=[BoxKeys(owner) copy];[self reload];
    if(local) Notice(owner,@"已进入精确发件人单封列表。通过「插件 → 预览已加载邮件并选择移动」核对数量，再由原生移动面板选择目标。同账号新建邮箱也是独立操作，不自动移动。退出整理会恢复原生查询，不回放旧账号状态。");
}
- (void)moveLoaded {
    if(busy || !preview || !local || ![BoxKeys(owner) isEqual:previewContext]) return;
    id ds=Get(owner,@"dataSource");
    id snapshot=Get(Get(ds,@"dataSource"),@"snapshot");
    NSArray *allIDs=Array(Get(snapshot,@"itemIdentifiers"));
    NSMutableArray *items=[NSMutableArray array],*ids=[NSMutableArray array];
    // No synchronous future.result: never block the Mail UI waiting for the daemon.
    for(id itemID in allIDs) {
        id future=One(ds,@"messageListItemForItemID:",itemID);
        id item=[future isKindOfClass:NSClassFromString(@"EMMessage")]?future:Get(future,@"resultIfAvailable");
        if(item && ValidItems(self,@[item],@[itemID])) {[items addObject:item];[ids addObject:itemID];}
    }
    if(!items.count) {Notice(owner,@"暂无已加载且通过逐封核对的匹配邮件。没有提交移动；可等待列表自然加载后重试。");return;}
    NSArray *capturedContext=[[previewContext copy] autorelease];
    NSDictionary *capturedRule=[[preview copy] autorelease];
    NSString *text=[NSString stringWithFormat:@"发件人：%@\n来源：%@（仅当前列表范围）\n已核对 %lu 封；尚未加载的邮件不包含。\n下一步由 Mail 原生面板选择同账号目标，选择目标会执行移动并可能同步其他设备。不会移动整个混合会话。",preview[@"sender"],preview[@"label"],(unsigned long)items.count];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"核对批量移动" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"选择同账号目标…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        if(![preview isEqual:capturedRule] || ![BoxKeys(owner) isEqual:capturedContext] || !ValidItems(self,items,ids)) {Notice(owner,@"来源或邮件集合已变化，未移动。请重新预览。");return;}
        id model=Get(owner,@"messageListSelectionModel");
        if(!ABI(model,@"clearAll","v16@0:8") || !ABI(model,@"disableSelectAll","v16@0:8") || !ABI(model,@"selectItemWithItemID:","@24@0:8@16") || !ABI(owner,@"_showTransferPickerForNonPredictiveMoveOfMessages:","v24@0:8@16")) {Notice(owner,@"原生选择/移动接口不匹配，未提交。");return;}
        Void(model,@"clearAll");Void(model,@"disableSelectAll");
        for(id itemID in ids) One(model,@"selectItemWithItemID:",itemID);
        NSArray *selected=Array(Get(Get(model,@"currentMessageListItemSelection"),@"messageListItems"));
        if(Flag(model,@"isSelectAll") || !ValidItems(self,selected,ids)) {Void(model,@"clearAll");Notice(owner,@"原生选择尚未稳定，未打开移动；请在列表加载完成后重试。");return;}
        Set(owner,@"_showTransferPickerForNonPredictiveMoveOfMessages:",selected);
        Reason(self,@"已打开原生目标选择；尚未确认执行。仅接受同账号且逐封精确匹配的选择。");
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[owner presentViewController:a animated:YES completion:nil];
}
- (void)createMailbox {
    if(!CreateReady) {Notice(owner,@"原生新建边界不可用；可以继续使用规则和已有目录移动。");return;}
    if(!preview || !local || Flag(owner,@"isSearchViewController") || Flag(owner,@"isSearching") || !MR5Context(owner,owner,BoxKeys(owner),previewContext)) {Notice(owner,@"当前来源范围无效或已变化，未打开新建界面。");return;}
    id box=nil;for(id b in Boxes(owner)) if([AccountID(b) isEqual:preview[@"account"]]) {box=b;break;}
    id account=One(Get(owner,@"accountsProvider"),@"legacyMailAccountForObjectID:",Get(box,@"accountIdentifier"));
    Class cls=NSClassFromString(@"MailboxEditingController");
    id raw=[cls alloc];
    if(!account || !ABI(raw,@"initWithMailbox:account:validAccounts:","@40@0:8@16@24@32")) {[raw release];Notice(owner,@"该账号的原生新建邮箱接口不可用；未创建也未移动。");return;}
    UIViewController *editor=((id(*)(id,SEL,id,id,id))objc_msgSend)(raw,NSSelectorFromString(@"initWithMailbox:account:validAccounts:"),nil,account,@[account]);
    if(!Set(editor,@"setDelegate:",self)) {[editor release];return;}
    objc_setAssociatedObject(editor,&CreateKey,account,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UINavigationController *nav=[[[UINavigationController alloc] initWithRootViewController:editor] autorelease];
    [owner presentViewController:nav animated:YES completion:nil];[editor release];
    Reason(self,@"原生新建界面：保存由 Mail 自身队列执行。创建后请等待目录出现，再重新选择移动目标。");
}
- (void)mailboxEditingControllerDidFinish:(UIViewController *)controller {
    if(!objc_getAssociatedObject(controller,&CreateKey)) return;
    [owner dismissViewControllerAnimated:YES completion:nil];
    Reason(self,@"新建界面已结束，不等于服务端创建完成。请确认邮箱已出现；本插件未自动移动任何邮件。");
}
@end
static void (*Reload)(id,SEL);
static BOOL (*Threaded)(id,SEL);
static MR5ListFactory Simple;
static void ReloadHook(id vc,SEL cmd) {
    id previous=ReloadOwner;ReloadOwner=vc;
    NSDictionary *previousFrame=ReloadFrame;ReloadFrame=nil;
    @try {
        if(!Ready || ![NSStringFromClass([vc class]) isEqual:@"MessageListViewController"] || !NSThread.isMainThread) {Reload(vc,cmd);return;}
        MR5State *s=State(vc,YES);
        NSPredicate *next=nil;
        @try {next=BuildLocal(s);}
        @catch(__unused NSException *e) {Reason(s,@"原生模型验证异常：仅清理插件状态，保留当前原生上下文。");}
        if(![s->local isEqual:next] && (s->local || next)) {
            Void(Get(vc,@"messageListSelectionModel"),@"clearAll");
            Void(Get(vc,@"messageListSelectionModel"),@"disableSelectAll");
        }
        [s->local release];s->local=[next retain];
        [s->context release];s->context=[BoxKeys(vc) copy];
        [s->configuration release];s->configuration=[Load() copy];
        if(next) ReloadFrame=[@{@"owner":vc,@"boxes":Boxes(vc),@"keys":s->context,@"local":next} copy];
        Reload(vc,cmd);
    } @finally {
        [ReloadFrame release];ReloadFrame=previousFrame;
        ReloadOwner=previous;
    }
}
static BOOL ThreadedHook(id vc,SEL cmd) {
    MR5State *s=State(vc,NO);
    return s && s->local && !Flag(vc,@"isSearchViewController") && !Flag(vc,@"isSearching") && [s->context isEqual:BoxKeys(vc)]?NO:Threaded(vc,cmd);
}
static id FactoryHook(id cls,SEL cmd,id boxes,id repository,BOOL oldest,BOOL display,id sort,MR5PredicateTransform transform,id ignore) {
    NSDictionary *frame=ReloadFrame;
    NSPredicate *local=nil;
    if(frame && MR5Context(ReloadOwner,frame[@"owner"],BoxKeys(ReloadOwner),frame[@"keys"]) && [Array(boxes) isEqual:frame[@"boxes"]]) local=frame[@"local"];
    return MR5InvokeFactory(Simple,cls,cmd,boxes,repository,oldest,display,sort,transform,ignore,local);
}
static BOOL Hook(Class cls,NSString *name,const char *type,IMP replacement,IMP *original) {
    SEL sel=NSSelectorFromString(name);Method m=class_getInstanceMethod(cls,sel);
    if(!m || strcmp(method_getTypeEncoding(m),type)) return NO;
    if(original) *original=method_getImplementation(m);
    if(!class_addMethod(cls,sel,replacement,type)) method_setImplementation(m,replacement);
    return YES;
}
static void (*Move)(id,SEL,id),(*MoveDelegate)(id,SEL,id);
static void MoveDelegateHook(id interaction,SEL cmd,id delegate) {
    MoveDelegate(interaction,cmd,delegate);
    MR5State *s=State(delegate,NO);
    if(s && s->preview && !objc_getAssociatedObject(interaction,&MoveKey)) {
        NSDictionary *stamp=@{@"rule":s->preview,@"context":s->previewContext?:@[],@"owner":[NSValue valueWithNonretainedObject:delegate]};
        objc_setAssociatedObject(interaction,&MoveKey,stamp,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Never erase an existing stamp when a native interaction loses its delegate.
}
static void MoveHook(id interaction,SEL cmd,id completion) {
    id vc=Get(interaction,@"delegate");MR5State *s=State(vc,NO);
    NSDictionary *stamp=objc_getAssociatedObject(interaction,&MoveKey);
    if(!stamp && (!s || !s->preview)) {Move(interaction,cmd,completion);return;}
    if(!NSThread.isMainThread || !s || !s->preview || !stamp || [stamp[@"owner"] nonretainedObjectValue]!=vc || ![s->preview isEqual:stamp[@"rule"]] || ![BoxKeys(vc) isEqual:stamp[@"context"]]) {
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
        valid=explicitSelection && object_getClass(explicitSelection)==object_getClass(selection) && [AccountID(target) isEqual:s->preview[@"account"]] && ![PreviewBoxes(s) containsObject:BoxID(target)] && ValidItems(s,items,ids);
    } @catch(__unused NSException *e) {valid=NO;}
    if(valid) {
        @synchronized(interaction) {
            if(objc_getAssociatedObject(interaction,&StartedKey)) {if(done) done(interaction,NO);return;}
            objc_setAssociatedObject(interaction,&StartedKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    NSDictionary *reportRule=s->preview;
    NSArray *reportContext=s->previewContext;
    MR5Perform(valid,interaction,^(void (^wrapped)(id,BOOL)){Move(interaction,cmd,wrapped);},^(NSString *state){
        NSDictionary *messages=@{@"blocked":@"移动已拦截：必须是当前来源、明确单封选择、精确发件人和同账号不同目标。未提交任何移动。",@"handedOff":@"已交给 Mail 原生执行队列；尚不能认定提交或服务器同步完成。",@"pendingSync":@"原生交互已执行／待同步；无逐封服务器完成回执，请查看 Mail 的活动与错误。",@"notPerformed":@"原生交互未执行或已取消；未报告移动成功。"};
        dispatch_async(dispatch_get_main_queue(),^{
            if(s->preview!=reportRule || ![BoxKeys(vc) isEqual:reportContext]) return;
            Reason(s,messages[state]);if([state isEqual:@"blocked"]) Notice(vc,s->reason);
        });
    },done);
}
static void (*Create)(id,SEL);
static void CreateHook(id editor,SEL cmd) {
    id account=objc_getAssociatedObject(editor,&CreateKey);
    if(account && Get(editor,@"account")!=account) {Notice(editor,@"创建账号发生变化，未提交。请在原账号重新打开新建界面。");return;}
    Create(editor,cmd);
}
__attribute__((constructor)) static void InstallNativeRules(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobilemail"]) return;
        char build[64]={0};size_t len=sizeof(build);
        if(sysctlbyname("kern.osversion",build,&len,NULL,0) || strcmp(build,"20G75")) return;
        Class c=NSClassFromString(@"MessageListViewController"),list=object_getClass(NSClassFromString(@"EMMessageList"));
        NSString *factory=@"simpleMessageListForMailboxes:withRepository:shouldTrackOldestItems:shouldUpdateDisplayDate:sortDescriptor:transformPredicate:ignoreMessageAdditionsPredicate:";
        // Preflight the complete query adapter before changing any implementation.
        Method r=class_getInstanceMethod(c,NSSelectorFromString(@"_reloadDataSource")),t=class_getInstanceMethod(c,NSSelectorFromString(@"isThreaded")),f=class_getInstanceMethod(list,NSSelectorFromString(factory));
        if(r && t && f && !strcmp(method_getTypeEncoding(r),"v16@0:8") && !strcmp(method_getTypeEncoding(t),"B16@0:8") && !strcmp(method_getTypeEncoding(f),"@64@0:8@16@24B32B36@40@?48@56")) {
            Hook(c,@"_reloadDataSource","v16@0:8",(IMP)ReloadHook,(IMP *)&Reload);
            Hook(c,@"isThreaded","B16@0:8",(IMP)ThreadedHook,(IMP *)&Threaded);
            Hook(list,factory,"@64@0:8@16@24B32B36@40@?48@56",(IMP)FactoryHook,(IMP *)&Simple);Ready=YES;
        }
        Class moveClass=NSClassFromString(@"MFMoveMessageTriageInteraction");
        Method md=class_getInstanceMethod(moveClass,NSSelectorFromString(@"setDelegate:")),mp=class_getInstanceMethod(moveClass,NSSelectorFromString(@"performInteractionWithCompletion:"));
        if(md && mp && !strcmp(method_getTypeEncoding(md),"v24@0:8@16") && !strcmp(method_getTypeEncoding(mp),"v24@0:8@?16")) {
            Hook(moveClass,@"setDelegate:","v24@0:8@16",(IMP)MoveDelegateHook,(IMP *)&MoveDelegate);
            MoveReady=Hook(moveClass,@"performInteractionWithCompletion:","v24@0:8@?16",(IMP)MoveHook,(IMP *)&Move);
        }
        CreateReady=Hook(NSClassFromString(@"MailboxEditingController"),@"_applyChangesAndDismissView","v16@0:8",(IMP)CreateHook,(IMP *)&Create);
        SEL appear=@selector(viewDidAppear:);Method m=class_getInstanceMethod(c,appear);
        if(!m || strcmp(method_getTypeEncoding(m),"v20@0:8B16")) return;
        IMP original=method_getImplementation(m);
        IMP replacement=imp_implementationWithBlock(^(UIViewController *vc,BOOL animated){
            ((void(*)(id,SEL,BOOL))original)(vc,appear,animated);
            if(![NSStringFromClass(vc.class) isEqual:@"MessageListViewController"]) return;
            MR5State *s=State(vc,YES);
            if(!s->button) s->button=[[UIBarButtonItem alloc] initWithTitle:@"插件" style:UIBarButtonItemStylePlain target:s action:@selector(show)];
            NSArray *items=vc.navigationItem.rightBarButtonItems?:@[];
            if(![items containsObject:s->button]) vc.navigationItem.rightBarButtonItems=[items arrayByAddingObject:s->button];
            if(!Ready) Reason(s,@"此系统的查询ABI不匹配，保留原始列表；外观仍可单独使用。");
            else if(![s->configuration isEqual:Load()] || ![s->context isEqual:BoxKeys(vc)]) [s reload];
        });
        Hook(c,@"viewDidAppear:","v20@0:8B16",replacement,NULL);
    }
}
