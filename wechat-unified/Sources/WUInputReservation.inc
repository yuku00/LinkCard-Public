// 8.0.79 declares -[MMInputToolView getGroupUndoneBarHeight] as double.
// The toolbar is owned by the host panel; only the returned height is extended.
#import <objc/runtime.h>
#import "WUInputHostGeometry.h"

static const CGFloat WUInputExtra=35.0;
static char WUInputStateKey, WUInputToolTrackKey;
static IMP WUInputHeightOriginal;

@interface WUInputReservation : NSObject
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,weak) UIView *tool;
@property(nonatomic,weak) UIView *panel;
@property(nonatomic,strong) WUInputToolbar *toolbar;
@property(nonatomic,strong) NSArray *entries;
@property(nonatomic,copy) BOOL (^current)(void);
@property(nonatomic) BOOL reserved;
@end
@implementation WUInputReservation @end

static void WUInputRemove(UIViewController *owner) {
    if(!NSThread.isMainThread || !owner) return;
    WUInputReservation *s=objc_getAssociatedObject(owner,&WUInputStateKey);
    if(!s) return;
    objc_setAssociatedObject(owner,&WUInputStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *tool=s.tool;
    if(objc_getAssociatedObject(tool,&WUInputToolTrackKey)==s)
        objc_setAssociatedObject(tool,&WUInputToolTrackKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    s.toolbar.current=^BOOL{ return NO; };
    [s.toolbar removeFromSuperview];
    [tool setNeedsLayout];
}
static BOOL WUInputValid(WUInputReservation *s) {
    return s && s.owner && s.tool && s.panel && s.toolbar.superview==s.panel &&
        s.owner.viewIfLoaded.window && s.tool.window==s.owner.viewIfLoaded.window &&
        [s.panel isDescendantOfView:s.tool] && (!s.current || s.current());
}
static void WUInputSyncChecked(UIViewController *owner, NSArray<NSDictionary *> *entries, BOOL (^current)(void)) {
    if(!NSThread.isMainThread || !owner) return;
    UIView *tool=WUInputToolForOwner(owner);
    id panel=Obj(tool,@"toolPanelView");
    WUInputReservation *s=objc_getAssociatedObject(owner,&WUInputStateKey);
    if(!WUInputHeightOriginal || !owner.viewIfLoaded.window || !entries.count || (current && !current()) || !tool) {
        WUInputRemove(owner); return;
    }
    BOOL panelValid=[panel isKindOfClass:UIView.class] && panel!=tool && [panel isDescendantOfView:tool];
    if(s && (s.tool!=tool || (s.panel && s.panel!=panel) || s.entries!=entries)) { WUInputRemove(owner); s=nil; }
    if(!s) {
        s=[WUInputReservation new]; s.owner=owner; s.tool=tool; s.entries=entries; s.current=current;
        objc_setAssociatedObject(owner,&WUInputStateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(tool,&WUInputToolTrackKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The host may create the panel after the controller's first layout.
    if(panelValid && !s.toolbar) {
        s.panel=panel; s.toolbar=[[WUInputToolbar alloc] initWithEntries:entries]; s.toolbar.current=current; s.toolbar.hidden=YES;
        [panel addSubview:s.toolbar];
        [tool setNeedsLayout];
    }
}
static __attribute__((unused)) void WUInputSync(UIViewController *owner, NSArray<NSDictionary *> *entries) { WUInputSyncChecked(owner,entries,nil); }

static double WUInputHeight(id tool, SEL sel) {
    double original=((double(*)(id,SEL))WUInputHeightOriginal)(tool,sel);
    if(!NSThread.isMainThread || object_getClass(tool)!=NSClassFromString(@"MMInputToolView")) return original;
    WUInputReservation *s=objc_getAssociatedObject(tool,&WUInputToolTrackKey);
    @try {
        // The disassembly describes a translation offset, but not enough to reproduce it safely.
        // Hide while translation is visible rather than overlapping that host control.
        BOOL getter=Has(tool,@"transToolView","@",@[]);
        id translation=getter?Obj(tool,@"transToolView"):nil;
        BOOL clear=getter && (!translation || ([translation isKindOfClass:UIView.class] && ([(UIView *)translation isHidden] || [(UIView *)translation alpha]<=0.01)));
        CGFloat width=CGRectGetWidth(s.panel.bounds);
        BOOL eligible=WUInputValid(s) && clear && isfinite(original) && isfinite(width) && width>=44;
        s.reserved=eligible;
        if(eligible) s.toolbar.frame=CGRectMake(0,WUInputHostY(original),width,WUInputExtra);
        else s.toolbar.hidden=YES;
        return WUInputHostHeight(original,eligible);
    } @catch(__unused NSException *e) { s.reserved=NO; s.toolbar.hidden=YES; return original; }
}

// After the host layout, reveal only if the reserved strip is inside its panel
// and does not intersect the real input bar. Never move the host's views.
void WUInputToolDidLayout(UIView *tool) {
    if(!NSThread.isMainThread || !tool) return;
    WUInputReservation *s=objc_getAssociatedObject(tool,&WUInputToolTrackKey);
    if(!s) return;
    @try {
        if(!s.toolbar) { WUInputSyncChecked(s.owner,s.entries,s.current); return; }
        if(!WUInputValid(s)) {
            UIViewController *owner=s.owner; NSArray *entries=s.entries; BOOL (^current)(void)=s.current;
            WUInputRemove(owner); WUInputSyncChecked(owner,entries,current); return;
        }
        UIView *bar=WUInputBarForOwner(s.owner), *root=s.owner.viewIfLoaded;
        CGRect strip=[s.toolbar convertRect:s.toolbar.bounds toView:root];
        CGRect input=[bar convertRect:bar.bounds toView:root];
        BOOL safe=s.reserved && bar && bar.window==root.window && !bar.hidden && !s.panel.hidden &&
            CGRectContainsRect(s.panel.bounds,s.toolbar.frame) && CGRectContainsRect(root.bounds,strip) &&
            WUInputHostDisjoint(strip.origin.x,strip.origin.y,strip.size.width,strip.size.height,input.origin.x,input.origin.y,input.size.width,input.size.height);
        s.toolbar.hidden=!safe;
        if(safe && s.panel.subviews.lastObject!=s.toolbar) [s.panel bringSubviewToFront:s.toolbar];
    } @catch(__unused NSException *e) { s.toolbar.hidden=YES; }
}
