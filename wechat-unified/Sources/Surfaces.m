#import "WU.h"
#import <QuartzCore/QuartzCore.h>
static NSHashTable<UIView *> *styled;
static char baselineKey,childrenKey;
static IMP searchLayout,referLayout,plusLayout,toastLayout,timeLayout,swipeLayout;
static void Restore(UIView *v) {
    NSDictionary *b=objc_getAssociatedObject(v,&baselineKey); if(!b) return;
    v.layer.cornerRadius=[b[@"radius"] doubleValue]; v.clipsToBounds=[b[@"clip"] boolValue]; v.backgroundColor=b[@"bg"]==NSNull.null?nil:b[@"bg"];
    objc_setAssociatedObject(v,&baselineKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void Style(UIView *v,NSString *key,CGFloat radius) {
    if(!WUEnabled(key)||!v.window||CGRectIsEmpty(v.bounds)) return;
    objc_setAssociatedObject(v,&baselineKey,@{@"radius":@(v.layer.cornerRadius),@"clip":@(v.clipsToBounds),@"bg":v.backgroundColor?:NSNull.null},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    v.layer.cornerRadius=MIN(radius,MIN(v.bounds.size.width,v.bounds.size.height)/2); v.clipsToBounds=YES;
    v.backgroundColor=[UIColor.secondarySystemGroupedBackgroundColor resolvedColorWithTraitCollection:v.traitCollection]; [styled addObject:v];
}
static void Search(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))searchLayout)(v,s); Style(v,@"searchSurface",14); }
static void Refer(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))referLayout)(v,s); Style(v,@"referSurface",12); }
static void Plus(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))plusLayout)(v,s); Style(v,@"plusSurface",18); }
static void Toast(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))toastLayout)(v,s); Style(v,@"toastSurface",16); }
static void RestoreChildren(UIView *v) { for(UIView *c in objc_getAssociatedObject(v,&childrenKey)) Restore(c); objc_setAssociatedObject(v,&childrenKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void TimeLabels(UIView *v,NSMutableArray *out,NSUInteger depth) { if(depth>4||out.count>=12) return; if([v isKindOfClass:UILabel.class]) { Style(v,@"timeSurface",6); [out addObject:v]; return; } for(UIView *c in v.subviews) TimeLabels(c,out,depth+1); }
static void Time(UIView *v,SEL s) { RestoreChildren(v); ((void(*)(id,SEL))timeLayout)(v,s); if(!WUEnabled(@"timeSurface")) return; NSMutableArray *a=[NSMutableArray array]; TimeLabels(v,a,0); objc_setAssociatedObject(v,&childrenKey,a,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void Swipe(UIView *v,SEL s) {
    RestoreChildren(v); ((void(*)(id,SEL))swipeLayout)(v,s); if(!WUEnabled(@"swipeSurface")) return;
    Class base=NSClassFromString(@"MMBaseMultiMenuTableViewCell"); Ivar ivar=base?class_getInstanceVariable(base,"_menuContentView"):NULL;
    if(!base||![v isKindOfClass:base]||!ivar||ivar_getTypeEncoding(ivar)[0]!='@') return;
    id menu=object_getIvar(v,ivar); if(![menu isKindOfClass:UIView.class]||![menu isDescendantOfView:v]) return;
    Style(menu,@"swipeSurface",14); objc_setAssociatedObject(v,&childrenKey,@[menu],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void WUInstallSurfaces(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{ styled=NSHashTable.weakObjectsHashTable; [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ for(UIView *v in styled) { Restore(v); [v setNeedsLayout]; } [styled removeAllObjects]; }]; });
    WUHook(@"ChatTimeCellView",@"layoutSubviews",NO,"v",@[],(IMP)Time,&timeLayout);
    Class base=NSClassFromString(@"MMBaseMultiMenuTableViewCell"); Ivar ivar=base?class_getInstanceVariable(base,"_menuContentView"):NULL;
    if(ivar && ivar_getTypeEncoding(ivar)[0]=='@') WUHook(@"NewMainFrameCell",@"layoutSubviews",NO,"v",@[],(IMP)Swipe,&swipeLayout);
    WUHook(@"WCSearchBar",@"layoutSubviews",NO,"v",@[],(IMP)Search,&searchLayout);
    WUHook(@"MMInputMsgReferView",@"layoutSubviews",NO,"v",@[],(IMP)Refer,&referLayout);
    WUHook(@"MainFrameActionFloatView",@"layoutSubviews",NO,"v",@[],(IMP)Plus,&plusLayout);
    WUHook(@"MMToastView",@"layoutSubviews",NO,"v",@[],(IMP)Toast,&toastLayout);
}
