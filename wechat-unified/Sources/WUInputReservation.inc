// The captured host uses a full-screen MMInputToolView. Its group-undone
// height is not a reliable reservation API for the ordinary input bar.
#import <objc/runtime.h>
#include <math.h>

static const CGFloat WUInputExtra=44.0;
static char WUInputStateKey, WUInputTrackKey, WUInputToolTrackKey;

@interface WUInputTracking : NSObject
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,weak) UIView *tool;
@property(nonatomic,strong) NSArray *entries;
@property(nonatomic,copy) BOOL (^current)(void);
@property(nonatomic) BOOL queued;
@end
@implementation WUInputTracking @end

@interface WUInputReservation : NSObject
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,weak) UIScrollView *table;
@property(nonatomic,strong) WUInputToolbar *toolbar;
@property(nonatomic,strong) NSArray *entries;
@property(nonatomic,copy) BOOL (^current)(void);
@property(nonatomic) CGFloat addedInset, lastBottom;
@end
@implementation WUInputReservation @end

static void WUInputStop(UIViewController *owner) {
    WUInputReservation *s=objc_getAssociatedObject(owner,&WUInputStateKey);
    if(!s) return;
    objc_setAssociatedObject(owner,&WUInputStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    s.toolbar.current=^BOOL{ return NO; };
    [s.toolbar removeFromSuperview];
    UIScrollView *table=s.table;
    if(table && fabs(table.contentInset.bottom-s.lastBottom)<0.5) {
        UIEdgeInsets inset=table.contentInset;
        inset.bottom-=s.addedInset;
        table.contentInset=inset;
    }
}
static void WUInputRemove(UIViewController *owner) {
    if(!NSThread.isMainThread || !owner) return;
    WUInputTracking *track=objc_getAssociatedObject(owner,&WUInputTrackKey);
    if(track && objc_getAssociatedObject(track.tool,&WUInputToolTrackKey)==track)
        objc_setAssociatedObject(track.tool,&WUInputToolTrackKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(owner,&WUInputTrackKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WUInputStop(owner);
}

// Only accept the observed direct-child input chain and a unique host table.
// The strip is above the input, while the table receives the missing bottom inset.
static void WUInputSyncChecked(UIViewController *owner, NSArray<NSDictionary *> *entries, BOOL (^current)(void)) {
    if(!NSThread.isMainThread || !owner) return;
    UIView *root=owner.viewIfLoaded, *toolCandidate=WUInputToolForOwner(owner);
    if(!root.window || !entries.count || (current && !current())) { WUInputRemove(owner); return; }
    WUInputTracking *track=objc_getAssociatedObject(owner,&WUInputTrackKey);
    if(track && track.tool!=toolCandidate) {
        if(objc_getAssociatedObject(track.tool,&WUInputToolTrackKey)==track)
            objc_setAssociatedObject(track.tool,&WUInputToolTrackKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(owner,&WUInputTrackKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); track=nil;
    }
    if(toolCandidate) {
        if(!track) { track=[WUInputTracking new]; track.owner=owner; track.tool=toolCandidate;
            objc_setAssociatedObject(owner,&WUInputTrackKey,track,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(toolCandidate,&WUInputToolTrackKey,track,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        track.entries=entries; track.current=current;
    }
    UIView *bar=WUInputBarForOwner(owner);
    WUInputReservation *s=objc_getAssociatedObject(owner,&WUInputStateKey);
    if(!bar.window || bar.window!=root.window || bar.hidden || bar.alpha<=0.01) { WUInputStop(owner); return; }
    UIView *container=bar.superview, *tool=container.superview;
    Class tableClass=NSClassFromString(@"MMTableView"); UIScrollView *table=nil;
    for(UIView *v in root.subviews) if(tableClass && [v isKindOfClass:tableClass] && [v isKindOfClass:UIScrollView.class]) { if(table) { WUInputStop(owner); return; } table=(UIScrollView *)v; }
    if(!table || tool.superview!=root || !container.window || container.hidden || tool.hidden || container.alpha<=0.01 || tool.alpha<=0.01 || table.hidden) { WUInputStop(owner); return; }
    CGRect barRect=[bar convertRect:bar.bounds toView:root];
    CGRect strip=CGRectMake(CGRectGetMinX(barRect),CGRectGetMinY(barRect)-WUInputExtra,CGRectGetWidth(barRect),WUInputExtra);
    if(CGRectIsNull(strip) || CGRectIsInfinite(strip) || CGRectGetWidth(strip)<44 || !CGRectContainsRect(root.bounds,strip)) { WUInputStop(owner); return; }
    CGRect inContainer=[root convertRect:strip toView:container];
    for(UIView *child in container.subviews) {
        if(child==bar || child.hidden || child.alpha<=0.01) continue;
        if(!child.userInteractionEnabled && [container.subviews indexOfObjectIdenticalTo:child]<[container.subviews indexOfObjectIdenticalTo:bar]) continue;
        if(CGRectIntersectsRect(CGRectInset(inContainer,0,0.5),[child convertRect:child.bounds toView:container])) { WUInputStop(owner); return; }
    }
    CGRect inTool=[root convertRect:strip toView:tool];
    for(UIView *child in tool.subviews) {
        if(child==container || child.hidden || child.alpha<=0.01) continue;
        if(!child.userInteractionEnabled && [tool.subviews indexOfObjectIdenticalTo:child]<[tool.subviews indexOfObjectIdenticalTo:container]) continue;
        if(CGRectIntersectsRect(CGRectInset(inTool,0,0.5),[child convertRect:child.bounds toView:tool])) { WUInputStop(owner); return; }
    }
    NSUInteger tableIndex=[root.subviews indexOfObjectIdenticalTo:table];
    for(UIView *child in root.subviews) {
        if(child==tool || child==table || child==s.toolbar || child.hidden || child.alpha<=0.01) continue;
        // A sibling behind the host table cannot obscure the reserved strip.
        if([root.subviews indexOfObjectIdenticalTo:child]<tableIndex) continue;
        if(!child.userInteractionEnabled && [root.subviews indexOfObjectIdenticalTo:child]<[root.subviews indexOfObjectIdenticalTo:tool]) continue;
        if(CGRectIntersectsRect(CGRectInset(strip,0,0.5),[child convertRect:child.bounds toView:root])) { WUInputStop(owner); return; }
    }
    if(s && (s.table!=table || s.entries!=entries || (s.current && !s.current()))) { WUInputStop(owner); s=nil; }
    if(!s) {
        s=[WUInputReservation new]; s.owner=owner; s.table=table; s.entries=entries; s.current=current;
        s.toolbar=[[WUInputToolbar alloc] initWithEntries:entries]; s.toolbar.current=current;
        objc_setAssociatedObject(owner,&WUInputStateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [root addSubview:s.toolbar];
    }
    // If the host has replaced its inset, treat that value as the new baseline.
    CGFloat previous=fabs(table.contentInset.bottom-s.lastBottom)<0.5?s.addedInset:0;
    CGRect tableStrip=[root convertRect:strip toView:table];
    CGFloat baseline=table.adjustedContentInset.bottom-previous;
    CGFloat needed=MAX(0,CGRectGetMaxY(table.bounds)-CGRectGetMinY(tableStrip)-baseline);
    if(!isfinite(needed) || needed>CGRectGetHeight(root.bounds)) { WUInputStop(owner); return; }
    UIEdgeInsets inset=table.contentInset;
    CGFloat target=inset.bottom-previous+needed;
    s.addedInset=needed; s.lastBottom=target;
    if(fabs(inset.bottom-target)>0.5) { inset.bottom=target; table.contentInset=inset; }
    if(!CGRectEqualToRect(s.toolbar.frame,strip)) s.toolbar.frame=strip;
    if(root.subviews.lastObject!=s.toolbar) [root bringSubviewToFront:s.toolbar];
}
static __attribute__((unused)) void WUInputSync(UIViewController *owner, NSArray<NSDictionary *> *entries) { WUInputSyncChecked(owner,entries,nil); }

// Called after the existing MMInputToolView layout hook, not by a second hook.
void WUInputToolDidLayout(UIView *tool) {
    if(!NSThread.isMainThread || !tool) return;
    WUInputTracking *track=objc_getAssociatedObject(tool,&WUInputToolTrackKey);
    if(!track || track.queued || track.tool!=tool) return;
    track.queued=YES; __weak WUInputTracking *weak=track;
    dispatch_async(dispatch_get_main_queue(), ^{
        WUInputTracking *t=weak; if(!t) return; t.queued=NO;
        UIViewController *owner=t.owner; UIView *input=t.tool;
        if(!owner || !input || objc_getAssociatedObject(owner,&WUInputTrackKey)!=t || objc_getAssociatedObject(input,&WUInputToolTrackKey)!=t) return;
        @try { WUInputSyncChecked(owner,t.entries,t.current); }
        @catch(__unused NSException *e) { WUInputRemove(owner); }
    });
}
