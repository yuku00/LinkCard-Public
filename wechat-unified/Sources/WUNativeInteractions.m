#import "WUNativeAction.h"
static IMP touchesOriginal, hideOriginal, toolHideOriginal, resignOriginal, patOriginal;
static BOOL keyboardReady, patReady;
static __weak UIViewController *scopeOwner;
static __weak UIView *scopeTool, *scopeEditor;
static NSUInteger scopeGeneration;
static unsigned scopeDepth;
static id Get(id x, NSString *name) {
    SEL s=NSSelectorFromString(name);
    if(!x || !WUMatches(class_getInstanceMethod(object_getClass(x),s),"@",@[])) return nil;
    @try { return ((id(*)(id,SEL))objc_msgSend)(x,s); } @catch(NSException *e) { return nil; }
}
static UIViewController *Owner(UIView *view) {
    UIResponder *r=view;
    for(unsigned i=0;r && i<128;i++,r=r.nextResponder)
        if([r isKindOfClass:UIViewController.class]) return (id)r;
    return nil;
}
static UIView *Editor(UIView *view, unsigned *budget) {
    if(!view || !*budget) return nil;
    --*budget;
    if(view.isFirstResponder && ([view isKindOfClass:UITextView.class] || [view isKindOfClass:UITextField.class])) return view;
    for(UIView *v in view.subviews) { UIView *found=Editor(v,budget); if(found) return found; }
    return nil;
}
static BOOL Preserve(id object, BOOL owner) {
    if(!NSThread.isMainThread || !scopeDepth) return NO;
    return WUNativeKeepFocus(WUNativeEnabled(@"keepKeyboard"),NSThread.isMainThread,scopeDepth>0,
        object==(owner?(id)scopeOwner:(id)scopeTool),scopeEditor.isFirstResponder && scopeEditor.window!=nil,
        scopeGeneration==WUContextGenerationSnapshot());
}
static void Hide(id x,SEL s) { if(!Preserve(x,YES)) ((void(*)(id,SEL))hideOriginal)(x,s); }
static void ToolHide(id x,SEL s,BOOL animated) { if(!Preserve(x,NO)) ((void(*)(id,SEL,BOOL))toolHideOriginal)(x,s,animated); }
static BOOL Resign(id x,SEL s) { return Preserve(x,NO)?NO:((BOOL(*)(id,SEL))resignOriginal)(x,s); }
static void Touches(UIViewController *owner,SEL cmd,id table,id touches,id event) {
    BOOL qualify=NSThread.isMainThread && WUNativeEnabled(@"keepKeyboard") && !scopeDepth &&
        [table isKindOfClass:UITableView.class] && [touches isKindOfClass:NSSet.class] &&
        [touches count]==1 && owner.isViewLoaded && owner.view.window && !owner.presentedViewController;
    UIView *editor=nil,*tool=nil;
    if(qualify) {
        UITouch *touch=[touches anyObject];
        if(![touch isKindOfClass:UITouch.class] || touch.phase!=UITouchPhaseBegan) qualify=NO;
        UIView *hit=qualify?[table hitTest:[touch locationInView:table] withEvent:event]:nil;
        UIView *voice=hit;
        Class voiceClass=NSClassFromString(@"VoiceMessageCellView");
        for(unsigned i=0;voice && i<64 && ![voice isKindOfClass:voiceClass];i++) voice=voice.superview;
        id bubble=nil;
        @try { if(voiceClass && [voice isKindOfClass:voiceClass]) bubble=[voice valueForKey:@"m_bgImageView"]; } @catch(NSException *e) {}
        // Only the playback bubble, not its avatar, row background, menu or progress controls.
        qualify=[bubble isKindOfClass:UIView.class] && hit && [hit isDescendantOfView:bubble] && ![hit isKindOfClass:UIControl.class];
        unsigned budget=256; editor=qualify?Editor(owner.view,&budget):nil;
        Class toolClass=NSClassFromString(@"MMInputToolView"); tool=editor;
        for(unsigned i=0;tool && i<64 && ![tool isKindOfClass:toolClass];i++) tool=tool.superview;
        qualify=qualify && toolClass && [tool isKindOfClass:toolClass] && [tool isDescendantOfView:owner.view];
    }
    if(!qualify) { ((void(*)(id,SEL,id,id,id))touchesOriginal)(owner,cmd,table,touches,event); return; }
    scopeOwner=owner; scopeTool=tool; scopeEditor=editor; scopeGeneration=WUContextGeneration(); scopeDepth=1;
    @try { ((void(*)(id,SEL,id,id,id))touchesOriginal)(owner,cmd,table,touches,event); }
    @finally { scopeDepth=0; scopeOwner=nil; scopeTool=nil; scopeEditor=nil; }
    // No delayed becomeFirstResponder and no global resign hook; explicit user dismiss always wins.
}
static BOOL PatIdentity(NSDictionary *f, NSString *account, NSString *session) {
    if(!f || (![f[@"m_n64MesSvrID"] unsignedLongLongValue] && ![f[@"m_uiMesLocalID"] unsignedLongLongValue])) return NO;
    NSString *from=f[@"m_nsFromUsr"], *to=f[@"m_nsToUsr"], *real=f[@"m_nsRealChatUsr"];
    if([from isEqual:account] && [to isEqual:session]) return YES;
    return [from isEqual:session] && [to isEqual:account] && (![session hasSuffix:@"@chatroom"] || real.length);
}
static void Pat(UIView *cell,SEL cmd,id sender) {
    if(!WUNativeEnabled(@"patConfirm")) { ((void(*)(id,SEL,id))patOriginal)(cell,cmd,sender); return; }
    if(!NSThread.isMainThread) return;
    @try {
        UIViewController *owner=Owner(cell);
        NSString *account=[WUCurrentAccount() copy], *session=[WUChatSession(owner) copy];
        WUNativeAction *prior=WUNativePendingAction(@"patConfirm",account,session);
        if(prior) { WUNativeRefreshActions(); return; }
        if(!cell.window || !owner || owner.presentedViewController || !account.length || !session.length) return;
        id model=Get(cell,@"viewModel"), message=Get(model,@"messageWrap");
        NSDictionary *identity=WUNativeMessageIdentity(message);
        // WCPulse 0xf2bf8..0xf2cbc: UIView sender OR cell.getHeadImageView.
        // The exported body does not require a gesture/delegate protocol: retain and
        // pass the original opaque object unchanged; never send invented selectors.
        UIView *head=Get(cell,@"getHeadImageView");
        UIView *anchor=[sender isKindOfClass:UIView.class]?sender:head;
        if(![head isKindOfClass:UIView.class] || ![anchor isKindOfClass:UIView.class] ||
           ![head isDescendantOfView:cell] || ![anchor isDescendantOfView:head] ||
           !PatIdentity(identity,account,session)) return;
        NSUInteger generation=WUContextGeneration(); id options=WUValue(@"native");
        __weak UIView *weakCell=cell;
        WUNativeAction *op=[WUNativeAction new]; op.key=@"patConfirm"; op.account=account; op.session=session; op.owner=owner;
        op.valid=^BOOL{
            UIView *c=weakCell;
            return c.window && Owner(c)==owner && Get(c,@"viewModel")==model && Get(model,@"messageWrap")==message &&
                Get(c,@"getHeadImageView")==head && [head isDescendantOfView:c] && [anchor isDescendantOfView:head] &&
                [WUNativeMessageIdentity(message) isEqual:identity] && options==WUValue(@"native") &&
                [account isEqual:WUCurrentAccount()] && [session isEqual:WUChatSession(owner)] && generation==WUContextGeneration();
        };
        op.commit=^(NSUInteger choice){ ((void(*)(id,SEL,id))patOriginal)(weakCell,cmd,sender); };
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"确认拍一拍？" message:@"确认后仅调用本次头像原UI动作一次；取消不发送。" preferredStyle:UIAlertControllerStyleAlert];
        __weak WUNativeAction *weak=op;
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ [weak cancel]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"拍一拍" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [weak choose:0]; }]];
        op.alert=alert; [op present];
    } @catch(NSException *e) { /* No original fallback while confirmation is enabled. */ }
}
static BOOL Hook(NSString *c,NSString *s,const char *ret,NSArray *args,IMP imp,IMP *orig) {
    if(*orig) return YES;
    return WUHook(c,s,NO,ret,args,imp,orig) && *orig;
}
void WUInstallNativeInteractions(void) {
    if(!WUNativeGuardAllowsHooks()) return;
    BOOL a=Hook(@"BaseMsgContentViewController",@"mmTableView:touchesBegan:withEvent:","v",@[@"@",@"@",@"@"],(IMP)Touches,&touchesOriginal);
    BOOL b=Hook(@"BaseMsgContentViewController",@"hideInputToolView","v",@[],(IMP)Hide,&hideOriginal);
    BOOL c=Hook(@"MMInputToolView",@"hideToolView:","v",@[@(@encode(BOOL))],(IMP)ToolHide,&toolHideOriginal);
    BOOL d=Hook(@"MMInputToolView",@"resignFirstResponder",@encode(BOOL),@[],(IMP)Resign,&resignOriginal);
    keyboardReady=a&&b&&c&&d;
    patReady=Hook(@"CommonMessageCellView",@"onHeadImageDoubleClick:","v",@[@"@"],(IMP)Pat,&patOriginal);
}
BOOL WUNativeInteractionAvailable(NSString *key) {
    if([key isEqual:@"keepKeyboard"]) return keyboardReady;
    if([key isEqual:@"patConfirm"]) return patReady;
    return NO;
}
