#import "WU.h"
#import "InteractionLogic.h"
#import <QuartzCore/QuartzCore.h>
static NSHashTable<UIView *> *styled;
static char childrenKey,cardKey;
static NSMutableSet<NSString *> *cardRoles;
static void Restore(UIView *v);
void WURestoreMessageSurface(UIView *cell) {
    UIView *target=objc_getAssociatedObject(cell,&cardKey);
    if(target) Restore(target);
    objc_setAssociatedObject(cell,&cardKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static IMP searchLayout,referLayout,plusLayout,toastLayout,timeLayout,swipeLayout;
static void Restore(UIView *v) { WURestoreConfiguredSurface(v); }
static void WUStyleSurface(UIView *v,NSString *key,CGFloat radius) {
    WUApplyConfiguredSurface(v,key,radius,YES); if(WUEnabled(key)) [styled addObject:v];
}
BOOL WUCardSurfaceAvailable(NSString *key) { return [cardRoles containsObject:key]; }
void WURefreshMessageSurface(UIView *cell,NSString *role) {
    WURestoreMessageSurface(cell);
    if(![@[@"fileSurface",@"emoticonSurface"] containsObject:role] || !cell.window) return;
    // m_bgImageView is the existing evidence-backed CommonMessageCellView background role.
    id target=nil; @try { target=[cell valueForKey:@"m_bgImageView"]; } @catch(NSException *e) { return; }
    if(![target isKindOfClass:UIImageView.class] || target==cell || ![target isDescendantOfView:cell]) return;
    [cardRoles addObject:role];
    WUStyleSurface(target,role,14);
    if(WUEnabled(role)) objc_setAssociatedObject(cell,&cardKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void Search(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))searchLayout)(v,s); WUStyleSurface(v,@"searchSurface",14); }
static void Refer(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))referLayout)(v,s); WUStyleSurface(v,@"referSurface",12); }
static void Plus(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))plusLayout)(v,s); WUStyleSurface(v,@"plusSurface",18); }
static void Toast(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))toastLayout)(v,s); WUStyleSurface(v,@"toastSurface",16); }
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
void WUInstallSurfaces(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{ styled=NSHashTable.weakObjectsHashTable; cardRoles=[NSMutableSet set]; [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ for(UIView *v in styled) { Restore(v); [v setNeedsLayout]; } [styled removeAllObjects]; }]; });
    WUHook(@"ChatTimeCellView",@"layoutSubviews",NO,"v",@[],(IMP)Time,&timeLayout);
    Class base=NSClassFromString(@"MMBaseMultiMenuTableViewCell"); Ivar ivar=base?class_getInstanceVariable(base,"_menuContentView"):NULL;
    if(ivar && ivar_getTypeEncoding(ivar)[0]=='@') WUHook(@"NewMainFrameCell",@"layoutSubviews",NO,"v",@[],(IMP)Swipe,&swipeLayout);
    WUHook(@"WCSearchBar",@"layoutSubviews",NO,"v",@[],(IMP)Search,&searchLayout);
    WUHook(@"MMInputMsgReferView",@"layoutSubviews",NO,"v",@[],(IMP)Refer,&referLayout);
    WUHook(@"MainFrameActionFloatView",@"layoutSubviews",NO,"v",@[],(IMP)Plus,&plusLayout);
    WUHook(@"MMToastView",@"layoutSubviews",NO,"v",@[],(IMP)Toast,&toastLayout);
}
