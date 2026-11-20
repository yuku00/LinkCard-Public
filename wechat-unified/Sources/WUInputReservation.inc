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
@property(nonatomic) CGFloat layoutY;
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
        [s.tool isDescendantOfView:s.owner.viewIfLoaded] && [s.panel isDescendantOfView:s.tool] && (!s.current || s.current());
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
        double translation=0; long position=0; BOOL hostKnown=YES;
        SEL transSel=NSSelectorFromString(@"getTransToolHeight");
        if([tool respondsToSelector:transSel]) {
            if(Has(tool,@"getTransToolHeight","d",@[])) translation=((double(*)(id,SEL))objc_msgSend)(tool,transSel);
            else hostKnown=NO;
        }
        if(!isfinite(translation)) hostKnown=NO;
        if(hostKnown && translation>0) {
            SEL modeSel=NSSelectorFromString(@"positionMode");
            if(Has(tool,@"positionMode","q",@[])) position=((long(*)(id,SEL))objc_msgSend)(tool,modeSel);
            else if(Has(tool,@"positionMode","Q",@[])) position=(long)((unsigned long(*)(id,SEL))objc_msgSend)(tool,modeSel);
            else if(Has(tool,@"positionMode","i",@[])) position=((int(*)(id,SEL))objc_msgSend)(tool,modeSel);
            else if(Has(tool,@"positionMode","I",@[])) position=(long)((unsigned int(*)(id,SEL))objc_msgSend)(tool,modeSel);
            else hostKnown=NO;
        }
        CGFloat width=CGRectGetWidth(s.panel.bounds);
        BOOL eligible=WUInputValid(s) && hostKnown && isfinite(original) && isfinite(original+48.0) && isfinite(width) && width>=44;
        CGFloat y=WUInputHostY(original,translation,position);
        if(!eligible || !s.reserved || s.layoutY!=y) s.toolbar.hidden=YES;
        s.layoutY=y; s.reserved=eligible;
        if(eligible) s.reason=@"已预留，等待宿主布局后核验位置";
        else s.reason=(!hostKnown ? @"宿主翻译栏高度或位置模式不可识别" : @"上下文、面板宽度或宿主高度不满足安全条件");
        return WUInputHostHeight(original,translation,eligible);
    } @catch(__unused NSException *e) { s.reserved=NO; s.toolbar.hidden=YES; s.reason=@"读取宿主高度状态时异常，已安全隐藏"; return original; }
}

// After host layout, reject input overlap and verify the window's hit-test.
// Never move the host's views.
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
        // The host uses the original height as panel-local y, not input-bar y.
        s.toolbar.frame=CGRectMake(0,s.layoutY,CGRectGetWidth(s.panel.bounds),WUInputExtra);
        CGRect strip=[s.toolbar convertRect:s.toolbar.bounds toView:root];
        CGRect input=[bar convertRect:bar.bounds toView:root];
        UIWindow *window=root.window;
        CGRect stripInWindow=[s.toolbar convertRect:s.toolbar.bounds toView:window];
        BOOL safe=CGRectContainsRect(root.bounds,strip) && CGRectContainsRect(window.bounds,stripInWindow) &&
            WUInputHostDisjoint(strip.origin.x,strip.origin.y,strip.size.width,strip.size.height,input.origin.x,input.origin.y,input.size.width,input.size.height);
        id trans=Obj(tool,@"transToolView");
        if(safe && [trans isKindOfClass:UIView.class]) {
            UIView *view=trans;
            if(view.window==window && !view.hidden && view.alpha>0.01 && !CGRectIsEmpty(view.bounds)) {
                CGRect translated=[view convertRect:view.bounds toView:root];
                safe=WUInputHostDisjoint(strip.origin.x,strip.origin.y,strip.size.width,strip.size.height,translated.origin.x,translated.origin.y,translated.size.width,translated.size.height);
            }
        }
        if(!safe) s.reason=@"工具栏位置超出当前聊天或与输入条、翻译栏重叠，已隐藏";
        // Custom host hit-testing may permit a child outside an ancestor's bounds.
        for(UIView *v=s.panel; safe && v; v=v.superview) {
            CGRect inView=[s.toolbar convertRect:s.toolbar.bounds toView:v];
            if(v.hidden || v.alpha<=0.01 || !v.userInteractionEnabled || (v.clipsToBounds && !CGRectContainsRect(v.bounds,inView))) {
                safe=NO; s.reason=@"上级视图不可见、不可交互或裁剪工具栏";
            }
            if(v==root) break;
        }
        s.toolbar.hidden=!safe;
        if(safe) {
            if(s.panel.subviews.lastObject!=s.toolbar) [s.panel bringSubviewToFront:s.toolbar];
            [s.toolbar layoutIfNeeded];
            CGPoint center=[s.toolbar convertPoint:CGPointMake(CGRectGetMidX(s.toolbar.bounds),CGRectGetMidY(s.toolbar.bounds)) toView:window];
            UIView *hit=[window hitTest:center withEvent:nil];
            safe=(hit==s.toolbar || [hit isDescendantOfView:s.toolbar]);
            s.toolbar.hidden=!safe;
            s.reason=safe ? @"位置及中心点击命中已核验；仍需真机确认各按钮和遮挡" : @"工具栏中心未命中当前工具栏，已隐藏";
        }
    } @catch(__unused NSException *e) { s.toolbar.hidden=YES; s.reason=@"核验宿主布局时异常，已安全隐藏"; }
}
