#include "WUMergeSpacingGeometry.h"
// The experimental integration assumes one message node per section; device validation is required.
static IMP mergeHeightOriginal;
static _Thread_local BOOL mergeHeightActive, mergeHeightReentered;
static double WUMergeHeight(id owner, SEL cmd, UITableView *table, NSIndexPath *path) {
    if(mergeHeightActive) {
        mergeHeightReentered=YES;
        return ((double(*)(id,SEL,id,id))mergeHeightOriginal)(owner,cmd,table,path);
    }
    mergeHeightActive=YES; mergeHeightReentered=NO;
    @try {
    double original=((double(*)(id,SEL,id,id))mergeHeightOriginal)(owner,cmd,table,path);
    @try {
        NSNumber *setting=WUValue(@"mergeSpacing");
        if(![setting isKindOfClass:NSNumber.class] || !isfinite(setting.doubleValue) || setting.doubleValue<0 || setting.doubleValue>30 || ![WUValue(@"enabled") boolValue]) return original;
        if(![table isKindOfClass:UITableView.class] || ![path isKindOfClass:NSIndexPath.class] || path.row!=0 || table!=KnownValue(owner,@"m_tableView")) return original;
        NSString *session=Session(owner), *account=Account(); BOOL group=[session hasSuffix:@"@chatroom"];
        if(!session.length || !account.length || !WUEnabled(group?@"mergeGroup":@"mergePrivate")) return original;
        NSArray *nodes=KnownValue(owner,@"m_arrMessageNodeData"); NSInteger section=path.section;
        // UIKit row/section counts can synchronously re-enter this height callback.
        if(![nodes isKindOfClass:NSArray.class] || nodes.count>10000 || section<0 || (NSUInteger)section+1>=nodes.count) return original;
        id first=nodes[(NSUInteger)section], second=nodes[(NSUInteger)section+1];
        Class base=NSClassFromString(@"BaseMessageViewModel");
        if(!base || ![first isKindOfClass:base] || ![second isKindOfClass:base]) return original;
        id a=Obj(first,@"messageWrap"), b=Obj(second,@"messageWrap"); Class wrapClass=NSClassFromString(@"CMessageWrap");
        if(!wrapClass || ![a isKindOfClass:wrapClass] || ![b isKindOfClass:wrapClass]) return original;
        for(id wrap in @[a,b]) if(!Has(wrap,@"m_uiMessageType","I",@[]) || !Has(wrap,@"m_uiCreateTime","I",@[]) || !Has(wrap,@"m_nsFromUsr","@",@[]) || !Has(wrap,@"m_nsToUsr","@",@[]) || !Has(wrap,@"m_nsRealChatUsr","@",@[]) || Num(wrap,@"m_uiMessageType")==0) return original;
        if(!WUGroupAdjacent(GroupInfo(first,session,account),GroupInfo(second,session,account))) return original;
        if(Num(a,@"m_uiMessageType")==1) {
            if(!Has(a,@"m_nsContent","@",@[])) return original;
            NSString *content=Str(a,@"m_nsContent");
            if(!content || content.length>80 || [content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet].count>2) return original;
        }
        double baseline=([Str(a,@"m_nsFromUsr") hasSuffix:@"@chatroom"] && Str(b,@"m_nsRealChatUsr").length)?30.0:16.0;
        return mergeHeightReentered?original:WUMergeSpacingHeight(original,baseline,setting.doubleValue);
    } @catch(__unused NSException *e) { return original; }
    } @finally { mergeHeightActive=NO; }
}
BOOL WUMergeSpacingAvailable(void) {
    Class cls=NSClassFromString(@"BaseMsgContentViewController"); SEL sel=NSSelectorFromString(@"tableView:heightForRowAtIndexPath:");
    return mergeHeightOriginal && cls && class_getMethodImplementation(cls,sel)==(IMP)WUMergeHeight;
}
static void WUInstallMergeSpacing(void) {
    if(!WU_MERGE_SPACING_EXPERIMENTAL || ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"8.0.79"]) return;
    WUHook(@"BaseMsgContentViewController",@"tableView:heightForRowAtIndexPath:",NO,"d",@[@"@",@"@"],(IMP)WUMergeHeight,&mergeHeightOriginal);
}
static char mergeSpacingDirtyKey;
static void WURefreshMergeSpacingOnAppear(UIViewController *owner) {
    @try {
        if(!objc_getAssociatedObject(owner,&mergeSpacingDirtyKey)) return;
        UITableView *table=KnownValue(owner,@"m_tableView");
        if(owner.viewIfLoaded.window && [table isKindOfClass:UITableView.class] && table.window) {
            [table reloadData];
            objc_setAssociatedObject(owner,&mergeSpacingDirtyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch(__unused NSException *e) {}
}
static void WURefreshMergeSpacing(void) {
    if(!WUMergeSpacingAvailable()) return;
    for(WUChatActions *actions in chatActions.allObjects) @try {
        UIViewController *owner=actions.owner; if(!owner) continue;
        objc_setAssociatedObject(owner,&mergeSpacingDirtyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        WURefreshMergeSpacingOnAppear(owner);
    } @catch(__unused NSException *e) {}
}
