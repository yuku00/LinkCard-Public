#import "WU.h"
#import "MessageLogic.h"
#import "WUStats.h"
#import "GroupLogic.h"
#import "Repository.h"
#import "EmoticonLogic.h"
#import "VoiceSendLogic.h"
#import <Photos/Photos.h>
static void ForwardSelectedVoice(UIViewController *owner);
static void SaveSelectedEmoticon(UIViewController *owner);
static void OpenRepository(UIViewController *owner);
static BOOL StatsReady(id mgr) {
    Method method=class_getInstanceMethod(object_getClass(mgr),NSSelectorFromString(@"GetMsgByCreateTime:FromID:FromCreateTime:Limit:LeftCount:"));
    for(NSString *i in @[@"I",@"i"]) for(NSString *t in @[@"I",@"i"]) for(NSString *l in @[@"I",@"i"]) for(NSString *p in @[@"^I",@"^i"])
        if(WUMatches(method,"@",@[@"@",i,t,l,p])) return YES;
    return NO;
}
static void OpenStats(UIViewController *owner);
#include <string.h>
#include <stdatomic.h>
// Only evidence-backed selectors below; every private call checks runtime encoding first.
static BOOL Has(id o, NSString *s, const char *r, NSArray *a) { return o && WUMatches(class_getInstanceMethod(object_getClass(o),NSSelectorFromString(s)),r,a); }
static id Obj(id o, NSString *s) { if(!Has(o,s,"@",@[])) return nil; return ((id(*)(id,SEL))objc_msgSend)(o,NSSelectorFromString(s)); }
static NSString *Str(id o, NSString *s) { id x=Obj(o,s); return [x isKindOfClass:NSString.class]?[x copy]:nil; }
static uint64_t Num(id o, NSString *s) {
    SEL sel=NSSelectorFromString(s); Method m=o?class_getInstanceMethod(object_getClass(o),sel):NULL;
    if(!m || method_getNumberOfArguments(m)!=2) return 0;
    char *r=method_copyReturnType(m); BOOL ok=strlen(r)==1 && strchr("IQiq",r[0]); free(r); if(!ok) return 0;
    NSMethodSignature *sig=[o methodSignatureForSelector:sel]; NSInvocation *v=[NSInvocation invocationWithMethodSignature:sig]; v.target=o; v.selector=sel; [v invoke]; uint64_t n=0; [v getReturnValue:&n]; return n;
}
static id Service(NSString *name) {
    id center=Obj(NSClassFromString(@"MMServiceCenter"),@"defaultCenter"); Class c=NSClassFromString(name);
    if(!c || !Has(center,@"getService:","@",@[@"#"])) {
        if(!c || !Has(center,@"getService:","@",@[@"@"])) return nil;
    }
    return ((id(*)(id,SEL,Class))objc_msgSend)(center,NSSelectorFromString(@"getService:"),c);
}
static _Atomic(NSUInteger) generation=1;
static NSString *lastAccount;
static NSString *Account(void) {
    NSString *a=Str(Obj(Service(@"CContactMgr"),@"getSelfContact"),@"m_nsUsrName");
    @synchronized(NSProcessInfo.processInfo) { if(![a isEqual:lastAccount]) { generation++; lastAccount=[a copy]; } }
    return a;
}
NSString *WUCurrentAccount(void) { @try { return Account(); } @catch(NSException *e) { return nil; } }
NSUInteger WUContextGeneration(void) { (void)WUCurrentAccount(); return generation; }
NSUInteger WUContextGenerationSnapshot(void) { return atomic_load(&generation); }
static id Contact(id v) { return Obj(v,@"GetContact") ?: Obj(v,@"getChatContact"); }
static NSString *Session(id v) { return Str(Contact(v),@"m_nsUsrName"); }
NSString *WUChatSession(UIViewController *owner) { @try { return Session(owner); } @catch(NSException *e) { return nil; } }
static id Wrap(id cell) { return Obj(Obj(cell,@"viewModel"),@"messageWrap"); }
static UIViewController *Owner(UIView *v) { for(UIResponder *r=v;r;r=r.nextResponder) if([r isKindOfClass:UIViewController.class]) return (id)r; return nil; }
static UIViewController *Chat(UIView *v) { UIViewController *c=Owner(v); Class k=NSClassFromString(@"BaseMsgContentViewController"); while(c && ![c isKindOfClass:k]) c=c.parentViewController; return c; }
static void Notice(UIViewController *v, NSString *text) {
    if(!v.viewIfLoaded.window || v.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"微信整合" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [v presentViewController:a animated:YES completion:nil];
}
static NSHashTable *pendingAlerts;
static void CancelPending(void) {
    generation++;
    WUCancelMoments();
    WUCancelVoice();
    for(UIAlertController *a in pendingAlerts.allObjects) [a dismissViewControllerAnimated:NO completion:nil];
    [pendingAlerts removeAllObjects];
}
static void Confirm(UIViewController *v, NSString *key, NSString *title, BOOL(^valid)(void), void(^commit)(void)) {
    if(!NSThread.isMainThread || !v.viewIfLoaded.window || v.presentedViewController || !WUEnabled(key)) return;
    NSString *account=Account(), *session=Session(v); if(!account.length || !session.length) { Notice(v,@"账号或当前会话无法核验，本次操作取消。"); return; }
    NSUInteger g=generation; __weak UIViewController *weak=v; __block BOOL consumed=NO;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:@"仅对当前会话执行一次。取消、离开页面、切号或关闭开关均不执行。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        UIViewController *owner=weak; if(consumed) return; consumed=YES;
        [owner dismissViewControllerAnimated:YES completion:^{
            @try { NSString *now=Account(); if(!owner.viewIfLoaded.window || !WUEnabled(key) || ![account isEqual:now] || g!=generation || ![session isEqual:Session(owner)] || !valid()) return; commit(); }
            @catch(NSException *e) { Notice(owner,@"操作结果未知，未自动重试。请在宿主核对。"); }
        }];
    }]];
    [pendingAlerts addObject:a]; [v presentViewController:a animated:YES completion:nil];
}
static NSDictionary *Info(id w) { return @{@"from":Str(w,@"m_nsFromUsr")?:@"",@"real":Str(w,@"m_nsRealChatUsr")?:@"",@"to":Str(w,@"m_nsToUsr")?:@"",@"id":@(Num(w,@"m_n64MesSvrID")),@"local":@(Num(w,@"m_uiMesLocalID")),@"time":@(Num(w,@"m_uiCreateTime")),@"type":@(Num(w,@"m_uiMessageType"))}; }
static BOOL InSession(NSDictionary *m, NSString *a, NSString *s) {
    NSString *f=m[@"from"], *t=m[@"to"];
    return [s hasSuffix:@"@chatroom"]?([f isEqual:s] || ([f isEqual:a] && [t isEqual:s])):(([f isEqual:a] && [t isEqual:s]) || ([f isEqual:s] && [t isEqual:a]));
}
static BOOL LookupReady(id mgr) { return Has(mgr,@"GetMsg:n64SvrID:","@",@[@"@",@"q"]) || Has(mgr,@"GetMsg:n64SvrID:","@",@[@"@",@"Q"]); }
static id Lookup(id mgr, NSString *s, uint64_t n) { return LookupReady(mgr)?((id(*)(id,SEL,id,uint64_t))objc_msgSend)(mgr,NSSelectorFromString(@"GetMsg:n64SvrID:"),s,n):nil; }
static IMP revokeOriginal;
static void Revoke(id self, SEL cmd, id notice) {
    BOOL protect=NO;
    @try {
        if(WUEnabled(@"antiRevoke")) {
            NSDictionary *fields=WURevokeFields(Str(notice,@"m_nsContent")); NSString *a=Account(), *s=fields[@"session"];
            id old=fields && a.length?Lookup(Service(@"CMessageMgr"),s,[fields[@"id"] unsignedLongLongValue]):nil;
            NSDictionary *m=Info(old);
            protect=old && [m[@"id"] isEqual:fields[@"id"]] && [a isEqual:Account()] && InSession(m,a,s) && !WUOwnMessage(a,s,m[@"from"],m[@"real"]) && [m[@"from"] length] && (![s hasSuffix:@"@chatroom"] || [m[@"real"] length]);
        }
    } @catch(NSException *e) { protect=NO; }
    // No local insertion; duplicate notices are idempotent and cannot cause a second write.
    if(!protect) ((void(*)(id,SEL,id))revokeOriginal)(self,cmd,notice);
}
static IMP callbackOriginal;
static char callbackPending;
static void Callback(UIView *cell, SEL cmd) {
    if(!WUEnabled(@"callbackConfirm")) { ((void(*)(id,SEL))callbackOriginal)(cell,cmd); return; }
    @try {
        UIViewController *v=Chat(cell); id wrap=Wrap(cell); NSDictionary *frozen=Info(wrap); NSString *callContent=Str(wrap,@"m_nsContent")?:@""; __weak UIView *weak=cell;
        if(!v || !wrap || ![frozen[@"id"] unsignedLongLongValue]) { Notice(v,@"回拨消息身份不可核验，已取消。"); return; }
        if([objc_getAssociatedObject(cell,&callbackPending) boolValue]) return;
        Confirm(v,@"callbackConfirm",@"确认回拨这条通话记录？",^BOOL{ return weak.window && Wrap(weak)==wrap && [Info(wrap) isEqual:frozen] && [callContent isEqual:Str(wrap,@"m_nsContent")?:@""]; },^{
            UIView *target=weak; objc_setAssociatedObject(target,&callbackPending,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try { ((void(*)(id,SEL))callbackOriginal)(target,cmd); } @finally { objc_setAssociatedObject(target,&callbackPending,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        });
    } @catch(NSException *e) { Notice(Chat(cell),@"回拨上下文失效，已取消。"); }
}

static NSString *RevokeSelector(id mgr) {
    for(NSString *s in @[@"RevokeMsg:MsgWrap:Counter:revokeTicket:viewController:",@"RevokeMsg:MsgWrap:Counter:"]) {
        for(NSString *counter in @[@"I",@"i",@"Q",@"q"]) {
            NSArray *args=[s hasSuffix:@"viewController:"]?@[@"@",@"@",counter,@"@",@"@"]:@[@"@",@"@",counter];
            if(Has(mgr,s,"v",args) || Has(mgr,s,"@",args)) return s;
        }
    }
    return nil;
}
static void RequestRevoke(id mgr, NSString *s, NSString *session, id wrap, UIViewController *owner) {
    // Width comes from the checked encoding, not an assumed NSUInteger ABI.
    NSInvocation *v=[NSInvocation invocationWithMethodSignature:[mgr methodSignatureForSelector:NSSelectorFromString(s)]];
    v.target=mgr; v.selector=NSSelectorFromString(s); __unsafe_unretained id chat=session, msg=wrap, ticket=nil, vc=owner;
    uint64_t one=1; [v setArgument:&chat atIndex:2]; [v setArgument:&msg atIndex:3]; [v setArgument:&one atIndex:4];
    if(v.methodSignature.numberOfArguments==7) { [v setArgument:&ticket atIndex:5]; [v setArgument:&vc atIndex:6]; }
    [v invoke];
}
@interface WUChatActions : NSObject
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,strong) UIBarButtonItem *search;
@property(nonatomic,strong) UIBarButtonItem *recall;
@property(nonatomic,strong) UIBarButtonItem *stats;
@property(nonatomic,strong) UIBarButtonItem *tools;
@property(nonatomic,strong) NSMutableSet *requested;
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSString *session;
- (void)refresh;
@end
static NSHashTable *chatActions;
@implementation WUChatActions
- (instancetype)init { if((self=[super init])) { _requested=[NSMutableSet set]; } return self; }
- (void)refresh {
    UIViewController *v=self.owner; if(!v) return;
    NSMutableArray *items=[v.navigationItem.rightBarButtonItems mutableCopy]?:[NSMutableArray array];
    if(self.tools) [items removeObject:self.tools];
    if(self.search) [items removeObject:self.search]; if(self.recall) [items removeObject:self.recall]; if(self.stats) [items removeObject:self.stats];
    // Statistics is available only through the account-selected tools menu.
    if(WUEnabled(@"chatSearch") && Has(v,@"onSearchItem","v",@[])) { if(!self.search) self.search=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"] style:UIBarButtonItemStylePlain target:self action:@selector(openSearch)]; self.search.accessibilityLabel=@"搜索当前会话聊天记录"; [items addObject:self.search]; }
    if(WUEnabled(@"multiRevoke") && Has(v,@"getSelectedMsgs","@",@[]) && RevokeSelector(Service(@"CMessageMgr"))) { if(!self.recall) self.recall=[[UIBarButtonItem alloc] initWithTitle:@"撤回所选" style:UIBarButtonItemStylePlain target:self action:@selector(recallSelected)]; [items addObject:self.recall]; }
    NSString *account=Account(), *session=Session(v); NSUInteger gen=generation;
    NSArray *selected=WUToolbarActions(WUAccountOptions(account)[@"toolbar"]);
    NSMutableArray *menu=[NSMutableArray array]; __weak WUChatActions *weak=self;
    if([WUValue(@"enabled") boolValue] && account.length && session.length) for(NSString *key in selected) {
        if([key isEqual:@"search"] && !Has(v,@"onSearchItem","v",@[])) continue;
        if([key isEqual:@"stats"] && !StatsReady(Service(@"CMessageMgr"))) continue;
        if([key isEqual:@"moments"] && (!WUEnabled(@"convenientMoments") || !WUMomentsAvailable())) continue;
        NSString *title=@{@"search":@"当前会话搜索",@"stats":@"当前会话统计",@"settings":@"整合设置",@"repository":@"消息仓库",@"voiceForward":@"所选语音转发",@"emojiSave":@"所选表情保存图库",@"moments":@"半屏朋友圈"}[key];
        [menu addObject:[UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction *action){
            WUChatActions *target=weak; UIViewController *owner=target.owner;
            @try {
                if(!owner.viewIfLoaded.window || owner.presentedViewController || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || ![WUValue(@"enabled") boolValue] || ![account isEqual:Account()] || gen!=generation || ![session isEqual:Session(owner)] || ![WUToolbarActions(WUAccountOptions(account)[@"toolbar"]) containsObject:key]) return;
                if([key isEqual:@"settings"]) WUShowSettings(owner);
                else if([key isEqual:@"voiceForward"]) ForwardSelectedVoice(owner);
                else if([key isEqual:@"emojiSave"]) SaveSelectedEmoticon(owner);
                else if([key isEqual:@"repository"]) OpenRepository(owner);
                else if([key isEqual:@"stats"]) OpenStats(owner);
                else if([key isEqual:@"moments"]) { if(!WUOpenMoments(owner)) Notice(owner,@"半屏朋友圈当前不可用，未打开全屏替代页面。"); }
                else if([key isEqual:@"search"] && Has(owner,@"onSearchItem","v",@[])) ((void(*)(id,SEL))objc_msgSend)(owner,NSSelectorFromString(@"onSearchItem"));
            } @catch(NSException *e) { Notice(owner,@"该工具当前不可用，未自动重试。"); }
        }]];
    }
    if(menu.count) {
        if(!self.tools) self.tools=[[UIBarButtonItem alloc] initWithTitle:@"工具" style:UIBarButtonItemStylePlain target:nil action:NULL];
        self.tools.menu=[UIMenu menuWithTitle:@"手动工具" children:menu]; [items addObject:self.tools];
        if([selected containsObject:@"stats"] && self.stats) [items removeObject:self.stats];
        if([selected containsObject:@"search"] && self.search) [items removeObject:self.search];
    } else self.tools.menu=nil;
    v.navigationItem.rightBarButtonItems=items;
    WURefreshMomentsInput(v);
}
- (void)openStats { if([WUValue(@"enabled") boolValue]) OpenStats(self.owner); }
- (void)openSearch {
    UIViewController *v=self.owner;
    @try { if(WUEnabled(@"chatSearch") && v.viewIfLoaded.window && !v.presentedViewController && Session(v).length && Has(v,@"onSearchItem","v",@[])) ((void(*)(id,SEL))objc_msgSend)(v,NSSelectorFromString(@"onSearchItem")); }
    @catch(NSException *e) { Notice(v,@"宿主聊天记录搜索不可用；未扫描数据库或采集搜索词。"); }
}
- (void)recallSelected {
    UIViewController *v=self.owner; if(!WUEnabled(@"multiRevoke")) return;
    @try {
        NSString *a=Account(), *s=Session(v); id selection=Obj(v,@"getSelectedMsgs");
        if(!a.length || !s.length || ![selection isKindOfClass:NSArray.class] || ![selection count] || [selection count]>100) { Notice(v,@"请在宿主多选模式选择1–100条消息；账号和会话必须可核验。"); return; }
        if(![self.account isEqual:a] || ![self.session isEqual:s]) { [self.requested removeAllObjects]; self.account=a; self.session=s; }
        NSArray *selected=[selection copy]; NSMutableArray *eligible=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set]; NSUInteger skipped=0;
        for(id wrap in selected) {
            NSDictionary *m=Info(wrap); NSNumber *mid=m[@"id"];
            if(!InSession(m,a,s) || !WURevokeEligible(a,s,m,NSDate.date.timeIntervalSince1970) || [seen containsObject:mid] || [self.requested containsObject:mid]) { skipped++; continue; }
            [seen addObject:mid]; [eligible addObject:@{@"wrap":wrap,@"info":m}];
        }
        if(!eligible.count) { Notice(v,@"没有可请求撤回的自身消息。他人、超时、未知身份和已请求项均跳过，绝不删除。"); return; }
        __weak WUChatActions *weak=self;
        Confirm(v,@"multiRevoke",[NSString stringWithFormat:@"撤回%lu条自身消息？（跳过%lu条）",(unsigned long)eligible.count,(unsigned long)skipped],^BOOL{ return weak.owner==v; },^{
            NSUInteger requested=0, unknown=0, omitted=skipped; id mgr=Service(@"CMessageMgr"); NSString *selector=RevokeSelector(mgr);
            for(NSDictionary *entry in eligible) {
                id wrap=entry[@"wrap"]; NSDictionary *m=Info(wrap); NSNumber *mid=m[@"id"];
                if(!selector || !WUEnabled(@"multiRevoke") || ![a isEqual:Account()] || ![s isEqual:Session(v)] || ![m isEqual:entry[@"info"]] || !WURevokeEligible(a,s,m,NSDate.date.timeIntervalSince1970) || [weak.requested containsObject:mid]) { omitted++; continue; }
                // Claim before crossing the host side-effect boundary. Never retry on exception.
                [weak.requested addObject:mid];
                @try { RequestRevoke(mgr,selector,s,wrap,v); requested++; }
                @catch(NSException *e) { unknown++; break; }
            }
            dispatch_async(dispatch_get_main_queue(),^{ Notice(v,[NSString stringWithFormat:@"已请求%lu条；跳过%lu条；结果未知%lu条。无服务器回执，不代表撤回成功。未删除任何消息。",(unsigned long)requested,(unsigned long)omitted,(unsigned long)unknown]); });
        });
    } @catch(NSException *e) { Notice(v,@"无法读取选中消息；未提交撤回。"); }
}
@end
static IMP chatAppearOriginal, chatDisappearOriginal;
static char chatKey;
static void ChatAppeared(UIViewController *v,SEL s,BOOL animated) {
    ((void(*)(id,SEL,BOOL))chatAppearOriginal)(v,s,animated);
    @try { WUChatActions *a=objc_getAssociatedObject(v,&chatKey); if(!a) { a=[WUChatActions new]; a.owner=v; objc_setAssociatedObject(v,&chatKey,a,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [chatActions addObject:a]; } [a refresh]; } @catch(NSException *e) {}
}
static void ChatDisappeared(UIViewController *v,SEL s,BOOL animated) {
    UIViewController *presented=v.presentedViewController;
    BOOL ownStats=[presented isKindOfClass:UINavigationController.class] && [[(UINavigationController *)presented topViewController] isKindOfClass:NSClassFromString(@"WUStatsController")];
    if(!ownStats && !WUIsMomentsSheet(presented) && !WUIsRepositoryController(presented)) CancelPending();
    ((void(*)(id,SEL,BOOL))chatDisappearOriginal)(v,s,animated);
}

@protocol WUMessageConstruct <NSObject>
- (instancetype)initWithMsgType:(long long)type nsFromUsr:(NSString *)from;
@end
static BOOL NumberSetter(id o, NSString *s) {
    for(NSString *t in @[@"I",@"i",@"Q",@"q"]) if(Has(o,s,"v",@[t])) return YES;
    return NO;
}
static void SetNumber(id o, NSString *s, uint64_t n) {
    NSInvocation *v=[NSInvocation invocationWithMethodSignature:[o methodSignatureForSelector:NSSelectorFromString(s)]];
    v.target=o; v.selector=NSSelectorFromString(s); [v setArgument:&n atIndex:2]; [v invoke];
}
static BOOL RepeatReady(id wrap) {
    Class c=NSClassFromString(@"CMessageWrap");
    if(!WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"initWithMsgType:nsFromUsr:")),"@",@[@"q",@"@"]) || !Has(wrap,@"copyToMsg:","v",@[@"@"]) || !Has(Service(@"CMessageMgr"),@"AddEmoticonMsg:MsgWrap:","v",@[@"@",@"@"])) return NO;
    for(NSString *s in @[@"setM_nsFromUsr:",@"setM_nsToUsr:",@"setM_nsRealChatUsr:"]) if(!WUMatches(class_getInstanceMethod(c,NSSelectorFromString(s)),"v",@[@"@"])) return NO;
    for(NSString *s in @[@"setM_uiCreateTime:",@"setM_uiMesLocalID:",@"setM_n64MesSvrID:"]) if(!NumberSetter(wrap,s)) return NO;
    return YES;
}
@interface WUCellActions : NSObject
@property(nonatomic,weak) UIView *cell;
@property(nonatomic,strong) UIButton *repeat;
@property(nonatomic,weak) UIView *head;
@property(nonatomic,weak) UIView *name;
@property(nonatomic) BOOL headHidden;
@property(nonatomic) BOOL nameHidden;
@property(nonatomic) BOOL changed;
@property(nonatomic) BOOL submitting;
- (void)restore;
- (void)update;
@end
static NSHashTable *cellActions;
static id KnownValue(id o, NSString *key) { @try { return [o valueForKey:key]; } @catch(NSException *e) { return nil; } }
static NSDictionary *GroupInfo(id model, NSString *session, NSString *account) {
    id wrap=Obj(model,@"messageWrap"); if(!wrap || [model isKindOfClass:NSClassFromString(@"ChatTimeViewModel")]) return @{@"separator":@YES};
    NSDictionary *m=Info(wrap); NSString *sender=[session hasSuffix:@"@chatroom"]?([m[@"real"] length]?m[@"real"]:m[@"from"]):m[@"from"];
    return @{@"session":session?:@"",@"sender":sender?:@"",@"time":m[@"time"],@"separator":@(!InSession(m,account,session) || [m[@"type"] unsignedIntValue]>=10000)};
}
@implementation WUCellActions
- (void)restore {
    if(self.changed) { self.head.hidden=self.headHidden; self.name.hidden=self.nameHidden; self.changed=NO; }
}
- (void)update {
    UIView *cell=self.cell; [self restore]; UIViewController *v=Chat(cell); id wrap=Wrap(cell);
    BOOL show=cell.window && v && WUEnabled(@"repeatEmoticon") && Num(wrap,@"m_uiMessageType")==47 && RepeatReady(wrap);
    if(!show) { [self.repeat removeFromSuperview]; self.repeat=nil; }
    else {
        if(!self.repeat) { self.repeat=[UIButton buttonWithType:UIButtonTypeSystem]; [self.repeat setImage:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"] forState:UIControlStateNormal]; self.repeat.accessibilityLabel=@"常规复读此表情（需要确认）"; self.repeat.layer.cornerRadius=6; self.repeat.backgroundColor=UIColor.secondarySystemBackgroundColor; [self.repeat addTarget:self action:@selector(repeatMessage) forControlEvents:UIControlEventTouchUpInside]; [cell addSubview:self.repeat]; }
        self.repeat.alpha=1; self.repeat.frame=CGRectMake(MAX(0,CGRectGetWidth(cell.bounds)-31),MAX(0,(CGRectGetHeight(cell.bounds)-25)/2),25,25);
    }
    NSString *session=Session(v); BOOL group=[session hasSuffix:@"@chatroom"];
    if(!cell.window || !WUEnabled(group?@"mergeGroup":@"mergePrivate") || !session.length) return;
    id models=KnownValue(v,@"m_arrMessageNodeData"), model=Obj(cell,@"viewModel");
    if(![models isKindOfClass:NSArray.class] || [models count]>10000) return;
    NSUInteger index=[models indexOfObjectIdenticalTo:model]; if(index==NSNotFound) return;
    BOOL bottom=WUEnabled(@"mergeBottom"); if((bottom && index+1>=[models count]) || (!bottom && index==0)) return;
    NSString *account=Account(); if(!account.length) return;
    id adjacent=models[bottom?index+1:index-1]; NSDictionary *a=GroupInfo(bottom?model:adjacent,session,account), *b=GroupInfo(bottom?adjacent:model,session,account);
    if(!WUGroupAdjacent(a,b)) return;
    id head=KnownValue(cell,@"m_headImageView"), name=KnownValue(cell,@"m_chatRoomNameLabel");
    if(![head isKindOfClass:UIView.class]) return;
    self.head=head; self.name=[name isKindOfClass:UIView.class]?name:nil; self.headHidden=self.head.hidden; self.nameHidden=self.name.hidden; self.changed=YES; self.head.hidden=YES; self.name.hidden=YES;
}
- (void)repeatMessage {
    if(self.submitting || !WUEnabled(@"repeatEmoticon")) return;
    UIView *cell=self.cell; UIViewController *v=Chat(cell);
    @try {
        id source=Wrap(cell); NSDictionary *frozen=Info(source); NSString *account=Account(), *session=Session(v);
        if(!account.length || !session.length || !InSession(frozen,account,session) || Num(source,@"m_uiMessageType")!=47 || !RepeatReady(source)) { Notice(v,@"当前表情接口或会话不可用，未发送。"); return; }
        __weak WUCellActions *weak=self;
        Confirm(v,@"repeatEmoticon",@"向当前会话复读这个表情？",^BOOL{ return weak.cell.window && Wrap(weak.cell)==source && [Info(source) isEqual:frozen] && !weak.submitting; },^{
            WUCellActions *state=weak; if(!state) return; state.submitting=YES;
            @try {
                // Fresh object, copy only via the host protocol, then clear original identity.
                id<WUMessageConstruct> allocated=[NSClassFromString(@"CMessageWrap") alloc];
                id message=[allocated initWithMsgType:47 nsFromUsr:account];
                if(!message) { Notice(v,@"无法构造新表情消息，未提交。"); return; }
                ((void(*)(id,SEL,id))objc_msgSend)(source,NSSelectorFromString(@"copyToMsg:"),message);
                ((void(*)(id,SEL,id))objc_msgSend)(message,NSSelectorFromString(@"setM_nsFromUsr:"),account);
                ((void(*)(id,SEL,id))objc_msgSend)(message,NSSelectorFromString(@"setM_nsToUsr:"),session);
                ((void(*)(id,SEL,id))objc_msgSend)(message,NSSelectorFromString(@"setM_nsRealChatUsr:"),nil);
                SetNumber(message,@"setM_uiCreateTime:",(uint64_t)NSDate.date.timeIntervalSince1970); SetNumber(message,@"setM_uiMesLocalID:",0); SetNumber(message,@"setM_n64MesSvrID:",0);
                if(![account isEqual:Account()] || !WUEnabled(@"repeatEmoticon") || ![session isEqual:Session(v)]) return;
                // The sole submission point. No AddMsg/forward fallback, no automatic retry.
                ((void(*)(id,SEL,id,id))objc_msgSend)(Service(@"CMessageMgr"),NSSelectorFromString(@"AddEmoticonMsg:MsgWrap:"),session,message);
                dispatch_async(dispatch_get_main_queue(),^{ Notice(v,@"表情发送已请求，送达状态以宿主为准。"); });
            } @catch(NSException *e) { dispatch_async(dispatch_get_main_queue(),^{ Notice(v,@"表情操作结果未知，未重试；请核对聊天记录。"); }); }
            @finally { state.submitting=NO; }
        });
    } @catch(NSException *e) { Notice(v,@"无法读取表情上下文，未发送。"); }
}
@end
static IMP cellLayoutOriginal, cellReuseOriginal;
static char cellKey;
static void CellLayout(UIView *cell, SEL s) {
    WUCellActions *a=objc_getAssociatedObject(cell,&cellKey); [a restore]; ((void(*)(id,SEL))cellLayoutOriginal)(cell,s);
    @try { if(!a) { a=[WUCellActions new]; a.cell=cell; objc_setAssociatedObject(cell,&cellKey,a,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [cellActions addObject:a]; } [a update]; } @catch(NSException *e) { [a restore]; [a.repeat removeFromSuperview]; a.repeat=nil; }
}
static void CellReuse(UIView *cell, SEL s) {
    WUCellActions *a=objc_getAssociatedObject(cell,&cellKey); [a restore]; [a.repeat removeFromSuperview]; a.repeat=nil;
    ((void(*)(id,SEL))cellReuseOriginal)(cell,s);
}

static UIViewController *ForegroundOwner(void) {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(scene.activationState!=UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for(UIWindow *window in [(UIWindowScene *)scene windows]) if(window.isKeyWindow) {
            UIViewController *v=window.rootViewController;
            while(v) { if(v.presentedViewController) { v=v.presentedViewController; continue; } if([v isKindOfClass:UINavigationController.class]) { v=[(UINavigationController *)v topViewController]; continue; } if([v isKindOfClass:UITabBarController.class]) { v=[(UITabBarController *)v selectedViewController]; continue; } break; }
            return [v isKindOfClass:UIAlertController.class]?nil:v;
        }
    }
    return nil;
}
static IMP arrivalOriginal;
static NSMutableOrderedSet *redSeen;
static NSString *redAccount;
static void Arrival(id self, SEL cmd, id sessionArg, id wrap) {
    ((void(*)(id,SEL,id,id))arrivalOriginal)(self,cmd,sessionArg,wrap);
    @try {
        if(!WUEnabled(@"redReminder") || Num(wrap,@"m_uiMessageType")!=49 || ![sessionArg isKindOfClass:NSString.class]) return;
        NSString *url=Str(Obj(wrap,@"m_oWCPayInfoItem"),@"m_c2cNativeUrl");
        if(![url hasPrefix:@"wxpay://c2cbizmessagehandler/hongbao/receivehongbao?"]) return;
        NSDictionary *m=Info(wrap); NSString *session=[sessionArg copy], *account=Account(); NSUInteger g=generation;
        double age=NSDate.date.timeIntervalSince1970-[m[@"time"] doubleValue];
        if(!account.length || ![m[@"id"] unsignedLongLongValue] || age<0 || age>60 || !InSession(m,account,session) || WUOwnMessage(account,session,m[@"from"],m[@"real"])) return;
        dispatch_async(dispatch_get_main_queue(),^{
            @try {
                if(!WUEnabled(@"redReminder") || ![account isEqual:Account()] || g!=generation || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
                if(![redAccount isEqual:account]) { [redSeen removeAllObjects]; redAccount=account; }
                NSString *key=[NSString stringWithFormat:@"%@:%@",session,m[@"id"]]; if([redSeen containsObject:key]) return;
                UIViewController *owner=nil;
                for(WUChatActions *a in chatActions.allObjects) if(a.owner.viewIfLoaded.window && !a.owner.presentedViewController) { owner=a.owner; break; }
                if(!owner) owner=ForegroundOwner();
                if(!owner || owner.presentedViewController) return;
                NSString *chatName=@"一个会话"; id contacts=Service(@"CContactMgr");
                if(Has(contacts,@"getContactByName:","@",@[@"@"])) { id contact=((id(*)(id,SEL,id))objc_msgSend)(contacts,NSSelectorFromString(@"getContactByName:"),session); NSString *name=Str(contact,@"m_nsRemark"); if(!name.length) name=Str(contact,@"m_nsNickName"); if(name.length) chatName=name; }
                [redSeen addObject:key]; if(redSeen.count>512) [redSeen removeObjectAtIndex:0];
                UIAlertController *alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"「%@」红包消息提醒",chatName] message:@"收到新的红包消息。仅提醒，不自动领取、不查询金额或人数。" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
                // Only offer positioning when the actual message cell is already available.
                __weak UIView *target=nil;
                for(WUCellActions *a in cellActions.allObjects) if(a.cell.window && [Session(Chat(a.cell)) isEqual:session] && Num(Wrap(a.cell),@"m_n64MesSvrID")==[m[@"id"] unsignedLongLongValue]) { target=a.cell; break; }
                if(target) {
                    [alert addAction:[UIAlertAction actionWithTitle:@"定位当前红包消息" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
                        UIView *cell=target;
                        if(!WUEnabled(@"redReminder") || ![account isEqual:Account()] || g!=generation || !cell.window || ![Session(Chat(cell)) isEqual:session] || Num(Wrap(cell),@"m_n64MesSvrID")!=[m[@"id"] unsignedLongLongValue]) return;
                        for(UIView *p=cell.superview;p;p=p.superview) if([p isKindOfClass:UIScrollView.class]) { [(UIScrollView *)p scrollRectToVisible:[cell convertRect:cell.bounds toView:p] animated:YES]; UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,cell); break; }
                    }]];
                } else alert.message=@"收到新的红包消息，请在会话列表打开对应聊天。本宿主跨会话定位接口尚未适配；不会自动领取。";
                [pendingAlerts addObject:alert]; [owner presentViewController:alert animated:YES completion:nil];
            } @catch(NSException *e) {}
        });
    } @catch(NSException *e) {}
}
BOOL WUMessageAvailable(NSString *key) {
    @try {
        Class base=NSClassFromString(@"BaseMsgContentViewController"), msg=NSClassFromString(@"CMessageWrap");
        if([key isEqual:@"chatSearch"]) return WUMatches(class_getInstanceMethod(base,NSSelectorFromString(@"onSearchItem")),"v",@[]);
        if([key isEqual:@"antiRevoke"]) return revokeOriginal && LookupReady(Service(@"CMessageMgr"));
        if([key isEqual:@"convenientMoments"]) return chatAppearOriginal && WUMomentsAvailable();
        if([key isEqual:@"callbackConfirm"]) return callbackOriginal!=NULL;
        if([key isEqual:@"multiRevoke"]) return chatAppearOriginal && WUMatches(class_getInstanceMethod(base,NSSelectorFromString(@"getSelectedMsgs")),"@",@[]) && RevokeSelector(Service(@"CMessageMgr"));
        if([key isEqual:@"repeatEmoticon"]) return cellLayoutOriginal && WUMatches(class_getInstanceMethod(msg,NSSelectorFromString(@"initWithMsgType:nsFromUsr:")),"@",@[@"q",@"@"]) && Has(Service(@"CMessageMgr"),@"AddEmoticonMsg:MsgWrap:","v",@[@"@",@"@"]);
        if([key hasPrefix:@"merge"]) return cellLayoutOriginal && WUMatches(class_getInstanceMethod(NSClassFromString(@"CommonMessageCellView"),NSSelectorFromString(@"viewModel")),"@",@[]);
        if([key isEqual:@"redReminder"]) return arrivalOriginal!=NULL;
    } @catch(NSException *e) {}
    return NO;
}
void WUInstallMessages(void) {
    WUInstallMoments();
    static dispatch_once_t once;
    dispatch_once(&once,^{
        chatActions=[NSHashTable weakObjectsHashTable]; cellActions=[NSHashTable weakObjectsHashTable]; pendingAlerts=[NSHashTable weakObjectsHashTable]; redSeen=[NSMutableOrderedSet orderedSet];
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            CancelPending(); for(WUChatActions *a in chatActions.allObjects) { @try { [a refresh]; } @catch(NSException *e) {} }
            for(WUCellActions *a in cellActions.allObjects) { [a restore]; if(!WUEnabled(@"repeatEmoticon")) { [a.repeat removeFromSuperview]; a.repeat=nil; } [a.cell setNeedsLayout]; }
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ for(WUChatActions *a in chatActions.allObjects) { @try { [a refresh]; } @catch(NSException *e) {} } }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardDidShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ for(WUChatActions *a in chatActions.allObjects) WURefreshMomentsInput(a.owner); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ CancelPending(); }];
    });
    WUHook(@"BaseMsgContentViewController",@"viewDidAppear:",NO,"v",@[@"B"],(IMP)ChatAppeared,&chatAppearOriginal);
    WUHook(@"BaseMsgContentViewController",@"viewDidDisappear:",NO,"v",@[@"B"],(IMP)ChatDisappeared,&chatDisappearOriginal);
    WUHook(@"MessageRevokeMgr",@"onRevokeMsg:",NO,"v",@[@"@"],(IMP)Revoke,&revokeOriginal);
    WUHook(@"VoIPBubbleMessageCellView",@"onClicked",NO,"v",@[],(IMP)Callback,&callbackOriginal);
    WUHook(@"CommonMessageCellView",@"layoutSubviews",NO,"v",@[],(IMP)CellLayout,&cellLayoutOriginal);
    WUHook(@"CommonMessageCellView",@"prepareForReuse",NO,"v",@[],(IMP)CellReuse,&cellReuseOriginal);
    WUHook(@"CMessageMgr",@"AsyncOnAddMsg:MsgWrap:",NO,"v",@[@"@",@"@"],(IMP)Arrival,&arrivalOriginal);
}

static void OpenStats(UIViewController *owner) {
    @try {
        NSString *account=Account(), *session=Session(owner); id mgr=Service(@"CMessageMgr");
        NSString *name=@"GetMsgByCreateTime:FromID:FromCreateTime:Limit:LeftCount:";
        Method method=class_getInstanceMethod(object_getClass(mgr),NSSelectorFromString(name));
        // Independently checked semantic contract: object session, 3 32-bit values,
        // pointer to 32-bit remaining count, object return (static PC 0x1599b44..68).
        BOOL checked=StatsReady(mgr);
        if(!checked || !account.length || !session.length) { Notice(owner,@"统计不可用：缺稳定账号、会话或已核验的32位分页接口。未调用宿主查询。"); return; }
        WUStatsBinding *binding=[WUStatsBinding new]; binding.account=account; binding.session=session; binding.group=[session hasSuffix:@"@chatroom"]; binding.messageManager=mgr;
        // Exact encoding is pinned only AFTER the independent semantic/width gate.
        binding.verifiedEncoding=[NSString stringWithUTF8String:method_getTypeEncoding(method)];
        binding.initialCursor=@{@"id":@0,@"time":@0}; // 0x158ca0c..30, not a guessed UINT_MAX cursor.
        NSUInteger g=generation; __weak UIViewController *weak=owner;
        binding.stillCurrent=^BOOL{ return weak && [WUValue(@"enabled") boolValue] && [account isEqual:Account()] && g==generation && [session isEqual:Session(weak)]; };
        BOOL group=binding.group;
        binding.decodePage=^NSDictionary *(NSArray *page,uint32_t left,NSDictionary *cursor) {
            NSMutableArray *records=[NSMutableArray arrayWithCapacity:page.count]; uint64_t minID=0, minTime=0;
            for(id wrap in page) {
                if(![wrap isKindOfClass:NSClassFromString(@"CMessageWrap")]) return nil;
                NSDictionary *m=Info(wrap); if(!InSession(m,account,session)) return nil;
                uint64_t local=[m[@"local"] unsignedLongLongValue], time=[m[@"time"] unsignedLongLongValue];
                if(local>UINT32_MAX || time>UINT32_MAX) return nil;
                if(local && (!minID || local<minID || (local==minID && time<minTime))) { minID=local; minTime=time; }
                NSString *sender=group?([m[@"from"] isEqual:account]?account:m[@"real"]):m[@"from"];
                NSString *type=@"other"; switch([m[@"type"] unsignedIntValue]) { case 1:type=@"text";break; case 3:type=@"image";break; case 34:type=@"voice";break; case 43:case 62:type=@"video";break; case 47:type=@"emoji";break; case 48:type=@"location";break; case 10000:type=@"system";break; default:break; }
                if([m[@"type"] unsignedIntValue]==49 && [Str(Obj(wrap,@"m_oWCPayInfoItem"),@"m_c2cNativeUrl") hasPrefix:@"wxpay://c2cbizmessagehandler/hongbao/receivehongbao?"]) type=@"redpacket";
                NSString *text=[type isEqual:@"text"]?Str(wrap,@"m_nsContent"):@"";
                if(text.length>8192) text=[text substringToIndex:8192];
                [records addObject:@{@"sid":[m[@"id"] stringValue],@"lid":[m[@"local"] stringValue],@"sender":sender?:@"",@"time":m[@"time"],@"type":type,@"text":text?:@"",@"source":@"normal"}];
            }
            // Do not equate a short page or an untrusted LeftCount alone with end.
            if(page.count && !minID) return nil;
            return @{@"records":[records copy],@"next":@{@"id":@(minID),@"time":@(minTime)},@"done":@(page.count==0 && left==0)};
        };
        WUStatsBindOwner(owner,binding); WUShowStats(owner);
    } @catch(NSException *e) { Notice(owner,@"统计绑定失败，未启动扫描。"); }
}

// Repository adapters reuse this module's exact account/session/generation checks.
static id RepositorySource(NSDictionary *identity, NSString *account) {
    id mgr=Service(@"CMessageMgr");
    if(!Has(mgr,@"GetMsg:LocalID:","@",@[@"@",@"I"]) && !Has(mgr,@"GetMsg:LocalID:","@",@[@"@",@"i"])) return nil;
    unsigned int local=[identity[@"local"] unsignedIntValue]; if(!local) return nil;
    id wrap=((id(*)(id,SEL,id,unsigned int))objc_msgSend)(mgr,NSSelectorFromString(@"GetMsg:LocalID:"),@"filehelper",local);
    return wrap && [Info(wrap) isEqual:identity] && InSession(identity,account,@"filehelper")?wrap:nil;
}
static void OpenRepository(UIViewController *owner) {
    NSString *account=Account(), *target=Session(owner); NSUInteger gen=generation;
    if(!account.length || !target.length) return;
    __weak UIViewController *weak=owner;
    WURepositoryBinding *binding=[WURepositoryBinding new]; binding.account=account; binding.target=target;
    BOOL (^current)(void)=^BOOL{
        UIViewController *v=weak;
        return v && (v.viewIfLoaded.window || WUIsRepositoryController(v.presentedViewController)) && (!v.navigationController || v.navigationController.topViewController==v) && UIApplication.sharedApplication.applicationState==UIApplicationStateActive && [WUValue(@"enabled") boolValue] && [account isEqual:Account()] && gen==generation && [target isEqual:Session(v)] && [WUToolbarActions(WUAccountOptions(account)[@"toolbar"]) containsObject:@"repository"];
    };
    binding.current=current;
    binding.capture=^NSArray *{
        @try {
            if(!current() || ![target isEqual:@"filehelper"]) return nil;
            id selected=Obj(weak,@"getSelectedMsgs");
            if(![selected isKindOfClass:NSArray.class] || ![selected count] || [selected count]>50) return nil;
            NSMutableArray *parts=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
            for(id wrap in [selected copy]) {
                NSDictionary *m=Info(wrap);
                if(!current() || !RepositorySource(m,account) || [seen containsObject:m[@"local"]]) return nil;
                [seen addObject:m[@"local"]]; [parts addObject:@{@"kind":@"reference",@"identity":m}];
            }
            [parts sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){ NSComparisonResult r=[a[@"identity"][@"time"] compare:b[@"identity"][@"time"]]; return r==NSOrderedSame?[a[@"identity"][@"local"] compare:b[@"identity"][@"local"]]:r; }];
            return [parts copy];
        } @catch(NSException *e) { return nil; }
    };
    binding.send=^NSString *(NSDictionary *part){
        if(!current()) return @"失败：上下文失效，未提交";
        if([part[@"kind"] isEqual:@"text"]) {
            id mgr=Service(@"CMessageMgr");
            if(!current()) return @"失败：上下文失效，未提交";
            // No AddMsg fallback after a possibly submitted call, and no AI helper.
            return WURepositoryInvoke(mgr,@"sendMsg:toContactUsrName:",part[@"text"],target);
        }
        id source=RepositorySource(part[@"identity"],account);
        if(!source) return @"失败：源消息已失效或查询接口不可用；不是独立备份";
        if([part[@"identity"][@"type"] unsignedIntValue]==34) return @"失败：普通转发不保证语音；请在聊天选择该语音并使用所选语音转发，未提交";
        id contacts=Service(@"CContactMgr");
        if(!Has(contacts,@"getContactByName:","@",@[@"@"])) return @"失败：目标查询不可用，未提交";
        id contact=((id(*)(id,SEL,id))objc_msgSend)(contacts,NSSelectorFromString(@"getContactByName:"),target);
        if(![Str(contact,@"m_nsUsrName") isEqual:target]) return @"失败：目标不符，未提交";
        Class cls=NSClassFromString(@"ForwardMessageLogicController");
        id forwarder=cls?[[cls alloc] init]:nil;
        if(!WURepositoryCanInvoke(forwarder,@"ForwardMsg:ToContact:")) return @"失败：转发协议不可用，未提交";
        if(!current() || ![Info(source) isEqual:part[@"identity"]]) return @"失败：源或目标变化，未提交";
        NSString *status=WURepositoryInvoke(forwarder,@"ForwardMsg:ToContact:",source,contact);
        // Retention matches the observed host adapter only; this is NOT a receipt timer.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{ (void)[forwarder class]; });
        return status;
    };
    WUShowRepository(owner,binding);
}

// Evidence: WCPulse 0xb8514 / 0xb8760-68 (NO,NO), 0x12be34 raw Photos resource.
static char emojiSaveKey;
static void SaveSelectedEmoticon(UIViewController *owner) {
    NSString *account=Account(), *session=Session(owner); NSUInteger gen=generation;
    id selected=Obj(owner,@"getSelectedMsgs");
    if(![selected isKindOfClass:NSArray.class] || [selected count]!=1) { Notice(owner,@"请先用微信长按菜单进入多选，仅选择一个表情，再打开此工具。不会读取未选择的消息。"); return; }
    id wrap=[selected firstObject]; NSDictionary *identity=Info(wrap);
    if(!account.length || !session.length || [identity[@"type"] unsignedIntValue]!=47 || !InSession(identity,account,session)) { Notice(owner,@"仅支持当前会话选中的单个表情；图片转表情尚未接入。"); return; }
    NSString *md5=Str(wrap,@"m_nsEmoticonMD5") ?: Str(Obj(wrap,@"m_extendInfoWithMsgType"),@"m_nsEmoticonMD5");
    Class util=NSClassFromString(@"EmoticonUtil"); NSString *selector=@"pathOfEmoticonForMd5:needUpdateTime:ignoreWxAM:";
    if(!WUValidMD5(md5) || !Has(util,selector,"@",@[@"@",@"B",@"B"])) { Notice(owner,@"原表情路径接口或签名不匹配，当前不可用；不会使用缩略图替代。"); return; }
    id path=((id(*)(id,SEL,id,BOOL,BOOL))objc_msgSend)(util,NSSelectorFromString(selector),md5,NO,NO);
    if(![path isKindOfClass:NSString.class] || ![path length]) { Notice(owner,@"原表情文件尚未就绪；不会自动下载或改写原消息。"); return; }
    // System authorization may resign active and invalidate the shared generation.
    // First authorization is deliberately permission-only, never an implicit retry/write.
    id usage=[NSBundle.mainBundle objectForInfoDictionaryKey:@"NSPhotoLibraryAddUsageDescription"];
    if(![usage isKindOfClass:NSString.class] || ![usage length]) { Notice(owner,@"宿主缺少添加照片权限声明，当前不可用，未保存。"); return; }
    PHAuthorizationStatus authorization=[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if(authorization==PHAuthorizationStatusNotDetermined) {
        UIAlertController *permission=[UIAlertController alertControllerWithTitle:@"先授权添加照片" message:@"本次只请求系统添加照片权限，不保存任何内容。授权完成后，请再次打开此工具并确认保存；不会跨失效会话自动写入。" preferredStyle:UIAlertControllerStyleAlert];
        [permission addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [permission addAction:[UIAlertAction actionWithTitle:@"请求权限" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            if(!owner.viewIfLoaded.window || ![account isEqual:WUCurrentAccount()] || gen!=WUContextGeneration() || ![session isEqual:WUChatSession(owner)] || ![WUValue(@"enabled") boolValue]) return;
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status){ /* Permission only. User must explicitly invoke the tool again. */ }];
        }]];
        [pendingAlerts addObject:permission]; [owner presentViewController:permission animated:YES completion:nil]; return;
    }
    if(authorization!=PHAuthorizationStatusAuthorized) { Notice(owner,@"没有添加照片权限，未保存。请在系统设置授权后再手动尝试。"); return; }
    NSMutableDictionary *prior=objc_getAssociatedObject(owner,&emojiSaveKey);
    if([prior[@"generation"] unsignedIntegerValue]!=gen) { prior=[NSMutableDictionary dictionaryWithObject:@(gen) forKey:@"generation"]; objc_setAssociatedObject(owner,&emojiSaveKey,prior,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if([prior[identity] unsignedIntegerValue]==gen) { Notice(owner,@"该选中表情本次页面已处理或正在保存。请先核对图库，不会重复提交。"); return; }
    if(prior.count>=101) { Notice(owner,@"本页面保存操作已达100次，请核对图库后重新进入聊天。"); return; }
    __weak UIViewController *weak=owner;
    BOOL (^current)(void)=^BOOL{
        @try {
        UIViewController *v=weak;
        if(!v.viewIfLoaded.window || (v.navigationController && v.navigationController.topViewController!=v) || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || ![WUValue(@"enabled") boolValue] || ![account isEqual:Account()] || gen!=generation || ![session isEqual:Session(v)] || ![WUToolbarActions(WUAccountOptions(account)[@"toolbar"]) containsObject:@"emojiSave"]) return NO;
        id now=Obj(v,@"getSelectedMsgs");
        return [now isKindOfClass:NSArray.class] && [now count]==1 && [now firstObject]==wrap && [Info(wrap) isEqual:identity];
        } @catch(NSException *e) { return NO; }
    };
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"保存原表情到图库？" message:@"仅复制所选表情原始GIF/PNG/JPEG；保留动画。缺失、损坏、特殊编码或超过20MiB将拒绝。允许后交由Photos写入，提交后不可撤销；不修改原消息。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __block BOOL consumed=NO;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存原表情" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        if(consumed) return; consumed=YES;
        [weak dismissViewControllerAnimated:YES completion:^{
            if(!current()) return;
            WUEmoticonSave *save=[WUEmoticonSave new];
            NSMutableDictionary *operations=objc_getAssociatedObject(weak,&emojiSaveKey);
            if(!operations) { operations=[NSMutableDictionary dictionary]; objc_setAssociatedObject(weak,&emojiSaveKey,operations,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            if([operations[identity] unsignedIntegerValue]==gen || operations.count>=101) return;
            operations[identity]=@(gen);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
                NSData *data=WUEmoticonRead(path);
                dispatch_async(dispatch_get_main_queue(),^{
                    [save startData:data current:current permission:^(void (^reply)(BOOL)){
                        // Missing privacy declaration must not terminate the host process.
                        id usage=[NSBundle.mainBundle objectForInfoDictionaryKey:@"NSPhotoLibraryAddUsageDescription"];
                        if(![usage isKindOfClass:NSString.class] || ![usage length]) { reply(NO); return; }
                        PHAuthorizationStatus status=[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
                        reply(status==PHAuthorizationStatusAuthorized);
                    } writer:^(NSData *original, NSString *uti, void (^reply)(BOOL)){
                        @try {
                            __block BOOL added=NO;
                            [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
                                @try {
                                __block BOOL valid=NO;
                                if(NSThread.isMainThread) valid=current(); else dispatch_sync(dispatch_get_main_queue(),^{ valid=current(); });
                                if(!valid) return;
                                PHAssetResourceCreationOptions *options=[PHAssetResourceCreationOptions new]; options.uniformTypeIdentifier=uti;
                                options.originalFilename=[@"Emoticon." stringByAppendingString:[uti isEqual:@"com.compuserve.gif"]?@"gif":([uti isEqual:@"public.png"]?@"png":@"jpg")];
                                PHAssetCreationRequest *request=[PHAssetCreationRequest creationRequestForAsset];
                                [request addResourceWithType:PHAssetResourceTypePhoto data:original options:options]; added=request!=nil;
                                } @catch(NSException *e) { added=NO; }
                            } completionHandler:^(BOOL success,NSError *error){ reply(added && success && !error); }];
                        } @catch(NSException *e) { reply(NO); }
                    } completion:^(NSString *result){
                        if([result isEqual:@"cancelled"] || !current()) return;
                        Notice(weak,@{@"saved":@"Photos已确认保存原表情。",@"failed":@"Photos未确认保存成功；请核对图库，未自动重试。",@"denied":@"没有添加照片权限或宿主缺少权限声明，未保存。",@"invalid":@"原文件缺失、损坏、超限或不是完整GIF/PNG/JPEG；未保存，未用静图替代。"}[result]);
                    }];
                });
            });
        }];
    }]];
    [pendingAlerts addObject:alert]; [owner presentViewController:alert animated:YES completion:nil];
}

static char voiceForwardKey;
static void ForwardSelectedVoice(UIViewController *owner) {
    NSString *account=Account(), *session=Session(owner); NSUInteger gen=generation;
    id selected=Obj(owner,@"getSelectedMsgs");
    if(!account.length || !session.length || ![selected isKindOfClass:NSArray.class] || [selected count]!=1) { Notice(owner,@"未提交：请先在聊天多选中只选一条已有语音。"); return; }
    id wrap=[selected firstObject]; NSDictionary *identity=Info(wrap);
    if(!InSession(identity,account,session) || (![identity[@"id"] unsignedLongLongValue] && ![identity[@"local"] unsignedIntValue])) { Notice(owner,@"失败：所选消息身份不可核验，未提交。"); return; }
    NSMutableDictionary *operations=objc_getAssociatedObject(owner,&voiceForwardKey);
    if([operations[@"generation"] unsignedIntegerValue]!=gen) { operations=[NSMutableDictionary dictionaryWithObject:@(gen) forKey:@"generation"]; objc_setAssociatedObject(owner,&voiceForwardKey,operations,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if(operations[identity]) { Notice(owner,operations[identity]); return; }
    if(operations.count>=101) { Notice(owner,@"本页面操作上限已到，请核对宿主后重新进入。"); return; }
    NSData *data=WUVoiceSelectedData(wrap);
    if(!data) { Notice(owner,@"失败：仅支持所选已有34类语音的原始数据与format 4配对；数据未就绪或ABI不符。未下载、未提交。"); return; }
    operations[identity]=@"未提交：等待收件人确认";
    __weak UIViewController *weak=owner;
    BOOL (^current)(void)=^BOOL {
        @try {
            UIViewController *v=weak;
            if(!v.viewIfLoaded.window || (v.navigationController && v.navigationController.topViewController!=v) || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || ![WUValue(@"enabled") boolValue] || ![account isEqual:Account()] || gen!=generation || ![session isEqual:Session(v)] || ![WUToolbarActions(WUAccountOptions(account)[@"toolbar"]) containsObject:@"voiceForward"]) return NO;
            id now=Obj(v,@"getSelectedMsgs");
            return [now isKindOfClass:NSArray.class] && [now count]==1 && [now firstObject]==wrap && [identity isEqual:Info(wrap)];
        } @catch(NSException *e) { return NO; }
    };
    UIAlertController *recipient=[UIAlertController alertControllerWithTitle:@"未提交：选择收件人" message:@"填写已有联系人或群的完整用户名，不使用昵称搜索，不拉取联系人列表。下一步仅离线验证，仍需再次确认发送。" preferredStyle:UIAlertControllerStyleAlert];
    [recipient addTextFieldWithConfigurationHandler:^(UITextField *field){ field.text=session; field.autocorrectionType=UITextAutocorrectionTypeNo; field.autocapitalizationType=UITextAutocapitalizationTypeNone; }];
    [recipient addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ [operations removeObjectForKey:identity]; }]];
    __weak UIAlertController *weakRecipient=recipient; __block BOOL chosen=NO;
    [recipient addAction:[UIAlertAction actionWithTitle:@"验证所选语音" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        if(chosen) return; chosen=YES;
        NSString *target=[weakRecipient.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [weak dismissViewControllerAnimated:YES completion:^{
            if(!current()) { operations[identity]=@"失败：上下文失效，未提交"; return; }
            @try {
                id contacts=Service(@"CContactMgr");
                if(!target.length || target.length>256 || !WUVoiceExactSignature(contacts,@"getContactByName:","@",@[@"@"])) { operations[identity]=@"失败：收件人接口不可用，未提交"; Notice(weak,operations[identity]); return; }
                id contact=((id(*)(id,SEL,id))objc_msgSend)(contacts,NSSelectorFromString(@"getContactByName:"),target);
                if(![Str(contact,@"m_nsUsrName") isEqual:target]) { operations[identity]=@"失败：收件人用户名不匹配，未提交"; Notice(weak,operations[identity]); return; }
            } @catch(NSException *e) { operations[identity]=@"失败：收件人核验异常，未提交"; Notice(weak,operations[identity]); return; }
            operations[identity]=@"未提交：正在离线解码所选语音";
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
                WUVoiceForwardOperation *operation=[[WUVoiceForwardOperation alloc] initWithData:data account:account target:target];
                dispatch_async(dispatch_get_main_queue(),^{
                    if(!current() || weak.presentedViewController) { operations[identity]=@"失败：上下文失效，未提交"; return; }
                    if(!operation.milliseconds) { operations[identity]=@"失败：仅接受完整SILK/AMR且真实时长不超过60秒；其他编码不转换、不发送"; Notice(weak,operations[identity]); return; }
                    operations[identity]=@"未提交：等待最终确认";
                    UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"确认普通语音转发" message:[NSString stringWithFormat:@"状态：未提交\n账号：%@\n收件人用户名：%@\n离线实测：%u毫秒\n保留所选原始编码与format；只请求一次，不保证送达，不回退、不自动重试。",account,target,operation.milliseconds] preferredStyle:UIAlertControllerStyleAlert];
                    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ [operations removeObjectForKey:identity]; }]];
                    __block BOOL confirmed=NO;
                    [confirm addAction:[UIAlertAction actionWithTitle:@"向此收件人请求发送一次" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
                        if(confirmed) return; confirmed=YES;
                        [weak dismissViewControllerAnimated:YES completion:^{
                            if(!current()) { operations[identity]=@"失败：确认失效，未提交"; return; }
                            @try { operations[identity]=[operation submitWithManager:Service(@"CMessageMgr") audioSender:Service(@"AudioSender") messageClass:NSClassFromString(@"CMessageWrap") current:current]; }
                            @catch(NSException *e) { operations[identity]=@"失败：服务获取异常，未提交"; }
                            Notice(weak,operations[identity]);
                        }];
                    }]];
                    [pendingAlerts addObject:confirm]; [weak presentViewController:confirm animated:YES completion:nil];
                });
            });
        }];
    }]];
    [pendingAlerts addObject:recipient]; [owner presentViewController:recipient animated:YES completion:nil];
}
