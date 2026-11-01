#import "WU.h"
#import "ThemeCatalog.h"
#import "ThemePrimitives.h"
#import "InteractionLogic.h"
@protocol WUStyledText <NSObject>
@property(nonatomic,strong) UIFont *font;
@property(nonatomic,strong) UIColor *textColor;
@end
static char styleBaselineKey;
static NSHashTable<UIView *> *styledViews;
static UIColor *HexColor(id value) { double c[4]; return [value isKindOfClass:NSString.class]&&WUParseRGBA([value UTF8String],c)?[UIColor colorWithRed:c[0] green:c[1] blue:c[2] alpha:c[3]]:nil; }
NSDictionary *WUSurfaceStyle(NSString *key) { id all=WUValue(@"surfaceStyles"); return WUValidSurfaceStyles(all)?all[key]?:@{}:@{}; }
UIColor *WUSurfaceColor(NSString *role,NSString *property,UITraitCollection *traits,UIColor *fallback) {
    NSDictionary *style=WUSurfaceStyle(role); BOOL dark=traits.userInterfaceStyle==UIUserInterfaceStyleDark;
    UIColor *color=HexColor(dark?style[[property stringByAppendingString:@"Dark"]]:nil)?:HexColor(style[property]);
    NSString *token=[@{@"background":@"bg-1",@"text":@"fg-0",@"tint":@"brand",@"border":@"fg-3"} objectForKey:property];
    return color?:WUThemeColor(token,traits)?:[fallback resolvedColorWithTraitCollection:traits];
}
static id Current(UIView *v,NSString *k) {
    if([k isEqual:@"radius"]) return @(v.layer.cornerRadius);
    if([k isEqual:@"borderWidth"]) return @(v.layer.borderWidth);
    if([k isEqual:@"border"]) return v.layer.borderColor?[UIColor colorWithCGColor:v.layer.borderColor]:NSNull.null;
    if([k isEqual:@"clip"]) return @(v.clipsToBounds);
    if([k isEqual:@"background"]) return v.backgroundColor?:NSNull.null;
    if([k isEqual:@"tint"]) return v.tintColor?:NSNull.null;
    if([k isEqual:@"opacity"]) return @(v.alpha);
    if([k isEqual:@"font"]&&[v respondsToSelector:@selector(font)]) return [(id<WUStyledText>)v font]?:NSNull.null;
    if([k isEqual:@"text"]&&[v respondsToSelector:@selector(textColor)]) return [(id<WUStyledText>)v textColor]?:NSNull.null;
    return NSNull.null;
}
static void Set(UIView *v,NSString *k,id x) {
    if(x==NSNull.null) x=nil;
    if([k isEqual:@"radius"]) v.layer.cornerRadius=[x doubleValue];
    else if([k isEqual:@"borderWidth"]) v.layer.borderWidth=[x doubleValue];
    else if([k isEqual:@"border"]) v.layer.borderColor=[x CGColor];
    else if([k isEqual:@"clip"]) v.clipsToBounds=[x boolValue];
    else if([k isEqual:@"background"]) v.backgroundColor=x;
    else if([k isEqual:@"tint"]) v.tintColor=x;
    else if([k isEqual:@"opacity"]) v.alpha=[x doubleValue];
    else if([k isEqual:@"font"]) [(id<WUStyledText>)v setFont:x];
    else if([k isEqual:@"text"]) [(id<WUStyledText>)v setTextColor:x];
}
void WURestoreConfiguredSurface(UIView *v) {
    NSDictionary *state=objc_getAssociatedObject(v,&styleBaselineKey); if(!state) return;
    for(UIView *child in state[@"children"]) WURestoreConfiguredSurface(child);
    for(NSString *k in state[@"old"]) if(WUSurfaceValueOwned(Current(v,k),state[@"applied"][k])) Set(v,k,state[@"old"][k]);
    objc_setAssociatedObject(v,&styleBaselineKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void Apply(UIView *v,NSDictionary *values,NSArray *children) {
    NSMutableDictionary *old=[NSMutableDictionary dictionary]; for(NSString *k in values) { old[k]=Current(v,k); Set(v,k,values[k]); }
    objc_setAssociatedObject(v,&styleBaselineKey,@{@"old":old,@"applied":values,@"children":children?:@[]},OBJC_ASSOCIATION_RETAIN_NONATOMIC); [styledViews addObject:v];
}
static void TextViews(UIView *v,NSMutableArray *out,NSUInteger depth) {
    if(depth>5||out.count>=64) return;
    if([v isKindOfClass:UILabel.class]||[v isKindOfClass:UITextView.class]||[v isKindOfClass:UITextField.class]) { [out addObject:v]; return; }
    for(UIView *child in v.subviews) TextViews(child,out,depth+1);
}
void WUApplyConfiguredSurface(UIView *v,NSString *role,CGFloat radius,BOOL background) {
    static dispatch_once_t once; dispatch_once(&once,^{ styledViews=NSHashTable.weakObjectsHashTable;
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ for(UIView *view in styledViews.allObjects) { WURestoreConfiguredSurface(view); [view setNeedsLayout]; } [styledViews removeAllObjects]; }];
    });
    WURestoreConfiguredSurface(v); if(!WUEnabled(role)||!v.window||CGRectIsEmpty(v.bounds)) return;
    NSDictionary *s=WUSurfaceStyle(role); CGFloat r=s[@"radius"]?[s[@"radius"] doubleValue]:radius;
    NSMutableDictionary *values=[@{@"radius":@(MIN(r,MIN(v.bounds.size.width,v.bounds.size.height)/2)),@"clip":@YES} mutableCopy];
    if(background||s[@"background"]||s[@"backgroundDark"]) values[@"background"]=WUSurfaceColor(role,@"background",v.traitCollection,UIColor.secondarySystemGroupedBackgroundColor);
    if(s[@"opacity"]) values[@"opacity"]=s[@"opacity"];
    if(s[@"borderWidth"]||[role isEqual:@"inputBorder"]||[role isEqual:@"noticeBorder"]) { values[@"borderWidth"]=s[@"borderWidth"]?:@1; values[@"border"]=WUSurfaceColor(role,@"border",v.traitCollection,UIColor.systemTealColor); }
    UIColor *tint=WUSurfaceColor(role,@"tint",v.traitCollection,nil); if(tint) values[@"tint"]=tint;
    NSMutableArray *textViews=[NSMutableArray array]; TextViews(v,textViews,0); NSMutableArray *children=[NSMutableArray array];
    for(UIView *text in textViews) {
        NSMutableDictionary *props=[NSMutableDictionary dictionary]; UIColor *color=WUSurfaceColor(role,@"text",text.traitCollection,nil); if(color) props[@"text"]=color;
        if(s[@"fontSize"]||s[@"fontName"]||s[@"fontWeight"]) {
            UIFont *old=[(id<WUStyledText>)text font]; CGFloat size=s[@"fontSize"]?[s[@"fontSize"] doubleValue]:(old.pointSize?:17);
            UIFont *font=s[@"fontName"]?[UIFont fontWithName:s[@"fontName"] size:size]:nil;
            if(!font) font=s[@"fontWeight"]?[UIFont systemFontOfSize:size weight:[s[@"fontWeight"] doubleValue]]:([old fontWithSize:size]?:[UIFont systemFontOfSize:size]); if(font) props[@"font"]=font;
        }
        if(text==v) [values addEntriesFromDictionary:props]; else if(props.count) { WURestoreConfiguredSurface(text); Apply(text,props,nil); [children addObject:text]; }
    }
    Apply(v,values,children);
}
