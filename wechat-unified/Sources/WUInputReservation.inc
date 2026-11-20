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
@property(nonatomic,copy) NSString *reason;
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
        s.reason=@"等待宿主创建工具面板或重新布局";
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
static NSString *WUInputDiagnostic(UIViewController *owner) {
    WUInputReservation *s=objc_getAssociatedObject(owner,&WUInputStateKey);
    if(!WUInputHeightOriginal) return @"未安装宿主高度挂点；输入栏工具不可用。";
    if(!s) return @"当前聊天未建立工具栏绑定；请返回聊天列表再进入。";
    if(!s.toolbar) return @"已绑定聊天，正在等待有效的宿主工具面板。";
    return [NSString stringWithFormat:@"%@。工具栏标记为%@。此状态不包含聊天、账号、工具名称或坐标，也不自动上传。", s.reason ?: @"尚未完成布局核验", s.toolbar.hidden ? @"隐藏" : @"显示"];
}

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
        if(eligible) s.reason=@"已预留，等待宿主布局后核验位置";
        else { s.toolbar.hidden=YES; s.reason=(!clear ? @"翻译栏状态不明或正在显示" : @"上下文、面板宽度或宿主高度不满足安全条件"); }
        return WUInputHostHeight(original,eligible);
    } @catch(__unused NSException *e) { s.reserved=NO; s.toolbar.hidden=YES; s.reason=@"读取宿主高度状态时异常，已安全隐藏"; return original; }
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
        if(!s.reserved || !bar || bar.window!=root.window || bar.hidden || s.panel.hidden) {
            s.toolbar.hidden=YES;
            if(s.reserved) s.reason=@"未找到可见的当前输入条或工具面板";
            return;
        }
        // Height is a size, not a panel-local y coordinate. Convert the actual
        // laid-out input bar to the same coordinates as the original host panel.
        CGRect barInPanel=[bar convertRect:bar.bounds toView:s.panel];
        s.toolbar.frame=CGRectMake(CGRectGetMinX(barInPanel),WUInputHostY(CGRectGetMinY(barInPanel)),CGRectGetWidth(barInPanel),WUInputExtra);
        CGRect strip=[s.toolbar convertRect:s.toolbar.bounds toView:root];
        CGRect input=[bar convertRect:bar.bounds toView:root];
        BOOL safe=CGRectContainsRect(s.panel.bounds,s.toolbar.frame) && CGRectContainsRect(root.bounds,strip) &&
            WUInputHostDisjoint(strip.origin.x,strip.origin.y,strip.size.width,strip.size.height,input.origin.x,input.origin.y,input.size.width,input.size.height);
        if(!safe) s.reason=@"工具栏位置不在面板内或与输入条重叠，已隐藏";
        // UIKit hit-testing also requires each ancestor to contain the point,
        // even when that ancestor does not clip its drawing.
        for(UIView *v=s.panel; safe && v; v=v.superview) {
            CGRect inView=[s.toolbar convertRect:s.toolbar.bounds toView:v];
            if(v.hidden || v.alpha<=0.01 || !v.userInteractionEnabled || !CGRectContainsRect(v.bounds,inView)) {
                safe=NO; s.reason=@"上级视图不可见、不可交互或超出点击范围";
            }
            if(v==root) break;
        }
        s.toolbar.hidden=!safe;
        if(safe) {
            s.reason=@"位置和交互条件已通过；仍需真机确认是否被其他视图遮挡";
            if(s.panel.subviews.lastObject!=s.toolbar) [s.panel bringSubviewToFront:s.toolbar];
        }
    } @catch(__unused NSException *e) { s.toolbar.hidden=YES; s.reason=@"核验宿主布局时异常，已安全隐藏"; }
}
