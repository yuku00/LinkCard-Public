#import "WU.h"
#import "InteractionLogic.h"
#import <QuartzCore/QuartzCore.h>
static NSHashTable<UIView *> *styled;
static char childrenKey,cardKey,referTargetKey,bubbleImageKey;
static NSMutableSet<NSString *> *cardRoles;
static void Restore(UIView *v);
void WURestoreMessageSurface(UIView *cell) {
    UIView *target=objc_getAssociatedObject(cell,&cardKey);
    if(target) {
        NSDictionary *imageState=objc_getAssociatedObject(target,&bubbleImageKey);
        if(imageState && [(UIImageView *)target image]==imageState[@"applied"]) [(UIImageView *)target setImage:imageState[@"old"]];
        objc_setAssociatedObject(target,&bubbleImageKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        Restore(target);
    }
    objc_setAssociatedObject(cell,&cardKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static IMP searchLayout,referLayout,plusLayout,toastLayout,timeLayout,swipeLayout;
static IMP referWindow,toastWindow;
static void RestoreHostPopup(UIView *view);
static void RefreshHostPopup(UIView *view);
static void Restore(UIView *v) { WURestoreConfiguredSurface(v); }
// Restore before UIKit's original callback, then request a fresh layout if reattached.
static void RestoreRefer(UIView *v) {
    UIView *target=objc_getAssociatedObject(v,&referTargetKey);
    if(target && target!=v) Restore(target);
    objc_setAssociatedObject(v,&referTargetKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Restore(v);
}
static void ReferWindow(UIView *v,SEL s) { RestoreRefer(v); ((void(*)(id,SEL))referWindow)(v,s); if(v.window) [v setNeedsLayout]; }
static void ToastWindow(UIView *v,SEL s) { RestoreHostPopup(v); Restore(v); ((void(*)(id,SEL))toastWindow)(v,s); if(v.window) [v setNeedsLayout]; }
static void WUStyleSurface(UIView *v,NSString *key,CGFloat radius) {
    WUApplyConfiguredSurface(v,key,radius,YES); if(WUEnabled(key)) [styled addObject:v];
}
BOOL WUCardSurfaceAvailable(NSString *key) { return [cardRoles containsObject:key]; }
void WURefreshMessageSurface(UIView *cell,NSString *role) {
    WURestoreMessageSurface(cell);
    if(![@[@"fileSurface",@"emoticonSurface",@"textBubbleSurface"] containsObject:role] || !cell.window) return;
    if([role isEqual:@"textBubbleSurface"]) {
        Class textClass=NSClassFromString(@"TextMessageCellView");
        if(!textClass || ![textClass isSubclassOfClass:UIView.class] || ![cell isKindOfClass:textClass]) return;
    }
    // m_bgImageView is the existing evidence-backed CommonMessageCellView background role.
    id target=nil; @try { target=[cell valueForKey:@"m_bgImageView"]; } @catch(NSException *e) { return; }
    if(![target isKindOfClass:UIImageView.class] || target==cell || ![target isDescendantOfView:cell]) return;
    [cardRoles addObject:role];
    WUStyleSurface(target,role,14);
    if(WUEnabled(role)) {
        objc_setAssociatedObject(cell,&cardKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIImageView *imageView=target;
        if([role isEqual:@"textBubbleSurface"] && imageView.image && !CGRectIsEmpty(imageView.bounds)) {
            UIImage *old=imageView.image, *applied=[UIImage new];
            objc_setAssociatedObject(target,&bubbleImageKey,@{@"old":old,@"applied":applied},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            imageView.image=applied;
        }
    }
}
static void Search(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))searchLayout)(v,s); WUStyleSurface(v,@"searchSurface",14); }
static id CheckedObjectGetter(id object,NSString *name);
static BOOL IsTextMessageReply(UIView *v) {
    Class cls=NSClassFromString(@"TextMessageCellView");
    if(!cls || ![cls isSubclassOfClass:UIView.class]) return NO;
    for(UIView *parent=v.superview;parent;parent=parent.superview) {
        if([parent isKindOfClass:cls]) return CheckedObjectGetter(parent,@"msgReplyView")==v || CheckedObjectGetter(parent,@"getMsgReplyView")==v;
    }
    return NO;
}
static void Refer(UIView *v,SEL s) {
    RestoreRefer(v); ((void(*)(id,SEL))referLayout)(v,s);
    // The public MMInputMsgReferView header exposes its visible container.
    // Fall back to the legacy root if the getter or ownership is not verifiable.
    NSString *role=IsTextMessageReply(v) && WUEnabled(@"referMessageSurface") ? @"referMessageSurface" : @"referSurface";
    id container=CheckedObjectGetter(v,@"containerView");
    UIView *target=[container isKindOfClass:UIView.class] && container!=v && [container isDescendantOfView:v] ? container : v;
    WUStyleSurface(target,role,12);
    if(WUEnabled(role)) { objc_setAssociatedObject(v,&referTargetKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [styled addObject:v]; }
}
static void Plus(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))plusLayout)(v,s); WUStyleSurface(v,@"plusSurface",18); }
static void Toast(UIView *v,SEL s) { RestoreHostPopup(v); Restore(v); ((void(*)(id,SEL))toastLayout)(v,s); WUStyleSurface(v,@"toastSurface",16); RefreshHostPopup(v); }
static void RestoreChildren(UIView *v) { for(UIView *c in objc_getAssociatedObject(v,&childrenKey)) Restore(c); objc_setAssociatedObject(v,&childrenKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void TimeLabels(UIView *v,NSMutableArray *out,NSUInteger depth) { if(depth>4||out.count>=12) return; if([v isKindOfClass:UILabel.class]) { WUStyleSurface(v,@"timeSurface",6); [out addObject:v]; return; } for(UIView *c in v.subviews) TimeLabels(c,out,depth+1); }
static void Time(UIView *v,SEL s) { RestoreChildren(v); ((void(*)(id,SEL))timeLayout)(v,s); if(!WUEnabled(@"timeSurface")) return; NSMutableArray *a=[NSMutableArray array]; TimeLabels(v,a,0); objc_setAssociatedObject(v,&childrenKey,a,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void Swipe(UIView *v,SEL s) {
    RestoreChildren(v); ((void(*)(id,SEL))swipeLayout)(v,s); if(!WUEnabled(@"swipeSurface")) return;
    Class base=NSClassFromString(@"MMBaseMultiMenuTableViewCell"); Ivar ivar=base?class_getInstanceVariable(base,"_menuContentView"):NULL;
    if(!base||![v isKindOfClass:base]||!ivar||ivar_getTypeEncoding(ivar)[0]!='@') return;
    id menu=object_getIvar(v,ivar); if(![menu isKindOfClass:UIView.class]||![menu isDescendantOfView:v]) return;
    WUStyleSurface(menu,@"swipeSurface",14); objc_setAssociatedObject(v,&childrenKey,@[menu],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// 8.0.55 public headers only; all selectors and ownership are revalidated at runtime.
static IMP chatToolLayout,chatToolWindow;
static char chatButtonsKey;
static NSHashTable<UIView *> *chatTools;
static NSMutableSet<NSString *> *chatButtonRoles;
BOOL WUChatButtonSurfaceAvailable(NSString *role) { return [chatButtonRoles containsObject:role]; }
static void RestoreChatButtons(UIView *tool) {
    for(UIView *button in objc_getAssociatedObject(tool,&chatButtonsKey)) WURestoreConfiguredSurface(button);
    objc_setAssociatedObject(tool,&chatButtonsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static id CheckedObjectGetter(id object,NSString *name) {
    SEL sel=NSSelectorFromString(name); Method method=class_getInstanceMethod(object_getClass(object),sel);
    if(!WUMatches(method,@encode(id),@[])) return nil;
    @try { return ((id(*)(id,SEL))objc_msgSend)(object,sel); } @catch(NSException *e) { return nil; }
}
static void RefreshChatButtons(UIView *tool) {
    RestoreChatButtons(tool);
    if(!tool.window) return;
    Class chatClass=NSClassFromString(@"BaseMsgContentViewController");
    UIViewController *owner=nil;
    for(UIResponder *r=tool.nextResponder;r;r=r.nextResponder) if(chatClass && [r isKindOfClass:chatClass] && [r isKindOfClass:UIViewController.class]) { owner=(id)r; break; }
    if(!owner || !owner.viewIfLoaded || ![tool isDescendantOfView:owner.viewIfLoaded]) return;
    if(CheckedObjectGetter(owner,@"toolView")!=tool && CheckedObjectGetter(owner,@"getInputToolView")!=tool) return;
    id send=CheckedObjectGetter(tool,@"sendButton"), attachment=CheckedObjectGetter(tool,@"attachmentButton");
    Class mmButton=NSClassFromString(@"MMUIButton");
    NSMutableArray *buttons=[NSMutableArray array];
    if([send isKindOfClass:UIButton.class] && send!=tool && [send isDescendantOfView:tool]) {
        [chatButtonRoles addObject:@"chatSendSurface"]; WUApplyConfiguredSurface(send,@"chatSendSurface",8,YES); [buttons addObject:send];
    }
    if(mmButton && [mmButton isSubclassOfClass:UIButton.class] && [attachment isKindOfClass:mmButton] && attachment!=tool && attachment!=send && [attachment isDescendantOfView:tool]) {
        [chatButtonRoles addObject:@"chatAttachmentSurface"]; WUApplyConfiguredSurface(attachment,@"chatAttachmentSurface",8,YES); [buttons addObject:attachment];
    }
    objc_setAssociatedObject(tool,&chatButtonsKey,buttons,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void ChatToolLayout(UIView *tool,SEL sel) {
    RestoreChatButtons(tool); ((void(*)(id,SEL))chatToolLayout)(tool,sel);
    [chatTools addObject:tool]; RefreshChatButtons(tool);
}
static void ChatToolWindow(UIView *tool,SEL sel) {
    RestoreChatButtons(tool); ((void(*)(id,SEL))chatToolWindow)(tool,sel);
    [chatTools addObject:tool]; if(tool.window) [tool setNeedsLayout];
}
// Scope the preview toolbar to a verified text-message delegate and owned descendant.
static IMP textPreviewLayout,textPreviewDisappear;
static char textPreviewTargetKey;
static NSHashTable<UIViewController *> *textPreviews;
static BOOL textPreviewAvailable;
BOOL WUTextPreviewSurfaceAvailable(void) { return textPreviewAvailable; }
static void RestoreTextPreview(UIViewController *controller) {
    UIView *target=objc_getAssociatedObject(controller,&textPreviewTargetKey);
    if(target) WURestoreConfiguredSurface(target);
    objc_setAssociatedObject(controller,&textPreviewTargetKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void TextPreviewLayout(UIViewController *controller,SEL sel) {
    RestoreTextPreview(controller); ((void(*)(id,SEL))textPreviewLayout)(controller,sel);
    [textPreviews addObject:controller];
    if(!controller.viewIfLoaded.window) return;
    Class cellClass=NSClassFromString(@"TextMessageCellView"), toolbarClass=NSClassFromString(@"MMTextFloatBottomToolView");
    id delegate=CheckedObjectGetter(controller,@"m_delegate");
    Class ownerClass=NSClassFromString(@"TextFloatViewController");
    Ivar ivar=ownerClass?class_getInstanceVariable(ownerClass,"m_bottomToolView"):NULL;
    if(!cellClass || ![cellClass isSubclassOfClass:UIView.class] || ![delegate isKindOfClass:cellClass] ||
       ![(UIView *)delegate window] || !toolbarClass || ![toolbarClass isSubclassOfClass:UIView.class] ||
       !ivar || ivar_getTypeEncoding(ivar)[0]!='@') return;
    id target=object_getIvar(controller,ivar);
    if(![target isKindOfClass:toolbarClass] || target==controller.viewIfLoaded || ![target isDescendantOfView:controller.viewIfLoaded]) return;
    textPreviewAvailable=YES;
    if(!WUEnabled(@"textPreviewSurface")) return;
    WUApplyConfiguredSurface(target,@"textPreviewSurface",14,YES);
    objc_setAssociatedObject(controller,&textPreviewTargetKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void TextPreviewDisappear(UIViewController *controller,SEL sel,BOOL animated) {
    RestoreTextPreview(controller); ((void(*)(id,SEL,BOOL))textPreviewDisappear)(controller,sel,animated);
}
// WeToast/MMToastView 8.0.54 headers: only the owned backgroundView of a plain toast.
// MMTipsViewController also exposes wcpay entry points: do not hook that shared container.
static char hostPopupTargetKey;
static NSHashTable<UIView *> *hostPopups;
static BOOL hostPopupAvailable;
BOOL WUHostPopupSurfaceAvailable(void) { return hostPopupAvailable; }
static void RestoreHostPopup(UIView *view) {
    UIView *target=objc_getAssociatedObject(view,&hostPopupTargetKey);
    if(target) WURestoreConfiguredSurface(target);
    objc_setAssociatedObject(view,&hostPopupTargetKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL CheckedFalseGetter(id object,NSString *name) {
    SEL sel=NSSelectorFromString(name);
    if(!WUMatches(class_getInstanceMethod(object_getClass(object),sel),@encode(BOOL),@[])) return NO;
    @try { return !((BOOL(*)(id,SEL))objc_msgSend)(object,sel); } @catch(NSException *e) { return NO; }
}
static void RefreshHostPopup(UIView *view) {
    [hostPopups addObject:view];
    if(!view.window || object_getClass(view)!=NSClassFromString(@"MMToastView")) return;
    Class toastClass=NSClassFromString(@"WeToast");
    if(!toastClass || ![toastClass isSubclassOfClass:UIViewController.class]) return;
    UIViewController *owner=nil;
    for(UIResponder *r=view.nextResponder;r;r=r.nextResponder) {
        if(object_getClass(r)==toastClass) { owner=(id)r; break; }
        if([r isKindOfClass:UIViewController.class]) return;
    }
    if(!owner || CheckedObjectGetter(owner,@"toastView")!=view ||
       !CheckedFalseGetter(owner,@"blockUserInteraction") || !CheckedFalseGetter(owner,@"loadingStyle")) return;
    // Positive context allowlist, not a payment-class substring blacklist.
    id context=CheckedObjectGetter(owner,@"topViewControllerInMainWindow");
    if(![context isKindOfClass:UIViewController.class] || context==owner) return;
    Class chatClass=NSClassFromString(@"BaseMsgContentViewController");
    if(!(chatClass && [context isKindOfClass:chatClass]) &&
       object_getClass(context)!=NSClassFromString(@"NewMainFrameViewController")) return;
    if(![(UIViewController *)context viewIfLoaded].window || [(UIViewController *)context presentedViewController]) return;
    // Custom content/loading/icon variants are deliberately outside this text-toast role.
    if(CheckedObjectGetter(view,@"customView") || CheckedObjectGetter(view,@"iconImage")) return;
    id svg=CheckedObjectGetter(view,@"svgIconName");
    if(svg && (![svg isKindOfClass:NSString.class] || [svg length])) return;
    id text=CheckedObjectGetter(view,@"text");
    if(![text isKindOfClass:NSString.class] || ![text length]) return;
    id target=CheckedObjectGetter(view,@"backgroundView");
    if(![target isKindOfClass:UIView.class] || target==view || ![target isDescendantOfView:view] ||
       CGRectIsEmpty([(UIView *)target bounds])) return;
    hostPopupAvailable=YES;
    if(!WUEnabled(@"hostPopupSurface")) return;
    WUApplyConfiguredSurface(target,@"hostPopupSurface",16,YES);
    objc_setAssociatedObject(view,&hostPopupTargetKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// The notify view's documented contentView is the banner, not a system notification.
static IMP quickReplyLayout,quickReplyWindow;
static char quickReplyTargetKey;
static NSHashTable<UIView *> *quickReplies;
static BOOL quickReplyAvailable;
BOOL WUQuickReplySurfaceAvailable(void) { return quickReplyAvailable; }
static void RestoreQuickReply(UIView *view) {
    UIView *target=objc_getAssociatedObject(view,&quickReplyTargetKey);
    if(target) WURestoreConfiguredSurface(target);
    objc_setAssociatedObject(view,&quickReplyTargetKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void QuickReplyLayout(UIView *view,SEL sel) {
    RestoreQuickReply(view); ((void(*)(id,SEL))quickReplyLayout)(view,sel);
    [quickReplies addObject:view];
    if(!view.window) return;
    id target=CheckedObjectGetter(view,@"contentView");
    if(![target isKindOfClass:UIView.class] || target==view || ![target isDescendantOfView:view]) return;
    quickReplyAvailable=YES;
    if(!WUEnabled(@"quickReplySurface")) return;
    WUApplyConfiguredSurface(target,@"quickReplySurface",16,YES);
    objc_setAssociatedObject(view,&quickReplyTargetKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void QuickReplyWindow(UIView *view,SEL sel) {
    RestoreQuickReply(view); ((void(*)(id,SEL))quickReplyWindow)(view,sel);
    [quickReplies addObject:view]; if(view.window) [view setNeedsLayout];
}
void WUInstallSurfaces(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{ styled=NSHashTable.weakObjectsHashTable; cardRoles=[NSMutableSet set]; [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ for(UIView *v in styled) { Restore(v); [v setNeedsLayout]; } [styled removeAllObjects]; }]; });
    static dispatch_once_t popupOnce; dispatch_once(&popupOnce, ^{
        hostPopups=NSHashTable.weakObjectsHashTable;
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            for(UIView *view in hostPopups.allObjects) { RestoreHostPopup(view); [view setNeedsLayout]; }
        }];
    });
    static dispatch_once_t chatOnce; dispatch_once(&chatOnce, ^{
        chatTools=NSHashTable.weakObjectsHashTable; chatButtonRoles=[NSMutableSet set];
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            for(UIView *tool in chatTools.allObjects) { RestoreChatButtons(tool); [tool setNeedsLayout]; }
        }];
    });
    static dispatch_once_t previewOnce; dispatch_once(&previewOnce, ^{
        textPreviews=NSHashTable.weakObjectsHashTable;
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            for(UIViewController *controller in textPreviews.allObjects) { RestoreTextPreview(controller); [controller.viewIfLoaded setNeedsLayout]; }
        }];
    });
    static dispatch_once_t quickOnce; dispatch_once(&quickOnce, ^{
        quickReplies=NSHashTable.weakObjectsHashTable;
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            for(UIView *view in quickReplies.allObjects) { RestoreQuickReply(view); [view setNeedsLayout]; }
        }];
    });
    Class quick=NSClassFromString(@"QuickReplyMsgNotifyView");
    if(quick && [quick isSubclassOfClass:UIView.class] && WUHook(@"QuickReplyMsgNotifyView",@"didMoveToWindow",NO,"v",@[],(IMP)QuickReplyWindow,&quickReplyWindow))
        WUHook(@"QuickReplyMsgNotifyView",@"layoutSubviews",NO,"v",@[],(IMP)QuickReplyLayout,&quickReplyLayout);
    Class preview=NSClassFromString(@"TextFloatViewController");
    if(preview && [preview isSubclassOfClass:UIViewController.class] && WUHook(@"TextFloatViewController",@"viewDidDisappear:",NO,"v",@[@"B"],(IMP)TextPreviewDisappear,&textPreviewDisappear))
        WUHook(@"TextFloatViewController",@"viewDidLayoutSubviews",NO,"v",@[],(IMP)TextPreviewLayout,&textPreviewLayout);
    Class toolClass=NSClassFromString(@"MMInputToolView");
    if(toolClass && [toolClass isSubclassOfClass:UIView.class] && WUHook(@"MMInputToolView",@"didMoveToWindow",NO,"v",@[],(IMP)ChatToolWindow,&chatToolWindow))
        WUHook(@"MMInputToolView",@"layoutSubviews",NO,"v",@[],(IMP)ChatToolLayout,&chatToolLayout);
    WUHook(@"ChatTimeCellView",@"layoutSubviews",NO,"v",@[],(IMP)Time,&timeLayout);
    Class base=NSClassFromString(@"MMBaseMultiMenuTableViewCell"); Ivar ivar=base?class_getInstanceVariable(base,"_menuContentView"):NULL;
    if(ivar && ivar_getTypeEncoding(ivar)[0]=='@') WUHook(@"NewMainFrameCell",@"layoutSubviews",NO,"v",@[],(IMP)Swipe,&swipeLayout);
    WUHook(@"WCSearchBar",@"layoutSubviews",NO,"v",@[],(IMP)Search,&searchLayout);
    Class refer=NSClassFromString(@"MMInputMsgReferView");
    if(refer && [refer isSubclassOfClass:UIView.class] && WUHook(@"MMInputMsgReferView",@"layoutSubviews",NO,"v",@[],(IMP)Refer,&referLayout))
        WUHook(@"MMInputMsgReferView",@"didMoveToWindow",NO,"v",@[],(IMP)ReferWindow,&referWindow);
    WUHook(@"MainFrameActionFloatView",@"layoutSubviews",NO,"v",@[],(IMP)Plus,&plusLayout);
    Class toast=NSClassFromString(@"MMToastView");
    if(toast && [toast isSubclassOfClass:UIView.class] && WUHook(@"MMToastView",@"didMoveToWindow",NO,"v",@[],(IMP)ToastWindow,&toastWindow))
        WUHook(@"MMToastView",@"layoutSubviews",NO,"v",@[],(IMP)Toast,&toastLayout);
}
