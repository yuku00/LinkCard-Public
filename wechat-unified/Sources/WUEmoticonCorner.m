#import "WU.h"
#import "WUEmoticonCornerState.h"
#import <QuartzCore/QuartzCore.h>

@interface WUEmoticonCornerRecord : NSObject
@property(nonatomic,weak) UIView *cell;
@property(nonatomic,weak) UIView *container;
@property(nonatomic,weak) UIView *imageView;
@property(nonatomic,assign) WUCornerState state;
@end
@implementation WUEmoticonCornerRecord
@end
static char recordKey;
static NSHashTable<UIView *> *views;
static IMP originalLayout, originalWindow, originalSuperview;
static void Restore(UIView *v) {
    WUEmoticonCornerRecord *record=objc_getAssociatedObject(v,&recordKey);
    if(!record) return;
    WUCornerState state=record.state; double radius=v.layer.cornerRadius; bool masks=v.layer.masksToBounds;
    WUCornerRestore(&state,&radius,&masks);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    v.layer.cornerRadius=radius; v.layer.masksToBounds=masks;
    [CATransaction commit];
    objc_setAssociatedObject(v,&recordKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void WURestoreEmoticonCornersInCell(UIView *cell) {
    for(UIView *v in views.allObjects) {
        WUEmoticonCornerRecord *r=objc_getAssociatedObject(v,&recordKey);
        if(r.cell==cell) { Restore(v); [v setNeedsLayout]; }
    }
}
static UIView *TargetCell(UIView *v, UIView **image) {
    Class emoticon=NSClassFromString(@"MMEmoticonView"), cell=NSClassFromString(@"EmoticonMessageCellView");
    UIView *container=v.superview, *owner=container.superview;
    if(!emoticon || !cell || !WUEmoticonCellLifecycleReady(cell) || object_getClass(v)!=emoticon || object_getClass(container)!=UIView.class || object_getClass(owner)!=cell || !v.window || owner.window!=v.window) return nil;
    UIView *candidate=nil;
    for(UIView *child in v.subviews) if(object_getClass(child)==UIImageView.class) { if(candidate) return nil; candidate=child; }
    if(!candidate || candidate.superview!=v || candidate.window!=v.window) return nil;
    *image=candidate; return owner;
}
static void Refresh(UIView *v) {
    UIView *image=nil, *cell=TargetCell(v,&image);
    WUEmoticonCornerRecord *record=objc_getAssociatedObject(v,&recordKey);
    if(record && (!cell || record.cell!=cell || record.container!=v.superview || record.imageView!=image || !WUEnabled(@"emoticonContentCorner"))) { Restore(v); record=nil; }
    if(!cell || !WUEnabled(@"emoticonContentCorner")) return;
    if(!record) { record=[WUEmoticonCornerRecord new]; record.cell=cell; record.container=v.superview; record.imageView=image; objc_setAssociatedObject(v,&recordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [views addObject:v]; }
    WUCornerState state=record.state; double radius=v.layer.cornerRadius; bool masks=v.layer.masksToBounds;
    NSNumber *setting=WUSurfaceStyle(@"emoticonContentCorner")[@"radius"];
    WUCornerApply(&state,&radius,&masks,setting?setting.doubleValue:12);
    record.state=state;
    [CATransaction begin]; [CATransaction setDisableActions:YES]; v.layer.cornerRadius=radius; v.layer.masksToBounds=masks; [CATransaction commit];
}
static void Layout(UIView *v,SEL s) { ((void(*)(id,SEL))originalLayout)(v,s); Refresh(v); }
static void Superview(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))originalSuperview)(v,s); if(v.window) [v setNeedsLayout]; }
static void Window(UIView *v,SEL s) { Restore(v); ((void(*)(id,SEL))originalWindow)(v,s); if(v.window) [v setNeedsLayout]; }
void WUInstallEmoticonCorners(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{
        views=NSHashTable.weakObjectsHashTable;
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ for(UIView *v in views.allObjects) { Restore(v); [v setNeedsLayout]; } }];
    });
    Class cls=NSClassFromString(@"MMEmoticonView");
    if(cls && [cls isSubclassOfClass:UIView.class] && WUHook(@"MMEmoticonView",@"didMoveToWindow",NO,"v",@[],(IMP)Window,&originalWindow) && WUHook(@"MMEmoticonView",@"didMoveToSuperview",NO,"v",@[],(IMP)Superview,&originalSuperview))
        WUHook(@"MMEmoticonView",@"layoutSubviews",NO,"v",@[],(IMP)Layout,&originalLayout);
}
