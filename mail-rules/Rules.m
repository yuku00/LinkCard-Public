#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/sysctl.h>
#import "RuleCore.h"
#import "Diagnostics.h"

static NSString *const Domain = @"dev.mailrules.rules";
static char StateKey, SourceKey;
static BOOL HooksReady;
static BOOL ABI(id object, NSString *name, const char *encoding) {
    Method m = class_getInstanceMethod(object_getClass(object), NSSelectorFromString(name));
    return m && strcmp(method_getTypeEncoding(m), encoding) == 0;
}
static id Get(id o, NSString *s) { return ((id(*)(id,SEL))objc_msgSend)(o, NSSelectorFromString(s)); }
static BOOL Flag(id o, NSString *s) { return ((BOOL(*)(id,SEL))objc_msgSend)(o, NSSelectorFromString(s)); }
static NSMutableDictionary *Load(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("accounts"), (CFStringRef)Domain);
    NSMutableDictionary *result = [value && [(id)value isKindOfClass:NSDictionary.class] ? (id)value : @{} mutableCopy];
    if (value) CFRelease(value);
    return [result autorelease];
}
static void Save(NSDictionary *accounts) {
    CFPreferencesSetAppValue(CFSTR("accounts"), (CFDictionaryRef)accounts, (CFStringRef)Domain);
    CFPreferencesAppSynchronize((CFStringRef)Domain);
}
static NSString *Identity(id object) {
    if ([object isKindOfClass:NSString.class]) return [object length] ? object : nil; // 0.2 compatibility
    if (![object isKindOfClass:NSClassFromString(@"EMObjectID")] || !ABI(object,@"isEphemeral","B16@0:8") || Flag(object,@"isEphemeral") || !ABI(object,@"serializedRepresentation","@16@0:8")) return nil;
    @try {
        id value=Get(object,@"serializedRepresentation");
        CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("identities"),(CFStringRef)Domain);
        NSMutableDictionary *ids=[raw && [(id)raw isKindOfClass:NSDictionary.class] ? (id)raw : @{} mutableCopy];
        if(raw) CFRelease(raw);
        NSUInteger count=ids.count;
        NSString *key=MRIdentityKey(value,ids);
        if(ids.count!=count) {CFPreferencesSetAppValue(CFSTR("identities"),(CFDictionaryRef)ids,(CFStringRef)Domain); CFPreferencesAppSynchronize((CFStringRef)Domain);}
        [[key retain] autorelease]; [ids release]; return key;
    } @catch (__unused NSException *e) { return nil; }
}
static NSArray *Boxes(id vc) {
    if (!ABI(vc,@"mailboxes","@16@0:8")) return @[];
    id boxes=Get(vc,@"mailboxes");
    return [boxes isKindOfClass:NSArray.class] ? boxes : ([boxes isKindOfClass:NSSet.class] ? [boxes allObjects] : @[]);
}
static NSString *BoxAccount(id box) {
    if (![box isKindOfClass:NSClassFromString(@"EMMailbox")] || !ABI(box,@"accountIdentifier","@16@0:8") || !ABI(box,@"isSmartMailbox","B16@0:8") || Flag(box,@"isSmartMailbox")) return nil;
    return Identity(Get(box,@"accountIdentifier"));
}
static NSString *AccountTitle(id vc, NSString *key) {
    NSString *suffix=key.length>8 ? [key substringFromIndex:key.length-8] : key;
    for (id box in Boxes(vc)) {
        if (![BoxAccount(box) isEqual:key] || !ABI(box,@"account","@16@0:8")) continue;
        id account=Get(box,@"account");
        if (!ABI(account,@"objectID","@16@0:8") || ![Get(account,@"objectID") isEqual:Get(box,@"accountIdentifier")] || !ABI(account,@"name","@16@0:8")) continue;
        id name=Get(account,@"name");
        if ([name isKindOfClass:NSString.class] && [name length]) return [NSString stringWithFormat:@"%@ · %@",name,suffix];
    }
    return [NSString stringWithFormat:@"本地账号 · %@",suffix ?: @"未识别"];
}
static NSString *EditingAccount(id vc) {
    NSArray *boxes=Boxes(vc);
    return boxes.count==1 ? BoxAccount(boxes.firstObject) : nil;
}
static NSString *ScopeReason(id vc) {
    NSArray *boxes=Boxes(vc);
    if (boxes.count!=1) return @"当前合并列表尚缺原始账号与查询逐消息归属契约；可分别编辑下列账号规则，但此列表不隐藏。";
    id box=boxes.firstObject;
    if (!BoxAccount(box)) return @"账号稳定标识不可用（不是可持久化 EMObjectID，或标识为临时值）。";
    for (NSString *s in @[@"isThreaded",@"isSearchViewController",@"isSearching",@"_isInSearch"]) if (!ABI(vc,s,"B16@0:8")) return [@"布尔接口签名不匹配：" stringByAppendingString:s];
    if (Flag(vc,@"isThreaded")) return @"当前开启会话分组：逐消息过滤契约尚未确认，未把代表发件人当整条会话隐藏。规则仍可编辑。";
    if (Flag(vc,@"isSearchViewController") || Flag(vc,@"isSearching") || Flag(vc,@"_isInSearch")) return @"搜索查询源范围契约尚未确认，此处暂不隐藏；不会把收件箱规则扩展为所有邮件规则。";
    if (!ABI(box,@"isInboxMailbox","B16@0:8") || !ABI(box,@"isSmartMailbox","B16@0:8")) return @"邮箱类型布尔接口不匹配。";
    if (Flag(box,@"isSmartMailbox")) return @"智能邮箱原始账号归属未确认，此处暂不隐藏。";
    if (!Flag(box,@"isInboxMailbox")) return @"仅原收件箱可隐藏；其他目录仍可编辑规则。";
    return nil;
}
static NSString *Account(id vc) { return ScopeReason(vc) ? nil : EditingAccount(vc); }
static id Address(NSString *s) {
    Class c=NSClassFromString(@"ECEmailAddress");
    if (!ABI(c,@"emailAddressWithString:","@24@0:8@16")) return nil;
    id a=((id(*)(id,SEL,id))objc_msgSend)(c,NSSelectorFromString(@"emailAddressWithString:"),s);
    if (![MRReadAddress(a) isEqual:MRNormalize(s)]) return nil;
    return a;
}
static NSPredicate *NativeInclude(NSString *s, BOOL stringArgument) {
    Class c=NSClassFromString(@"EMMessageListItemPredicates");
    if (!ABI(c,@"predicateForMessagesWithSender:","@24@0:8@16")) return nil;
    id arg=stringArgument ? (id)s : Address(s);
    if (!arg) return nil;
    id p=((id(*)(id,SEL,id))objc_msgSend)(c,NSSelectorFromString(@"predicateForMessagesWithSender:"),arg);
    if (MRDiagnosticActive()) MRDiagnosticRecord(@"sender-factory",@{@"synthetic":@([s hasSuffix:@"@fixture.invalid"]),@"ast":MRPredicateShape(p)});
    return [p isKindOfClass:NSPredicate.class] ? p : nil;
}
static BOOL ValidateNativeSender(NSPredicate *predicate, NSString *address) {
    Class model=NSClassFromString(@"EMMessage");
    if (!model) return NO;
    return MRValidateNativeSenderPredicate(predicate,address,^id(NSString *s){return Address(s);},^id(NSArray *senders){
        id message=[[model alloc] init];
        if (!ABI(message,@"setSenderList:","v24@0:8@16") || !ABI(message,@"senderList","@16@0:8")) { [message release]; return nil; }
        ((void(*)(id,SEL,id))objc_msgSend)(message,NSSelectorFromString(@"setSenderList:"),senders);
        return [message autorelease];
    });
}
static NSInteger PredicateMode = -2;
static NSString *SenderKey;
static NSComparisonPredicateOptions SenderOptions;
static NSPredicate *Exclusion(NSArray *rules, NSString **reason) {
    @try {
        if (PredicateMode == -2) {
            PredicateMode = -1;
            for (NSInteger mode=0;mode<2;mode++) {
                @try {
                    NSPredicate *p=NativeInclude(@"mr.fixture+keep@fixture.invalid",mode==1);
                    if (ValidateNativeSender(p,@"mr.fixture+keep@fixture.invalid")) {
                        PredicateMode=mode; SenderKey=[((NSComparisonPredicate *)p).leftExpression.keyPath copy];
                        SenderOptions=((NSComparisonPredicate *)p).options; break;
                    }
                } @catch (__unused NSException *e) { /* Try the other documented convertible representation. */ }
            }
        }
        if (PredicateMode < 0) { *reason=@"原生发件人谓词未通过单封精确匹配自检，隐藏已停用。未读取或记录真实邮件。"; return nil; }
        NSMutableArray *predicates=[NSMutableArray array];
        for (NSDictionary *rule in rules) {
            if (![rule isKindOfClass:NSDictionary.class] || ![rule[@"enabled"] boolValue]) continue;
            NSString *s=MRNormalize(rule[@"address"]);
            if (!s) continue;
            NSPredicate *p=NativeInclude(s,PredicateMode==1);
            if (!ValidateNativeSender(p,s) || ![((NSComparisonPredicate *)p).leftExpression.keyPath isEqual:SenderKey] || ((NSComparisonPredicate *)p).options != SenderOptions) { *reason=@"此地址的原生精确匹配验证失败，本账号隐藏已停用。"; return nil; }
            [predicates addObject:p];
        }
        if (!predicates.count) { *reason=@"本账号没有已启用的有效规则：未隐藏任何邮件。"; return nil; }
        return [NSCompoundPredicate notPredicateWithSubpredicate:[NSCompoundPredicate orPredicateWithSubpredicates:predicates]];
    } @catch (__unused NSException *e) { *reason=@"原生谓词接口拒绝合成测试，隐藏已停用。"; return nil; }
}

@interface MRState : NSObject {
@public
    UIViewController *owner; // assign; cleared by the base-class dealloc hook (also covers KVO subclasses).
    id source;
    id boundMailbox;
    NSPredicate *exclude;
    NSMutableArray *calls;
    UIBarButtonItem *button;
    NSString *status;
    NSString *activeAccount;
    BOOL visible;
    NSUInteger depth;
}
- (void)restore;
- (void)refresh;
- (void)showRules;
- (void)showAccount:(NSString *)account;
- (void)diagnostics;
- (void)edit:(NSUInteger)index account:(NSString *)account;
- (void)manage:(NSUInteger)index account:(NSString *)account;
@end
static UIViewController *Presenter(MRState *s) {
    UIViewController *vc=s->owner;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed && ![vc.presentedViewController isKindOfClass:UIAlertController.class] && ![vc.presentedViewController isKindOfClass:UIActivityViewController.class]) vc=vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc=[(UINavigationController *)vc topViewController];
    return vc;
}
static BOOL CanEdit(MRState *s, NSString *account) {
    if (!s->owner || !account.length) return NO;
    for (id box in Boxes(s->owner)) if ([BoxAccount(box) isEqual:account]) return YES;
    return NO;
}
@interface MRRulesController : UITableViewController {
    MRState *_state;
    NSString *_account;
}
- (instancetype)initWithState:(MRState *)state account:(NSString *)account;
@end
static void (*Apply)(id,SEL,id,id);
static void (*ApplySection)(id,SEL,id,id,id);
static MRState *State(id vc, BOOL create) {
    MRState *s=objc_getAssociatedObject(vc,&StateKey);
    if (!s && create) {
        s=[[[MRState alloc] init] autorelease]; s->owner=vc;
        objc_setAssociatedObject(vc,&StateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return s;
}
static id Unnull(id x) {return x==NSNull.null ? nil : x;}
static void Remember(MRState *s, id p, id i, id section, BOOL sectional) {
    if (!sectional) [s->calls removeAllObjects];
    else {
        NSIndexSet *old=[s->calls indexesOfObjectsPassingTest:^BOOL(NSArray *a,NSUInteger n,BOOL *stop){return [a[3] boolValue] && [Unnull(a[2]) isEqual:section];}];
        [s->calls removeObjectsAtIndexes:old];
    }
    [s->calls addObject:@[p ?: NSNull.null,i ?: NSNull.null,section ?: NSNull.null,@(sectional)]];
}
static BOOL ContextMatches(MRState *s) {
    return s && s->owner && ABI(s->owner,@"dataSource","@16@0:8") &&
        MRContextMatches(s->owner,s->source,Get(s->owner,@"dataSource"),s->activeAccount,EditingAccount(s->owner),s->boundMailbox,Boxes(s->owner).firstObject);
}
static NSPredicate *Filter(MRState *s, id p, NSString *section) {
    if (!s || s->depth || !s->exclude) return p;
    // During preview keep the current filter stable; explicit scope transitions restore before changing scope.
    if (!ContextMatches(s) || ![Account(s->owner) isEqual:s->activeAccount]) { [s->exclude release]; s->exclude=nil; [s->status release]; s->status=[@"账号、邮箱或数据源已变化：暂停隐藏，等待原生列表更新。" copy]; }
    return MRCombineSection(p,s->exclude,section);
}
static void ApplyHook(id ds,SEL cmd,id p,id ignored) {
    if (MRDiagnosticActive()) MRDiagnosticRecord(@"natural-filter",@{@"sourceClass":NSStringFromClass([ds class]),@"ast":MRPredicateShape(p),@"ignoredAST":MRPredicateShape(ignored)});
    MRState *s=objc_getAssociatedObject(ds,&SourceKey);
    if (!s || s->depth) { Apply(ds,cmd,p,ignored); return; }
    Remember(s,p,ignored,nil,NO);
    s->depth++;
    @try {
        // A system global update must stay global, but our rule belongs only to
        // MessageListSectionRecent (the section used by MobileMail's controller).
        Apply(ds,cmd,p,ignored);
    } @finally {s->depth--;}
    id combined=Filter(s,p,@"MessageListSectionRecent");
    if (combined!=p) {
        s->depth++;
        @try { ApplySection(ds,NSSelectorFromString(@"applyFilterPredicate:ignoreMessagesPredicate:section:"),combined,ignored,@"MessageListSectionRecent"); }
        @finally {s->depth--;}
    }
}
static void SectionHook(id ds,SEL cmd,id p,id ignored,id section) {
    MRState *s=objc_getAssociatedObject(ds,&SourceKey);
    if (!s || s->depth) {ApplySection(ds,cmd,p,ignored,section);return;}
    Remember(s,p,ignored,section,YES);
    id combined=Filter(s,p,section);
    s->depth++; @try {ApplySection(ds,cmd,combined,ignored,section);} @finally {s->depth--;}
}

@implementation MRState
- (instancetype)init { if ((self=[super init])) calls=[NSMutableArray new]; return self; }
- (void)restore {
    if (source) {
        BOOL ownsSource=objc_getAssociatedObject(source,&SourceKey)==self && ContextMatches(self);
        depth++;
        @try {
            for (NSArray *a in (ownsSource ? calls : @[])) {
                if ([a[3] boolValue]) ApplySection(source,NSSelectorFromString(@"applyFilterPredicate:ignoreMessagesPredicate:section:"),Unnull(a[0]),Unnull(a[1]),Unnull(a[2]));
                else Apply(source,NSSelectorFromString(@"applyFilterPredicate:ignoreMessagesPredicate:"),Unnull(a[0]),Unnull(a[1]));
            }
        } @finally {depth--;}
        if (objc_getAssociatedObject(source,&SourceKey)==self) objc_setAssociatedObject(source,&SourceKey,nil,OBJC_ASSOCIATION_ASSIGN);
        [source release]; source=nil;
    }
    [boundMailbox release]; boundMailbox=nil;
    [calls removeAllObjects]; [exclude release]; exclude=nil;
    [activeAccount release]; activeAccount=nil;
}
- (void)refresh {
    UIViewController *presenter=Presenter(self);
    if ([presenter isKindOfClass:MRRulesController.class]) [[(UITableViewController *)presenter tableView] reloadData];
    if (!visible || depth) return;
    NSString *account=Account(owner);
    NSString *scope=ScopeReason(owner);
    if (!HooksReady || !account) { [status release]; status=[(scope ?: @"原生过滤钩子未就绪。") copy]; [self restore]; return; }
    if (!ABI(owner,@"dataSource","@16@0:8")) { [self restore]; [status release]; status=[@"数据源接口签名不匹配：隐藏已暂停。" copy]; return; }
    id ds=Get(owner,@"dataSource");
    if (![ds isKindOfClass:NSClassFromString(@"MessageListDataSource")]) { [self restore]; [status release]; status=[@"当前数据源类型未确认：隐藏已暂停。" copy]; return; }
    MRState *other=objc_getAssociatedObject(ds,&SourceKey);
    if (other && other!=self) { [self restore]; [status release]; status=[@"数据源仍属于另一列表：本账号隐藏已暂停，未复用其他账号上下文。" copy]; return; }
    NSDictionary *config=Load()[account];
    NSString *why=nil;
    NSPredicate *next=nil;
    if ([config isKindOfClass:NSDictionary.class] && [config[@"enabled"] boolValue] && [config[@"rules"] isKindOfClass:NSArray.class]) next=Exclusion(config[@"rules"],&why);
    [status release]; status=[why copy];
    if (!next) { [self restore]; return; }
    if (ContextMatches(self) && source==ds && [exclude isEqual:next] && [activeAccount isEqual:account]) return;
    if (!ABI(owner,@"currentFilterPredicate","@16@0:8") || !ABI(owner,@"currentMessagesToIgnorePredicate","@16@0:8") || !ABI(owner,@"_inMultiSelectionMode","B16@0:8") || !ABI(owner,@"_exitMultiSelectionForce:","v20@0:8B16")) { [self restore]; return; }
    if (Flag(owner,@"_inMultiSelectionMode")) ((void(*)(id,SEL,BOOL))objc_msgSend)(owner,NSSelectorFromString(@"_exitMultiSelectionForce:"),YES);
    [self restore];
    source=[ds retain]; boundMailbox=[Boxes(owner).firstObject retain]; exclude=[next retain]; activeAccount=[account copy];
    objc_setAssociatedObject(source,&SourceKey,self,OBJC_ASSOCIATION_ASSIGN);
    SectionHook(source,NSSelectorFromString(@"applyFilterPredicate:ignoreMessagesPredicate:section:"),Get(owner,@"currentFilterPredicate"),Get(owner,@"currentMessagesToIgnorePredicate"),@"MessageListSectionRecent");
}
- (void)showRules {
    [self refresh];
    NSString *account=EditingAccount(owner);
    if (account) { [self showAccount:account]; return; }
    NSMutableArray *accounts=[NSMutableArray array];
    for (id box in Boxes(owner)) {NSString *key=BoxAccount(box); if(key && ![accounts containsObject:key]) [accounts addObject:key];}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"选择规则账号" message:ScopeReason(owner) preferredStyle:UIAlertControllerStyleActionSheet];
    [accounts enumerateObjectsUsingBlock:^(NSString *key,NSUInteger idx,BOOL *stop){
        [a addAction:[UIAlertAction actionWithTitle:AccountTitle(owner,key) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self showAccount:key];}]];
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"最后一次定向诊断（手动）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self diagnostics];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem=button;
    a.popoverPresentationController.sourceView=Presenter(self).view;
    a.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(Presenter(self).view.bounds),CGRectGetMidY(Presenter(self).view.bounds),1,1);
    [Presenter(self) presentViewController:a animated:YES completion:nil];
}
- (void)showAccount:(NSString *)account {
    if (!CanEdit(self,account)) return;
    MRRulesController *list=[[[MRRulesController alloc] initWithState:self account:account] autorelease];
    UINavigationController *nav=[[[UINavigationController alloc] initWithRootViewController:list] autorelease];
    nav.modalPresentationStyle=UIModalPresentationFormSheet;
    [owner presentViewController:nav animated:YES completion:nil];
}
- (void)diagnostics {
    MRDiagnosticStart();
    for (NSInteger mode=0;mode<2;mode++) {
        @try {
            NSPredicate *p=NativeInclude(@"mr.fixture+keep@fixture.invalid",mode==1);
            BOOL valid=ValidateNativeSender(p,@"mr.fixture+keep@fixture.invalid");
            MRDiagnosticRecord(@"synthetic-validation",@{@"mode":@(mode),@"valid":@(valid)});
        } @catch (__unused NSException *e) { MRDiagnosticRecord(@"synthetic-unavailable",@{@"mode":@(mode)}); }
    }
    NSString *report=MRDiagnosticExport();
    UIActivityViewController *share=[[[UIActivityViewController alloc] initWithActivityItems:@[report ?: @"诊断不可用"] applicationActivities:nil] autorelease];
    share.popoverPresentationController.barButtonItem=button;
    [Presenter(self) presentViewController:share animated:YES completion:nil];
}
- (void)edit:(NSUInteger)index account:(NSString *)account {
    if (!CanEdit(self,account)) return;
    NSDictionary *raw=Load()[account]; NSDictionary *config=[raw isKindOfClass:NSDictionary.class]?raw:@{};
    NSArray *rules=[config[@"rules"] isKindOfClass:NSArray.class]?config[@"rules"]:@[];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:index==NSNotFound?@"添加邮箱":@"编辑邮箱" message:@"输入完整 ASCII 邮箱地址。只规范域名大小写，保留 +tag 和点号。新规则默认停用。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.keyboardType=UIKeyboardTypeEmailAddress; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.autocorrectionType=UITextAutocorrectionTypeNo; if(index<rules.count) f.text=rules[index][@"address"]; }];
    // Capture the field, not the alert, to avoid an alert/action retain cycle under MRC.
    UITextField *field=a.textFields.firstObject;
    [a addAction:[UIAlertAction actionWithTitle:@"保存（停用）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *address=MRNormalize(field.text);
        if (!address) {
            UIAlertController *error=[UIAlertController alertControllerWithTitle:@"邮箱格式无效" message:@"请输入单个完整邮箱，不含显示名、空格或非 ASCII 字符。" preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
            [Presenter(self) presentViewController:error animated:YES completion:nil]; return;
        }
        if (!CanEdit(self,account) || ![Load()[account] ?: @{} isEqual:config]) return;
        NSMutableDictionary *all=Load(); NSMutableDictionary *c=[[config mutableCopy] autorelease]; NSMutableArray *r=[[rules mutableCopy] autorelease];
        NSDictionary *entry=@{@"address":address,@"enabled":@NO};
        if (index<r.count) r[index]=entry; else [r addObject:entry];
        c[@"rules"]=r; all[account]=c; Save(all); [self refresh];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [Presenter(self) presentViewController:a animated:YES completion:nil];
}
- (void)manage:(NSUInteger)index account:(NSString *)account {
    if (!CanEdit(self,account)) return;
    NSMutableDictionary *all=Load(); NSDictionary *config=all[account]; NSArray *rules=config[@"rules"];
    if (index>=rules.count) return;
    NSDictionary *rule=rules[index];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:rule[@"address"] message:@"本账号规则" preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:[rule[@"enabled"] boolValue]?@"停用":@"启用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        if (!CanEdit(self,account) || ![Load()[account] ?: @{} isEqual:config]) return;
        NSMutableDictionary *all=Load(); NSMutableDictionary *c=[[config mutableCopy] autorelease]; NSMutableArray *r=[[rules mutableCopy] autorelease]; NSMutableDictionary *entry=[[rule mutableCopy] autorelease]; entry[@"enabled"]=@(![rule[@"enabled"] boolValue]); r[index]=entry; c[@"rules"]=r; all[account]=c; Save(all); [self refresh];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"编辑" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self edit:index account:account];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"删除规则" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        if (!CanEdit(self,account) || ![Load()[account] ?: @{} isEqual:config]) return;
        NSMutableDictionary *all=Load(); NSMutableDictionary *c=[[config mutableCopy] autorelease]; NSMutableArray *r=[[rules mutableCopy] autorelease]; [r removeObjectAtIndex:index]; c[@"rules"]=r; all[account]=c; Save(all); [self refresh];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem=button;
    a.popoverPresentationController.sourceView=Presenter(self).view;
    a.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(Presenter(self).view.bounds),CGRectGetMidY(Presenter(self).view.bounds),1,1);
    [Presenter(self) presentViewController:a animated:YES completion:nil];
}
- (void)dealloc { [self restore]; [calls release]; [button release]; [status release]; [super dealloc]; }
@end

@implementation MRRulesController
- (instancetype)initWithState:(MRState *)state account:(NSString *)account {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) { _state=[state retain]; _account=[account copy]; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"发件人规则";
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles=YES;
    self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)] autorelease];
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=64;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSDictionary *)config { id c=Load()[_account]; return [c isKindOfClass:NSDictionary.class] ? c : @{}; }
- (NSArray *)rules { id r=[self config][@"rules"]; return [r isKindOfClass:NSArray.class] ? r : @[]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section==0 ? 2 : (section==1 ? (NSInteger)[self rules].count+1 : 1); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"当前账号",@"精确发件人匹配",@"验证"][(NSUInteger)section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if(section==0) return @"开关与下方规则仅属于本页账号。规则数不是邮件数量；不改已读状态、归属或实体位置。";
    if(section==1) return @"新建和编辑后默认停用。保留 +tag 和点号；原生 ANY 不区分大小写的精确相等必须先通过合成模型自检。";
    return @"Mail Rules 0.3.1 · 诊断仅使用合成地址，不读取或导出真实邮件。";
}
- (void)toggleAccount:(UISwitch *)sender {
    if (!CanEdit(_state,_account)) { sender.on=NO; [self.tableView reloadData]; return; }
    NSMutableDictionary *all=Load(); NSMutableDictionary *c=[[[self config] mutableCopy] autorelease];
    c[@"enabled"]=@(sender.on); all[_account]=c; Save(all); [_state refresh]; [self.tableView reloadData];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
    cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.textLabel.adjustsFontForContentSizeCategory=YES; cell.detailTextLabel.adjustsFontForContentSizeCategory=YES;
    cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    BOOL editable=CanEdit(_state,_account);
    if (path.section==0 && path.row==0) {
        cell.textLabel.text=AccountTitle(_state->owner,_account);
        NSString *reason=editable ? ScopeReason(_state->owner) : @"当前邮箱账号已变化，本页编辑和隐藏已暂停；请关闭后重新打开规则。";
        BOOL current=[EditingAccount(_state->owner) isEqual:_account];
        cell.detailTextLabel.text=reason ?: (current && _state->status ? _state->status : (_state->exclude && [_state->activeAccount isEqual:_account] ? @"已通过自检：仅当前账号收件箱列表生效。" : ([[self config][@"enabled"] boolValue] ? @"已启用；关闭规则页后对当前收件箱执行自检，失败则暂停并显示原因。" : @"本账号隐藏已关闭。")));
        cell.imageView.image=[UIImage systemImageNamed:reason ? @"exclamationmark.shield" : @"person.crop.circle"];
        cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else if (path.section==0) {
        cell.textLabel.text=@"启用本账号隐藏";
        UISwitch *toggle=[[[UISwitch alloc] init] autorelease]; toggle.on=[[self config][@"enabled"] boolValue]; toggle.enabled=editable;
        toggle.accessibilityLabel=[@"启用隐藏：" stringByAppendingString:AccountTitle(_state->owner,_account)];
        [toggle addTarget:self action:@selector(toggleAccount:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=toggle;
        cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else if (path.section==1) {
        NSArray *rules=[self rules];
        if ((NSUInteger)path.row==rules.count) { cell.textLabel.text=@"添加发件人邮箱"; cell.textLabel.textColor=editable ? self.view.tintColor : UIColor.secondaryLabelColor; cell.imageView.image=[UIImage systemImageNamed:@"plus.circle.fill"]; }
        else { NSDictionary *rule=rules[(NSUInteger)path.row]; cell.textLabel.text=rule[@"address"]; cell.detailTextLabel.text=[rule[@"enabled"] boolValue]?@"规则已启用 · 仍需账号开关和自检通过":@"规则已停用"; cell.imageView.image=[UIImage systemImageNamed:[rule[@"enabled"] boolValue]?@"checkmark.circle.fill":@"circle"]; }
        cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else {cell.textLabel.text=@"运行合成匹配诊断"; cell.imageView.image=[UIImage systemImageNamed:@"checkmark.shield"]; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (!CanEdit(_state,_account)) { [tableView reloadData]; return; }
    if(path.section==1) { if ((NSUInteger)path.row==[self rules].count) [_state edit:NSNotFound account:_account]; else [_state manage:(NSUInteger)path.row account:_account]; }
    if(path.section==2) [_state diagnostics];
}
- (void)dealloc { [_state release]; [_account release]; [super dealloc]; }
@end

static void (*DidAppear)(id,SEL,BOOL), (*WillDisappear)(id,SEL,BOOL), (*DidLayout)(id,SEL), (*Dealloc)(id,SEL);
static void (*SetSource)(id,SEL,id), (*SetThreaded)(id,SEL,BOOL), (*SearchPresent)(id,SEL,id);
static void (*SetBoxes)(id,SEL,id), (*SetBoxesForce)(id,SEL,id,BOOL), (*PrivateBoxes)(id,SEL,id);
static void (*Reload)(id,SEL), (*Update)(id,SEL);
static void AttachButton(MRState *s) {
    if (!s->button) s->button=[[UIBarButtonItem alloc] initWithTitle:@"规则" style:UIBarButtonItemStylePlain target:s action:@selector(showRules)];
    NSArray *items=s->owner.navigationItem.rightBarButtonItems ?: @[];
    if (![items containsObject:s->button]) s->owner.navigationItem.rightBarButtonItems=[items arrayByAddingObject:s->button];
}
static void DidAppearHook(id vc,SEL cmd,BOOL animated) {
    DidAppear(vc,cmd,animated); MRState *s=State(vc,YES); s->visible=YES; AttachButton(s); [s refresh];
}
static void DisappearHook(id vc,SEL cmd,BOOL animated) {
    MRState *s=State(vc,NO); if(s) { s->visible=NO; [s restore]; }
    WillDisappear(vc,cmd,animated);
}
static void LayoutHook(id vc,SEL cmd) {
    DidLayout(vc,cmd); MRState *s=State(vc,NO);
    if(s && s->visible) {AttachButton(s); [s refresh];}
}
static void DeallocHook(id vc,SEL cmd) {
    MRState *s=State(vc,NO);
    // Do not send filter changes to a controller being torn down.
    if(s) {s->owner=nil; [s->calls removeAllObjects]; [s restore];}
    objc_setAssociatedObject(vc,&StateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Dealloc(vc,cmd);
}
static void BeginTransition(MRState *s) {if(s) { [s restore]; s->depth++; }}
static void EndTransition(MRState *s) {if(s) { s->depth--; [s refresh]; }}
static void SourceHook(id vc,SEL cmd,id ds) {
    MRState *s=State(vc,NO), *previous=objc_getAssociatedObject(ds,&SourceKey);
    if(previous && previous!=s) [previous restore];
    BeginTransition(s); @try {SetSource(vc,cmd,ds);} @finally {EndTransition(s);}
}
static void ThreadHook(id vc,SEL cmd,BOOL value) {MRState *s=State(vc,NO); BeginTransition(s); @try {SetThreaded(vc,cmd,value);} @finally {EndTransition(s);}}
static void SearchHook(id vc,SEL cmd,id value) {MRState *s=State(vc,NO); BeginTransition(s); @try {SearchPresent(vc,cmd,value);} @finally {if(s) s->depth--;}}
static void BoxesHook(id vc,SEL cmd,id value) {MRState *s=State(vc,NO); BeginTransition(s); @try {SetBoxes(vc,cmd,value);} @finally {EndTransition(s);}}
static void BoxesForceHook(id vc,SEL cmd,id value,BOOL force) {MRState *s=State(vc,NO); BeginTransition(s); @try {SetBoxesForce(vc,cmd,value,force);} @finally {EndTransition(s);}}
static void PrivateBoxesHook(id vc,SEL cmd,id value) {MRState *s=State(vc,NO); BeginTransition(s); @try {PrivateBoxes(vc,cmd,value);} @finally {EndTransition(s);}}
static void ReloadHook(id vc,SEL cmd) {MRState *s=State(vc,NO); BeginTransition(s); @try {Reload(vc,cmd);} @finally {EndTransition(s);}}
static void UpdateHook(id vc,SEL cmd) {Update(vc,cmd); [State(vc,NO) refresh];}
static BOOL Check(Class c,NSString *name,const char *enc) {
    Method m=class_getInstanceMethod(c,NSSelectorFromString(name));
    return m && strcmp(method_getTypeEncoding(m),enc)==0;
}
static void Hook(Class c,NSString *name,IMP replacement,IMP *original) {
    SEL sel=NSSelectorFromString(name); Method method=class_getInstanceMethod(c,sel);
    *original=method_getImplementation(method);
    // Add on the target class when inherited; never replace an NSObject/UIViewController implementation.
    if (!class_addMethod(c,sel,replacement,method_getTypeEncoding(method))) method_setImplementation(method,replacement);
}
__attribute__((constructor)) static void Install(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobilemail"]) return;
        char build[64]={0}; size_t size=sizeof(build);
        if (sysctlbyname("kern.osversion",build,&size,NULL,0)!=0 || strcmp(build,"20G75")!=0) return;
        Class vc=NSClassFromString(@"MessageListViewController"), ds=NSClassFromString(@"MessageListDataSource");
        if (!vc || !ds) return;
        NSArray *checks=@[
            @[@"viewDidAppear:",@"v20@0:8B16"],@[@"viewWillDisappear:",@"v20@0:8B16"],
            @[@"viewDidLayoutSubviews",@"v16@0:8"],@[@"dealloc",@"v16@0:8"],
            @[@"setDataSource:",@"v24@0:8@16"],@[@"setThreaded:",@"v20@0:8B16"],
            @[@"willPresentSearchController:",@"v24@0:8@16"],@[@"setMailboxes:",@"v24@0:8@16"],
            @[@"setMailboxes:forceReload:",@"v28@0:8@16B24"],@[@"_setMailboxes:",@"v24@0:8@16"],
            @[@"_reloadDataSource",@"v16@0:8"],@[@"_updateFilters",@"v16@0:8"]];
        for(NSArray *c in checks) if(!Check(vc,c[0],[c[1] UTF8String])) return;
        if (!Check(ds,@"applyFilterPredicate:ignoreMessagesPredicate:","v32@0:8@16@24") || !Check(ds,@"applyFilterPredicate:ignoreMessagesPredicate:section:","v40@0:8@16@24@32") || !Check(NSClassFromString(@"EMMessageList"),@"filteredMessageListWithPredicate:ignoredMessagesPredicate:","@32@0:8@16@24")) return;
#define H(C,N,F,O) Hook(C,@N,(IMP)F,(IMP *)&O)
        H(ds,"applyFilterPredicate:ignoreMessagesPredicate:",ApplyHook,Apply);
        H(ds,"applyFilterPredicate:ignoreMessagesPredicate:section:",SectionHook,ApplySection);
        H(vc,"viewDidAppear:",DidAppearHook,DidAppear);
        H(vc,"viewWillDisappear:",DisappearHook,WillDisappear);
        H(vc,"viewDidLayoutSubviews",LayoutHook,DidLayout);
        H(vc,"dealloc",DeallocHook,Dealloc);
        H(vc,"setDataSource:",SourceHook,SetSource);
        H(vc,"setThreaded:",ThreadHook,SetThreaded);
        H(vc,"willPresentSearchController:",SearchHook,SearchPresent);
        H(vc,"setMailboxes:",BoxesHook,SetBoxes);
        H(vc,"setMailboxes:forceReload:",BoxesForceHook,SetBoxesForce);
        H(vc,"_setMailboxes:",PrivateBoxesHook,PrivateBoxes);
        H(vc,"_reloadDataSource",ReloadHook,Reload);
        H(vc,"_updateFilters",UpdateHook,Update);
#undef H
        HooksReady=YES;
    }
}
