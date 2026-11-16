#import "WU.h"
#import "WUEmoticonCornerState.h"
#import <QuartzCore/QuartzCore.h>
#include <string.h>

@interface WUEmoticonCornerRecord : NSObject
@property(nonatomic,weak) UIView *cell;
@property(nonatomic,weak) UIView *container;
@property(nonatomic,weak) UIView *imageView;
@property(nonatomic,assign) WUCornerState state;
@end
@implementation WUEmoticonCornerRecord
@end
static char recordKey;
static NSHashTable<UIView *> *views, *imageCells;
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

static IMP imageLayoutOriginal, imageModelOriginal, imageReuseOriginal, imageWindowOriginal;
static Ivar imageIvar;
static void ImageLayout(UIView *cell, SEL s);
static void ImageModel(UIView *cell, SEL s, id model);
static void ImageReuse(UIView *cell, SEL s);
static void ImageWindow(UIView *cell, SEL s);
static BOOL ImageHooksReady(Class cls) {
    return imageIvar && imageLayoutOriginal && imageModelOriginal && imageReuseOriginal && imageWindowOriginal &&
        class_getMethodImplementation(cls,NSSelectorFromString(@"layoutContentView"))==(IMP)ImageLayout &&
        class_getMethodImplementation(cls,NSSelectorFromString(@"setViewModel:"))==(IMP)ImageModel &&
        class_getMethodImplementation(cls,NSSelectorFromString(@"prepareForReuse"))==(IMP)ImageReuse &&
        class_getMethodImplementation(cls,NSSelectorFromString(@"didMoveToWindow"))==(IMP)ImageWindow;
}
static void ImageRestoreCell(UIView *cell) {
    for(UIView *v in views.allObjects) {
        WUEmoticonCornerRecord *r=objc_getAssociatedObject(v,&recordKey);
        if(r.cell==cell) Restore(v);
    }
}
static void ImageRefresh(UIView *cell) {
    Class cls=NSClassFromString(@"ImageMessageCellView"), imageClass=NSClassFromString(@"YYAsyncImageView");
    UIView *image=nil;
    if(cls && imageClass && object_getClass(cell)==cls && ImageHooksReady(cls) && cell.window) {
        id candidate=object_getIvar(cell,imageIvar);
        if(object_getClass(candidate)==imageClass && [candidate isDescendantOfView:cell] && [candidate window]==cell.window) image=candidate;
    }
    for(UIView *v in views.allObjects) {
        WUEmoticonCornerRecord *r=objc_getAssociatedObject(v,&recordKey);
        if(r.cell==cell && (v!=image || r.container!=image.superview || !WUEnabled(@"imageContentCorner"))) Restore(v);
    }
    if(!image || !WUEnabled(@"imageContentCorner")) return;
    WUEmoticonCornerRecord *record=objc_getAssociatedObject(image,&recordKey);
    if(record && (record.cell!=cell || record.container!=image.superview)) { Restore(image); record=nil; }
    if(!record) { record=[WUEmoticonCornerRecord new]; record.cell=cell; record.container=image.superview; record.imageView=image; objc_setAssociatedObject(image,&recordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [views addObject:image]; }
    WUCornerState state=record.state; double radius=image.layer.cornerRadius; bool masks=image.layer.masksToBounds;
    NSNumber *setting=WUSurfaceStyle(@"imageContentCorner")[@"radius"];
    WUCornerApply(&state,&radius,&masks,setting?setting.doubleValue:12); record.state=state;
    [CATransaction begin]; [CATransaction setDisableActions:YES]; image.layer.cornerRadius=radius; image.layer.masksToBounds=masks; [CATransaction commit];
}
static void ImageLayout(UIView *cell, SEL s) { ((void(*)(id,SEL))imageLayoutOriginal)(cell,s); [imageCells addObject:cell]; ImageRefresh(cell); }
static void ImageModel(UIView *cell, SEL s, id model) { ImageRestoreCell(cell); ((void(*)(id,SEL,id))imageModelOriginal)(cell,s,model); [cell setNeedsLayout]; }
static void ImageReuse(UIView *cell, SEL s) { ImageRestoreCell(cell); ((void(*)(id,SEL))imageReuseOriginal)(cell,s); }
static void ImageWindow(UIView *cell, SEL s) { ImageRestoreCell(cell); ((void(*)(id,SEL))imageWindowOriginal)(cell,s); if(cell.window) [cell setNeedsLayout]; }
void WUInstallImageCorners(void) {
    Class cls=NSClassFromString(@"ImageMessageCellView"), imageClass=NSClassFromString(@"YYAsyncImageView");
    if(!cls || !imageClass || ![cls isSubclassOfClass:UIView.class] || ![imageClass isSubclassOfClass:UIImageView.class]) return;
    Ivar ivar=class_getInstanceVariable(cls,"m_imageView");
    if(!ivar || !ivar_getTypeEncoding(ivar) || strcmp(ivar_getTypeEncoding(ivar),"@\"YYAsyncImageView\"")!=0) return;
    imageIvar=ivar;
    if(WUHook(@"ImageMessageCellView",@"setViewModel:",NO,"v",@[@"@"],(IMP)ImageModel,&imageModelOriginal) &&
       WUHook(@"ImageMessageCellView",@"prepareForReuse",NO,"v",@[],(IMP)ImageReuse,&imageReuseOriginal) &&
       WUHook(@"ImageMessageCellView",@"didMoveToWindow",NO,"v",@[],(IMP)ImageWindow,&imageWindowOriginal))
        WUHook(@"ImageMessageCellView",@"layoutContentView",NO,"v",@[],(IMP)ImageLayout,&imageLayoutOriginal);
}
void WUInstallEmoticonCorners(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{
        views=NSHashTable.weakObjectsHashTable; imageCells=NSHashTable.weakObjectsHashTable;
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ for(UIView *v in views.allObjects) { Restore(v); [v setNeedsLayout]; } for(UIView *cell in imageCells.allObjects) ImageRefresh(cell); }];
    });
    Class cls=NSClassFromString(@"MMEmoticonView");
    if(cls && [cls isSubclassOfClass:UIView.class] && WUHook(@"MMEmoticonView",@"didMoveToWindow",NO,"v",@[],(IMP)Window,&originalWindow) && WUHook(@"MMEmoticonView",@"didMoveToSuperview",NO,"v",@[],(IMP)Superview,&originalSuperview))
        WUHook(@"MMEmoticonView",@"layoutSubviews",NO,"v",@[],(IMP)Layout,&originalLayout);
}
