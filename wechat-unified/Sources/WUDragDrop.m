// Based on Netskao's WeChatDragDropImages (MIT); see Vendor/WeChatDragDropImages-LICENSE.
// The confirmation delegate and context checks are specific to this integration.
#import "WUDragDrop.h"
#import "WU.h"

static BOOL Match(id object, NSString *name, const char *result, NSArray<NSString *> *args) {
    return object && WUMatches(class_getInstanceMethod(object_getClass(object),NSSelectorFromString(name)),result,args);
}
static id Object(id object, NSString *name) {
    return Match(object,name,"@",@[])?((id(*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(name)):nil;
}
static BOOL SheetABI(Class c) {
    if(!c || ![c isSubclassOfClass:UIView.class]) return NO;
    return WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"setDelegate:")),"v",@[@"@"]) &&
        WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"setTitle:")),"v",@[@"@"]) &&
        WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"setArrMsgs:")),"v",@[@"@"]) &&
        WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"setBShowTextView:")),"v",@[@"B"]) &&
        WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"showFromViewController:animated:complete:")),"v",@[@"@",@"B",@"@?"]) &&
        WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"dismissWithAnimated:")),"v",@[@"B"]);
}
BOOL WUDragDropAvailable(void) {
    id version=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if(![version isKindOfClass:NSString.class] || ![version isEqualToString:@"8.0.79"]) return NO;
    Class c=NSClassFromString(@"BaseMsgContentViewController");
    return WUDragDropLifecycleAvailable() && c && [c isSubclassOfClass:UIViewController.class] && SheetABI(NSClassFromString(@"SharePreConfirmSheetView")) &&
        WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"m_delegate")),"@",@[]) &&
        WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"OnSharePreConfirmSheetViewSend:")),"v",@[@"@"]) &&
        WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"viewDidAppear:")),"v",@[@"B"]) &&
        WUMatches(class_getInstanceMethod(c,NSSelectorFromString(@"viewDidDisappear:")),"v",@[@"B"]);
}

@protocol SharePreConfirmSheetViewDelegate <NSObject>
@optional
- (void)OnSharePreConfirmSheetViewSend:(id)sheet;
- (void)OnSharePreConfirmSheetViewCancel:(id)sheet;
- (void)OnSharePreConfirmSheetViewClose:(id)sheet;
@end
@interface WUDragDrop : NSObject <UIDropInteractionDelegate, SharePreConfirmSheetViewDelegate>
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,weak) id hostDelegate;
@property(nonatomic,strong) UIDropInteraction *interaction;
@property(nonatomic,strong) id sheet;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) NSProgress *progress;
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSString *session;
@property(nonatomic) NSUInteger generation, epoch;
@property(nonatomic) NSTimeInterval loadDeadline;
@property(nonatomic) BOOL busy, submitted;
- (void)stop:(BOOL)dismiss;
@end
static char dragKey;

// Existing interactions on the target chain or an existing WeChat drop manager win.
static BOOL HostDropInTree(UIView *view, UIDropInteraction *own) {
    Class manager=NSClassFromString(@"MMDropManager");
    for(id<UIInteraction> interaction in view.interactions) {
        if(interaction==own || ![interaction isKindOfClass:UIDropInteraction.class]) continue;
        id delegate=((UIDropInteraction *)interaction).delegate;
        if(manager && [delegate isKindOfClass:manager]) return YES;
    }
    for(UIView *child in view.subviews) if(HostDropInTree(child,own)) return YES;
    return NO;
}
static BOOL DropOnChain(UIView *from, UIView *last, UIDropInteraction *own) {
    for(UIView *v=from;v;v=v.superview) {
        for(id<UIInteraction> interaction in v.interactions)
            if(interaction!=own && [interaction isKindOfClass:UIDropInteraction.class]) return YES;
        if(v==last) break;
    }
    return NO;
}
static BOOL HostConflict(UIViewController *owner, UIDropInteraction *own) {
    UIView *view=owner.viewIfLoaded;
    return !view || HostDropInTree(view,own) || DropOnChain(view,nil,own);
}
@implementation WUDragDrop
- (BOOL)current {
    @try {
        UIViewController *v=self.owner;
        if(!NSThread.isMainThread || !self.busy || self.submitted || !WUDragDropAvailable() || !v || !v.viewIfLoaded.window ||
           UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || !WUEnabled(@"dragImages") ||
           (v.navigationController && v.navigationController.topViewController!=v) ||
           !self.account.length || !self.session.length) return NO;
        NSString *account=WUCurrentAccount();
        return [self.account isEqual:account] && self.generation==WUContextGeneration() &&
            [self.session isEqual:WUChatSession(v)] && self.hostDelegate && self.hostDelegate==Object(v,@"m_delegate") &&
            !HostConflict(v,self.interaction);
    } @catch(__unused NSException *e) { return NO; }
}
- (void)checkContext:(NSTimer *)timer {
    if(![self current] || (self.loadDeadline && NSDate.timeIntervalSinceReferenceDate>=self.loadDeadline)) [self stop:YES];
}
- (void)changed:(NSNotification *)note {
    if(self.busy) [self stop:YES];
    if(!WUEnabled(@"dragImages") && self.interaction) { [self.owner.viewIfLoaded removeInteraction:self.interaction]; self.interaction=nil; }
}
- (void)inactive:(NSNotification *)note { if(self.busy) [self stop:YES]; }
- (void)stop:(BOOL)dismiss {
    self.epoch++; self.busy=NO; self.submitted=NO; self.loadDeadline=0;
    [self.timer invalidate]; self.timer=nil;
    [self.progress cancel]; self.progress=nil;
    id sheet=self.sheet; self.sheet=nil; self.hostDelegate=nil; self.account=nil; self.session=nil;
    if(dismiss && sheet && Match(sheet,@"dismissWithAnimated:","v",@[@"B"])) {
        @try { ((void(*)(id,SEL,BOOL))objc_msgSend)(sheet,NSSelectorFromString(@"dismissWithAnimated:"),NO); } @catch(__unused NSException *e) {}
    }
}
- (BOOL)dropInteraction:(UIDropInteraction *)interaction canHandleSession:(id<UIDropSession>)session {
    UIViewController *v=self.owner;
    if(!NSThread.isMainThread || !WUDragDropAvailable() || interaction!=self.interaction || self.busy || !WUEnabled(@"dragImages") || !v.viewIfLoaded.window ||
       UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || v.presentedViewController ||
       (v.navigationController && v.navigationController.topViewController!=v) || HostConflict(v,interaction) ||
       !session.items.count || session.items.count>9 || ![session canLoadObjectsOfClass:UIImage.class]) return NO;
    UIView *hit=[v.view hitTest:[session locationInView:v.view] withEvent:nil];
    return hit && !DropOnChain(hit,v.view,interaction);
}
- (UIDropProposal *)dropInteraction:(UIDropInteraction *)interaction sessionDidUpdate:(id<UIDropSession>)session {
    return [[UIDropProposal alloc] initWithDropOperation:[self dropInteraction:interaction canHandleSession:session]?UIDropOperationCopy:UIDropOperationForbidden];
}
- (void)dropInteraction:(UIDropInteraction *)interaction performDrop:(id<UIDropSession>)session {
    @try { [self receive:interaction session:session]; }
    @catch(__unused NSException *e) { [self stop:YES]; }
}
- (void)receive:(UIDropInteraction *)interaction session:(id<UIDropSession>)session {
    if(![self dropInteraction:interaction canHandleSession:session]) return;
    UIViewController *v=self.owner; id delegate=Object(v,@"m_delegate");
    if(!Match(delegate,@"GetMessageFromImage:","@",@[@"@"]) || !Match(v,@"OnSharePreConfirmSheetViewSend:","v",@[@"@"]) || !SheetABI(NSClassFromString(@"SharePreConfirmSheetView"))) return;
    self.account=WUCurrentAccount(); self.session=WUChatSession(v); self.generation=WUContextGeneration();
    self.hostDelegate=delegate; self.busy=YES; self.submitted=NO; NSUInteger epoch=++self.epoch, expected=session.items.count;
    if(![self current]) { [self stop:NO]; return; }
    self.loadDeadline=NSDate.timeIntervalSinceReferenceDate+30;
    self.timer=[NSTimer timerWithTimeInterval:0.25 target:self selector:@selector(checkContext:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    __weak WUDragDrop *weak=self;
    self.progress=[session loadObjectsOfClass:UIImage.class completion:^(NSArray<__kindof id<NSItemProviderReading>> *items) {
        dispatch_async(dispatch_get_main_queue(),^{
            WUDragDrop *strong=weak; if(!strong || !strong.busy || strong.epoch!=epoch) return;
            if(![strong current] || !expected || items.count!=expected) { [strong stop:NO]; return; }
            strong.loadDeadline=0; strong.progress=nil;
            @try {
                NSMutableArray *messages=[NSMutableArray array]; id host=strong.hostDelegate;
                if(!Match(host,@"GetMessageFromImage:","@",@[@"@"])) { [strong stop:NO]; return; }
                for(id image in items) {
                    if(![strong current] || ![image isKindOfClass:UIImage.class]) { [strong stop:NO]; return; }
                    id message=((id(*)(id,SEL,id))objc_msgSend)(host,NSSelectorFromString(@"GetMessageFromImage:"),image);
                    Class wrapClass=NSClassFromString(@"CMessageWrap");
                    if(!wrapClass || ![message isKindOfClass:wrapClass]) { [strong stop:NO]; return; }
                    [messages addObject:message];
                }
                if(![strong current] || !SheetABI(NSClassFromString(@"SharePreConfirmSheetView"))) { [strong stop:NO]; return; }
                id sheet=[NSClassFromString(@"SharePreConfirmSheetView") new]; if(!sheet) { [strong stop:NO]; return; }
                strong.sheet=sheet;
                ((void(*)(id,SEL,id))objc_msgSend)(sheet,NSSelectorFromString(@"setDelegate:"),strong);
                ((void(*)(id,SEL,id))objc_msgSend)(sheet,NSSelectorFromString(@"setTitle:"),@"是否发送以下图片？");
                ((void(*)(id,SEL,id))objc_msgSend)(sheet,NSSelectorFromString(@"setArrMsgs:"),messages);
                ((void(*)(id,SEL,BOOL))objc_msgSend)(sheet,NSSelectorFromString(@"setBShowTextView:"),NO);
                if(![strong current]) { [strong stop:YES]; return; }
                ((void(*)(id,SEL,id,BOOL,id))objc_msgSend)(sheet,NSSelectorFromString(@"showFromViewController:animated:complete:"),strong.owner,YES,nil);
            } @catch(__unused NSException *e) { [strong stop:YES]; }
        });
    }];
}
// Only this callback forwards to WeChat; it is invoked by its confirmation sheet.
- (void)OnSharePreConfirmSheetViewSend:(id)sheet {
    if(sheet!=self.sheet || ![self current] || !Match(self.owner,@"OnSharePreConfirmSheetViewSend:","v",@[@"@"])) { [self stop:YES]; return; }
    self.submitted=YES;
    @try { ((void(*)(id,SEL,id))objc_msgSend)(self.owner,NSSelectorFromString(@"OnSharePreConfirmSheetViewSend:"),sheet); }
    @catch(__unused NSException *e) {} // Result unknown: never retry a possible send.
    [self stop:NO];
}
- (void)OnSharePreConfirmSheetViewCancel:(id)sheet { if(sheet==self.sheet) [self stop:NO]; }
- (void)OnSharePreConfirmSheetViewClose:(id)sheet { if(sheet==self.sheet) [self stop:NO]; }
@end

void WUDragDropAppeared(UIViewController *owner) {
    if(!NSThread.isMainThread || !WUDragDropAvailable() || !owner.viewIfLoaded.window) return;
    WUDragDrop *drag=objc_getAssociatedObject(owner,&dragKey);
    if(!drag) {
        drag=[WUDragDrop new]; drag.owner=owner;
        objc_setAssociatedObject(owner,&dragKey,drag,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [NSNotificationCenter.defaultCenter addObserver:drag selector:@selector(changed:) name:WUChanged object:nil];
        [NSNotificationCenter.defaultCenter addObserver:drag selector:@selector(inactive:) name:UIApplicationWillResignActiveNotification object:nil];
    }
    if(!WUEnabled(@"dragImages") || HostConflict(owner,drag.interaction)) {
        [drag stop:YES]; if(drag.interaction) [owner.view removeInteraction:drag.interaction]; drag.interaction=nil; return;
    }
    if(!drag.interaction) { drag.interaction=[[UIDropInteraction alloc] initWithDelegate:drag]; [owner.view addInteraction:drag.interaction]; }
}
void WUDragDropDisappeared(UIViewController *owner) {
    WUDragDrop *drag=objc_getAssociatedObject(owner,&dragKey); [drag stop:YES];
    if(drag.interaction) [owner.viewIfLoaded removeInteraction:drag.interaction]; drag.interaction=nil;
}
