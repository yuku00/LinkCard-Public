#import "TestHost.h"
static UIAlertController *Alert(TestScene *f) { return (id)f.chat.presentedViewController; }
static void Pat(TestScene *f,id sender) { [f.cell onHeadImageDoubleClick:sender]; }
static void Game(TestScene *f) { [f.manager AddEmoticonMsg:f.chat.session MsgWrap:f.cell.viewModel.messageWrap]; }
static void Touch(TestScene *f) { UITouch *t=[UITouch new]; t.phase=UITouchPhaseBegan; [f.chat mmTableView:f.table touchesBegan:[NSSet setWithObject:t] withEvent:[UIEvent new]]; }
static void PatTests(void) {
    TestConfig(@{@"patConfirm":@YES});
    TestScene *f=[TestScene new]; id opaque=[NSObject new]; Pat(f,opaque);
    UIAlertController *a=Alert(f); assert(a && f.cell.pats==0); Pat(f,opaque); assert(Alert(f)==a && f.chat.presents==1);
    [a.actions[1] fire]; [a.actions[1] fire]; assert(f.cell.pats==1 && f.cell.receivedSender==opaque && !Alert(f));
    f=[TestScene new]; Pat(f,f.cell.head); a=Alert(f); [a.actions[0] fire]; [a.actions[1] fire]; assert(!f.cell.pats && !Alert(f));
    f=[TestScene new]; Pat(f,f.cell.head); [Alert(f).actions[1] fire]; assert(f.cell.pats==1 && f.cell.receivedSender==f.cell.head);
    f=[TestScene new]; Pat(f,[NSObject new]); a=Alert(f); assert(WUNativeOwnsController(a));
    [a dismissViewControllerAnimated:NO completion:nil]; [a.actions[1] fire]; assert(f.cell.pats==1); // UIKit auto-dismissed before handler
    f=[TestScene new]; Pat(f,[NSObject new]); a=Alert(f); a.deferDismissCompletion=YES; [a.actions[1] fire];
    assert(!f.cell.pats); TestConfig(@{@"patConfirm":@NO}); WUTestFlushDismissals(); [a.actions[1] fire]; assert(!f.cell.pats);
    TestConfig(@{@"patConfirm":@YES});
    // Same object pointer, different author/session/IDs/type must invalidate.
    for(NSUInteger mutation=0;mutation<14;mutation++) {
        f=[TestScene new]; TestConfig(@{@"patConfirm":@YES}); Pat(f,[NSObject new]); a=Alert(f); assert(a);
        CMessageWrap *w=f.cell.viewModel.messageWrap;
        switch(mutation) {
            case 0:w.m_nsFromUsr=@"other";break;
            case 1:w.m_nsRealChatUsr=@"other-member";break;
            case 2:w.m_nsToUsr=@"other-chat";break;
            case 3:w.m_n64MesSvrID++;break;
            case 4:w.m_uiMesLocalID++;break;
            case 5:w.m_uiCreateTime++;break;
            case 6:w.m_uiMessageType=1;break;
            case 7:f.cell.viewModel=[Model new];break;
            case 8:[f.cell.head removeFromSuperview]; f.cell.head=[UIView new]; [f.cell addSubview:f.cell.head];break;
            case 9:testAccount=@"B";testGeneration++;break;
            case 10:f.chat.session=@"chat-B";break;
            case 11:UIApplication.sharedApplication.applicationState=UIApplicationStateBackground; [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];break;
            case 12:TestConfig(@{@"patConfirm":@NO});break;
            case 13:[f.cell removeFromSuperview];break;
        }
        WUNativeRefreshActions(); assert(!Alert(f)); [a.actions[1] fire]; assert(!f.cell.pats);
    }
    f=[TestScene new]; TestConfig(@{@"patConfirm":@YES}); Pat(f,[NSObject new]); a=Alert(f);
    UIViewController *foreign=[UIViewController new]; f.chat.presentedViewController=foreign; WUNativeRefreshActions(); assert(f.chat.presentedViewController==foreign); [a.actions[1] fire]; assert(!f.cell.pats);
    f=[TestScene new]; f.cell.throwPat=YES; Pat(f,[NSObject new]); WUNativeAction *op=WUNativePendingAction(@"patConfirm",testAccount,f.chat.session); a=Alert(f); [a.actions[1] fire]; [a.actions[1] fire]; assert(f.cell.pats==1 && [op.outcome isEqual:@"unknown"]);
    f=[TestScene new]; TestConfig(@{@"patConfirm":@NO}); opaque=[NSObject new]; Pat(f,opaque); assert(f.cell.pats==1 && !Alert(f) && f.cell.receivedSender==opaque);
}
static void KeyboardTests(void) {
    TestConfig(@{@"keepKeyboard":@YES}); TestScene *f=[TestScene new]; Touch(f);
    assert(f.chat.touches==1 && !f.chat.hides && !f.tool.hides && !f.tool.resigns && f.tool.editor.isFirstResponder);
    [f.chat hideInputToolView]; [f.tool hideToolView:NO]; [f.tool resignFirstResponder]; assert(f.chat.hides==1 && f.tool.hides==1 && f.tool.resigns==1);
    for(NSUInteger kind=0;kind<4;kind++) {
        f=[TestScene new];
        if(kind==0) f.table.hitResult=f.cell.head;
        if(kind==1) f.table.hitResult=f.table;
        if(kind==2) { UIControl *control=[UIControl new]; [f.voice.m_bgImageView addSubview:control]; f.table.hitResult=control; }
        if(kind==3) TestConfig(@{@"keepKeyboard":@NO});
        Touch(f); assert(f.chat.touches==1 && f.chat.hides==1 && f.tool.hides==1 && f.tool.resigns==1);
    }
    f=[TestScene new]; TestConfig(@{@"keepKeyboard":@YES}); f.chat.throwTouch=YES;
    @try { Touch(f); assert(0); } @catch(NSException *e) {}
    [f.chat hideInputToolView]; assert(f.chat.hides==1); // finally cleared the production scope
}
static void GameTests(void) {
    TestConfig(@{@"gameChoice":@YES});
    for(unsigned type=1;type<=2;type++) for(unsigned choice=0;choice<(type==1?3:6);choice++) {
        TestScene *f=[TestScene new]; CMessageWrap *source=f.cell.viewModel.messageWrap; source.m_uiGameType=type;
        Game(f); UIAlertController *a=Alert(f); assert(a && !f.manager.sends); Game(f); assert(Alert(f)==a && f.chat.presents==1 && !f.manager.sends);
        // Pending retained the copy, not live mutable source fields.
        source.m_uiGameContent=99; source.m_nsFromUsr=@"mutated-source"; source.m_uiCreateTime=1;
        f.manager.reenter=YES; [a.actions[choice] fire]; [a.actions[choice] fire];
        CMessageWrap *w=f.manager.sent;
        assert(f.manager.sends==1 && w!=source && w.m_uiGameContent==(type==1?choice+1:choice+4));
        assert([w.m_nsFromUsr isEqual:testAccount] && [w.m_nsToUsr isEqual:f.chat.session] && !w.m_nsRealChatUsr.length);
        assert(!w.m_n64MesSvrID && !w.m_uiMesLocalID && w.m_uiCreateTime>100);
        assert(source.m_n64MesSvrID==5000000001LL && source.m_uiMesLocalID==4 && source.m_uiGameContent==99 && [source.m_nsEmoticonMD5 isEqual:@"original"]);
    }
    TestScene *f=[TestScene new]; Game(f); UIAlertController *a=Alert(f); [a.actions.lastObject fire]; [a.actions[0] fire]; assert(!f.manager.sends);
    for(NSUInteger mutation=0;mutation<5;mutation++) {
        f=[TestScene new]; TestConfig(@{@"gameChoice":@YES}); Game(f); a=Alert(f); assert(a);
        if(mutation==0) { testAccount=@"B"; testGeneration++; }
        if(mutation==1) f.chat.session=@"B";
        if(mutation==2) TestConfig(@{@"gameChoice":@NO});
        if(mutation==3) { UIApplication.sharedApplication.applicationState=UIApplicationStateBackground; [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil]; }
        if(mutation==4) [f.chat.view removeFromSuperview];
        WUNativeRefreshActions(); assert(!Alert(f)); [a.actions[0] fire]; assert(!f.manager.sends);
    }
    // A foreign modal keeps the underlying chat and must never bypass the chooser.
    f=[TestScene new]; TestConfig(@{@"gameChoice":@YES}); f.chat.presentedViewController=[UIAlertController new]; Game(f); assert(!f.manager.sends);
    f=[TestScene new]; [f.manager AddEmoticonMsg:@"non-current" MsgWrap:f.cell.viewModel.messageWrap]; assert(f.manager.sends==1 && [f.manager.destination isEqual:@"non-current"]);
    f=[TestScene new]; UIApplication.sharedApplication.applicationState=UIApplicationStateBackground; Game(f); assert(f.manager.sends==1 && f.manager.sent==f.cell.viewModel.messageWrap);
    f=[TestScene new]; f.manager.throws=YES; Game(f); WUNativeAction *op=WUNativePendingAction(@"gameChoice",testAccount,f.chat.session); a=Alert(f); [a.actions[0] fire]; [a.actions[0] fire]; assert(f.manager.sends==1 && [op.outcome isEqual:@"unknown"]);
    // The original sender manager and presenting controller survive the UI delay.
    f=[TestScene new]; Game(f); __weak CMessageMgr *weakManager=f.manager; f.manager=nil; assert(weakManager);
    a=Alert(f); [a.actions[0] fire]; assert(!WUNativePendingAction(@"gameChoice",testAccount,f.chat.session));
    f=[TestScene new]; Game(f); __weak BaseMsgContentViewController *weakOwner=f.chat;
    f.window.rootViewController=nil; f.chat=nil; assert(weakOwner); // pending operation retains original presenter
    WUNativeRefreshActions(); // disappearance cancels rather than retargeting
    f=[TestScene new]; testThrowCopy=YES; Game(f); assert(!Alert(f) && !f.manager.sends); testThrowCopy=NO;
    for(NSUInteger fault=0;fault<2;fault++) {
        f=[TestScene new]; Game(f); op=WUNativePendingAction(@"gameChoice",testAccount,f.chat.session); a=Alert(f);
        if(fault==0) testBadMD5=YES; else testSwitchOnEnvelope=YES;
        [a.actions[0] fire]; [a.actions[0] fire];
        assert(!f.manager.sends && [op.outcome isEqual:@"not-submitted"]); testBadMD5=NO; testSwitchOnEnvelope=NO;
    }
}
int main(int argc,const char **argv) { @autoreleasepool {
    TestInit();
    if(argc>1) {
        // Built with WU_TEST_BAD_ABI: actual declarations/implementations differ.
        // class_replaceMethod alone would preserve the original method encoding.
        Method pat=class_getInstanceMethod(CommonMessageCellView.class,@selector(onHeadImageDoubleClick:));
        Method time=class_getInstanceMethod(CMessageWrap.class,@selector(setM_uiCreateTime:));
        assert(!WUMatches(pat,"v",@[@"@"]));
        assert(WUMatches(time,"v",@[@"d"]));
        WUInstallNativeInteractions(); WUInstallNativeGames();
        assert(!WUNativeInteractionAvailable(@"patConfirm") && !WUNativeGameAvailable());
        puts("PASS full production entry signature rejection"); return 0;
    }
    WUInstallNativeInteractions(); WUInstallNativeGames(); WUInstallNativeInteractions(); WUInstallNativeGames();
    assert(WUNativeInteractionAvailable(@"patConfirm") && WUNativeInteractionAvailable(@"keepKeyboard") && WUNativeGameAvailable());
    PatTests(); KeyboardTests(); GameTests(); WUNativeCancelActions();
    puts("PASS full production Interactions + Games + Action + MessageConstruction, real Core hooks, UIKit mock (not device)");
} return 0; }
