#import "WUNativeAction.h"
#import "MessageConstruction.h"
#include <limits.h>
static IMP sendOriginal;
static BOOL ready;
static BOOL Has(id x,NSString *s,const char *ret,NSArray *args) {
    return x && WUMatches(class_getInstanceMethod(object_getClass(x),NSSelectorFromString(s)),ret,args);
}
static UIViewController *Chat(void) {
    for(UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if(s.activationState!=UISceneActivationStateForegroundActive || ![s isKindOfClass:UIWindowScene.class]) continue;
        for(UIWindow *w in ((UIWindowScene *)s).windows) if(w.isKeyWindow) {
            UIViewController *v=w.rootViewController;
            for(unsigned n=0;v && n<32;n++) {
                // A presented sheet is not a chat. Keep the underlying session;
                // Send rejects its pending/foreign modal instead of bypassing confirmation.
                if([v isKindOfClass:NSClassFromString(@"BaseMsgContentViewController")]) return v;
                if([v isKindOfClass:UINavigationController.class]) v=((UINavigationController *)v).visibleViewController;
                else if([v isKindOfClass:UITabBarController.class]) v=((UITabBarController *)v).selectedViewController;
                else if(v.presentedViewController && ![v.presentedViewController isKindOfClass:UIAlertController.class]) v=v.presentedViewController;
                else break;
            }
            return v;
        }
    }
    return nil;
}
static BOOL ResetEnvelope(id copy, NSString *account, NSString *session) {
    NSArray *keys=@[@"m_nsFromUsr",@"m_nsToUsr",@"m_nsRealChatUsr"];
    NSArray *values=@[account,session,@""];
    for(NSUInteger i=0;i<keys.count;i++) {
        NSString *setter=[NSString stringWithFormat:@"set%@%@:",[[keys[i] substringToIndex:1] uppercaseString],[keys[i] substringFromIndex:1]];
        if(!Has(copy,setter,"v",@[@"@"])) return NO;
        ((void(*)(id,SEL,id))objc_msgSend)(copy,NSSelectorFromString(setter),values[i]);
        if(![WUNativeString(copy,keys[i]) isEqual:values[i]]) return NO;
    }
    uint64_t now=(uint64_t)NSDate.date.timeIntervalSince1970;
    if(!WUNativeSetUnsigned(copy,@"setM_n64MesSvrID:",0) || !WUNativeSetUnsigned(copy,@"setM_uiMesLocalID:",0) ||
       !WUNativeSetUnsigned(copy,@"setM_uiCreateTime:",now)) return NO;
    return [WUNativeUnsigned(copy,@"m_n64MesSvrID") isEqual:@0] &&
        [WUNativeUnsigned(copy,@"m_uiMesLocalID") isEqual:@0] && [WUNativeUnsigned(copy,@"m_uiCreateTime") isEqual:@(now)];
}
static void Send(id manager,SEL cmd,id destination,id source) {
    if(!NSThread.isMainThread) {
        // This adapter only intercepts main-thread interactive sends. No UI hop or reroute.
        ((void(*)(id,SEL,id,id))sendOriginal)(manager,cmd,destination,source); return;
    }
    NSString *account=[WUCurrentAccount() copy];
    // Recognize a pending operation before traversing presentation or any passthrough.
    WUNativeAction *prior=[destination isKindOfClass:NSString.class]?WUNativePendingAction(@"gameChoice",account,destination):nil;
    if(prior) { WUNativeRefreshActions(); return; }
    WUNativeRefreshActions();
    unsigned type=0;
    @try { type=WUNativeGameNumber(source,@"m_uiGameType"); } @catch(NSException *e) { return; }
    if(!WUNativeEnabled(@"gameChoice") || (type!=1 && type!=2) || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) {
        ((void(*)(id,SEL,id,id))sendOriginal)(manager,cmd,destination,source); return;
    }
    UIViewController *owner=Chat();
    if(!owner || !owner.viewIfLoaded.window || ![destination isKindOfClass:NSString.class] || ![destination isEqual:WUChatSession(owner)]) {
        // No pending matching operation: non-current-chat and background sends pass unchanged once.
        ((void(*)(id,SEL,id,id))sendOriginal)(manager,cmd,destination,source); return;
    }
    if(owner.presentedViewController || !account.length) return;
    NSString *session=[destination copy]; NSUInteger generation=WUContextGeneration(); id options=WUValue(@"native");
    id copy=nil;
    @try {
        if(WUNativeGameNumber(source,@"m_uiMessageType")==47 && Has(source,@"copyToMsg:","v",@[@"@"])) {
            copy=WUCreateMessage(NSClassFromString(@"CMessageWrap"),47,account);
            if(copy && copy!=source) ((void(*)(id,SEL,id))objc_msgSend)(source,NSSelectorFromString(@"copyToMsg:"),copy);
            else copy=nil;
        }
    } @catch(NSException *e) { copy=nil; }
    if(!copy) return;
    // Do not reread source after opening UI. copyToMsg may carry IDs/account/time;
    // all send-envelope fields are checked and overwritten immediately before sending.
    WUNativeAction *op=[WUNativeAction new]; op.owner=owner; op.account=account; op.session=session; op.key=@"gameChoice";
    BOOL (^current)(void)=^BOOL{
        return Chat()==owner && WUNativeEnabled(@"gameChoice") && UIApplication.sharedApplication.applicationState==UIApplicationStateActive &&
            options==WUValue(@"native") && [session isEqual:WUChatSession(owner)] &&
            [account isEqual:WUCurrentAccount()] && generation==WUContextGeneration();
    };
    op.valid=current;
    op.commit=^(NSUInteger choice){
        if(!WUNativeApplyGameChoice(copy,type,(unsigned)choice) || !ResetEnvelope(copy,account,session) || !current())
            @throw [NSException exceptionWithName:@"WUNativePreparationFailed" reason:@"No send was attempted" userInfo:nil];
        ((void(*)(id,SEL,id,id))sendOriginal)(manager,cmd,session,copy);
    };
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:type==1?@"选择猜拳":@"选择骰子点数" message:@"仅供非金钱娱乐；实际对端结果以微信为准。选择后发送一次。" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles=type==1?@[@"剪刀",@"石头",@"布"]:@[@"1",@"2",@"3",@"4",@"5",@"6"];
    __weak WUNativeAction *weak=op;
    for(NSUInteger choice=0;choice<titles.count;choice++) [sheet addAction:[UIAlertAction actionWithTitle:titles[choice] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [weak choose:choice]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ [weak cancel]; }]];
    sheet.popoverPresentationController.sourceView=owner.view;
    sheet.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(owner.view.bounds),CGRectGetMidY(owner.view.bounds),1,1);
    op.alert=sheet; [op present];
}
void WUInstallNativeGames(void) {
    if(!WUNativeGuardAllowsHooks()) return;
    if(sendOriginal) return;
    Class c=NSClassFromString(@"CMessageWrap");
    if(!WUMessageCanConstruct(c)) return;
    for(NSString *getter in @[@"m_n64MesSvrID",@"m_uiMesLocalID",@"m_uiCreateTime"]) {
        NSString *setter=[NSString stringWithFormat:@"set%@%@:",[[getter substringToIndex:1] uppercaseString],[getter substringFromIndex:1]];
        if(!WUNativeNumberField(c,getter,setter)) return;
    }
    for(NSString *getter in @[@"m_nsFromUsr",@"m_nsToUsr",@"m_nsRealChatUsr"]) {
        NSString *setter=[NSString stringWithFormat:@"set%@%@:",[[getter substringToIndex:1] uppercaseString],[getter substringFromIndex:1]];
        if(!WUMatches(class_getInstanceMethod(c,NSSelectorFromString(getter)),"@",@[]) ||
           !WUMatches(class_getInstanceMethod(c,NSSelectorFromString(setter)),"v",@[@"@"])) return;
    }
    for(NSString *key in @[@"m_uiMessageType",@"m_uiGameType",@"m_uiGameContent"]) {
        Method m=class_getInstanceMethod(c,NSSelectorFromString(key));
        if(!WUMatches(m,"I",@[]) && !WUMatches(m,"Q",@[]) && !WUMatches(m,"q",@[])) return;
    }
    Method setter=class_getInstanceMethod(c,NSSelectorFromString(@"setM_uiGameContent:"));
    if(!WUMatches(setter,"v",@[@"I"]) && !WUMatches(setter,"v",@[@"Q"]) && !WUMatches(setter,"v",@[@"q"])) return;
    if(!WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"copyToMsg:")),"v",@[@"@"]) ||
       !WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"setM_nsEmoticonMD5:")),"v",@[@"@"])) return;
    id game=NSClassFromString(@"GameController");
    if(!Has(game,@"getMD5ByGameContent:","@",@[@"I"]) && !Has(game,@"getMD5ByGameContent:","@",@[@"Q"]) && !Has(game,@"getMD5ByGameContent:","@",@[@"q"])) return;
    ready=WUHook(@"CMessageMgr",@"AddEmoticonMsg:MsgWrap:",NO,"v",@[@"@",@"@"],(IMP)Send,&sendOriginal) && sendOriginal;
}
BOOL WUNativeGameAvailable(void) { return ready; }
