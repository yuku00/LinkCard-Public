#import "WU.h"
#import <QuartzCore/QuartzCore.h>
static IMP inputLayout, noticeLayout, homeLayout;
static NSHashTable<UIView *> *decorated;
static NSHashTable<UITableView *> *tables;
static char layerKey, separatorKey;
static void Remove(UIView *v) { CALayer *l=objc_getAssociatedObject(v,&layerKey); [l removeFromSuperlayer]; objc_setAssociatedObject(v,&layerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void Decorate(UIView *v,NSString *key) {
    Remove(v);
    if(!WUEnabled(key) || !v.window || CGRectIsEmpty(v.bounds)) return;
    Class chat=NSClassFromString(@"BaseMsgContentViewController"); BOOL inChat=NO;
    for(UIResponder *r=v; r; r=r.nextResponder) if(chat && [r isKindOfClass:chat]) { inChat=YES; break; }
    if(!inChat) return;
    CAShapeLayer *l=[CAShapeLayer layer]; l.name=@"org.wechatunified.border";
    l.frame=v.bounds; l.path=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(v.bounds,1,1) cornerRadius:10].CGPath;
    l.fillColor=UIColor.clearColor.CGColor;
    l.strokeColor=[UIColor.systemTealColor resolvedColorWithTraitCollection:v.traitCollection].CGColor; l.lineWidth=1;
    [v.layer addSublayer:l]; objc_setAssociatedObject(v,&layerKey,l,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [decorated addObject:v];
}
static void Input(UIView *v,SEL s) { Remove(v); ((void(*)(id,SEL))inputLayout)(v,s); Decorate(v,@"inputBorder"); }
static void Notice(UIView *v,SEL s) { Remove(v); ((void(*)(id,SEL))noticeLayout)(v,s); Decorate(v,@"noticeBorder"); }
static void RestoreTables(void) {
    for(UITableView *t in tables) {
        NSNumber *baseline=objc_getAssociatedObject(t,&separatorKey);
        if(baseline && t.separatorStyle==UITableViewCellSeparatorStyleNone) t.separatorStyle=baseline.integerValue;
        objc_setAssociatedObject(t,&separatorKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [tables removeAllObjects];
}
static void Walk(UIView *v) {
    if([v isKindOfClass:UITableView.class]) {
        UITableView *t=(UITableView *)v;
        if(!objc_getAssociatedObject(t,&separatorKey)) objc_setAssociatedObject(t,&separatorKey,@(t.separatorStyle),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        t.separatorStyle=UITableViewCellSeparatorStyleNone; [tables addObject:t]; return;
    }
    for(UIView *c in v.subviews) Walk(c);
}
static void Home(UIViewController *v,SEL s) {
    RestoreTables(); ((void(*)(id,SEL))homeLayout)(v,s);
    if(WUEnabled(@"separators")) Walk(v.view);
}
void WUInstallAppearance(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{
        decorated=NSHashTable.weakObjectsHashTable; tables=NSHashTable.weakObjectsHashTable;
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            RestoreTables(); for(UIView *v in decorated) { Remove(v); [v setNeedsLayout]; }
        }];
    });
    WUHook(@"MMGrowTextView",@"layoutSubviews",NO,"v",@[],(IMP)Input,&inputLayout);
    WUHook(@"SystemMessageCellView",@"layoutSubviews",NO,"v",@[],(IMP)Notice,&noticeLayout);
    WUHook(@"NewMainFrameViewController",@"viewDidLayoutSubviews",NO,"v",@[],(IMP)Home,&homeLayout);
}
