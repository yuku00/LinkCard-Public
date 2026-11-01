#import "WUNative.h"
/* These are independent local host switches, not reward completion or global UI filters. */
static IMP experimentOriginal, readOnlyOriginal, tableLayoutOriginal;
static BOOL finderReady;
static BOOL RewardKey(id key) {
    if(![key isKindOfClass:NSString.class]) return NO;
    NSString *s=key;
    return [s isEqual:@"clicfg_miniprogram_open_admb2_in_motivating"] ||
           [s isEqual:@"clicfg_miniprogram_open_admb2_in_motivating_test"];
}
static BOOL Experiment(id x,SEL s,id key,BOOL fallback,IMP original) {
    if(RewardKey(key) && WUNativeEnabled(@"rewardFast")) return YES;
    return ((BOOL(*)(id,SEL,id,BOOL))original)(x,s,key,fallback);
}
static BOOL ExperimentNormal(id x,SEL s,id key,BOOL fallback) { return Experiment(x,s,key,fallback,experimentOriginal); }
static BOOL ExperimentReadOnly(id x,SEL s,id key,BOOL fallback) { return Experiment(x,s,key,fallback,readOnlyOriginal); }
static BOOL Matches(id x,NSString *name,const char *ret,NSArray *args) {
    return x && WUMatches(class_getInstanceMethod(object_getClass(x),NSSelectorFromString(name)),ret,args);
}
static id Get(id x,NSString *name) {
    SEL s=NSSelectorFromString(name);
    return Matches(x,name,"@",@[])?((id(*)(id,SEL))objc_msgSend)(x,s):nil;
}
static id Language(void) {
    id center=Get(NSClassFromString(@"MMServiceCenter"),@"defaultCenter");
    SEL s=NSSelectorFromString(@"getService:");
    if(!Matches(center,@"getService:","@",@[@"#"]) && !Matches(center,@"getService:","@",@[@"@"])) return nil;
    Class language=NSClassFromString(@"MMLanguageMgr");
    return language?((id(*)(id,SEL,Class))objc_msgSend)(center,s,language):nil;
}
@interface WUFinderRows : NSObject
@property(nonatomic,weak) id manager,section;
@property(nonatomic,weak) NSMutableArray *cells;
@property(nonatomic,copy) NSArray *before,*after;
@end
@implementation WUFinderRows @end
static char finderRowsKey, finderBusyKey;
static NSHashTable *finderTables;
static BOOL SameRows(NSArray *a,NSArray *b) {
    if(a.count!=b.count) return NO;
    for(NSUInteger i=0;i<a.count;i++) if(a[i]!=b[i]) return NO;
    return YES;
}
static BOOL Exact(id x,NSString *name) { return x && object_getClass(x)==NSClassFromString(name); }
static NSArray *Sections(id manager) {
    id a=Get(manager,@"sections"); return [a isKindOfClass:NSArray.class]?a:nil;
}
static BOOL ProjectionValid(UIView *table) {
    NSArray *pending=objc_getAssociatedObject(table,&finderRowsKey);
    if(!pending.count) return NO;
    id manager=Get(table,@"m_delegate"); NSArray *sections=Sections(manager);
    for(WUFinderRows *r in pending) if(!manager || manager!=r.manager || !r.section || !sections ||
        [sections indexOfObjectIdenticalTo:r.section]==NSNotFound || !r.cells ||
        Get(r.section,@"cells")!=r.cells || !SameRows(r.cells,r.after)) return NO;
    return YES;
}
static BOOL RestoreFinder(UIView *table) {
    NSArray *pending=objc_getAssociatedObject(table,&finderRowsKey);
    objc_setAssociatedObject(table,&finderRowsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL changed=NO;
    for(WUFinderRows *r in pending) {
        id manager=Get(table,@"m_delegate"); NSMutableArray *cells=r.cells;
        // Never reinsert stale rows after the host replaces/rebuilds its section model.
        if(manager!=r.manager || !manager || !r.section || !Sections(manager) || [Sections(manager) indexOfObjectIdenticalTo:r.section]==NSNotFound ||
           !cells || Get(r.section,@"cells")!=cells || !SameRows(cells,r.after)) continue;
        [cells setArray:r.before]; changed=YES;
    }
    return changed;
}
static void FilterFinder(UIView *table) {
    id manager=Get(table,@"m_delegate");
    if(!Exact(manager,@"WCTableViewManager") || Get(manager,@"tableView")!=table) return;
    id language=Language(); SEL localized=NSSelectorFromString(@"getStringForCurLanguage:");
    if(!Matches(language,@"getStringForCurLanguage:","@",@[@"@"])) return;
    NSMutableSet *names=[NSMutableSet set];
    for(NSString *key in @[@"WCFinder_WXProfile_Finder",@"WCFinder_WXProfile_Finder_Brand"]) {
        id name=((id(*)(id,SEL,id))objc_msgSend)(language,localized,key);
        if([name isKindOfClass:NSString.class] && [name length] && ![name isEqual:key]) [names addObject:name];
    }
    if(!names.count) return;
    NSHashTable *targets=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality|NSPointerFunctionsStrongMemory];
    for(UIView *cell in [table.subviews copy]) {
        if(!Exact(cell,@"MMTableViewCell") || ![names containsObject:Get(cell,@"accessibilityLabel") ?: @""]) continue;
        id info=Get(cell,@"cellInfo"); if(info) [targets addObject:info];
    }
    if(!targets.count) return;
    NSMutableArray *changes=[NSMutableArray array];
    for(id section in [Sections(manager) copy]) {
        id cells=Get(section,@"cells"); if(![cells isKindOfClass:NSMutableArray.class]) continue;
        NSArray *before=[cells copy]; NSMutableArray *after=[NSMutableArray array];
        for(id row in before) if(![targets containsObject:row]) [after addObject:row];
        if(before.count==after.count) continue;
        WUFinderRows *r=[WUFinderRows new]; r.manager=manager; r.section=section; r.cells=cells; r.before=before; r.after=after; [changes addObject:r];
    }
    if(!WUNativeEnabled(@"homeFinder") || Get(table,@"m_delegate")!=manager) return;
    // Preflight the whole write set; getters can reenter or replace the host model.
    for(WUFinderRows *r in changes) if(Get(r.section,@"cells")!=r.cells || !SameRows(r.cells,r.before) || [Sections(manager) indexOfObjectIdenticalTo:r.section]==NSNotFound) return;
    if(!WUNativeEnabled(@"homeFinder")) return;
    objc_setAssociatedObject(table,&finderRowsKey,changes,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for(WUFinderRows *r in changes) [r.cells setArray:r.after];
    if(changes.count) {
        [finderTables addObject:table];
        if(Matches(table,@"reloadData","v",@[])) ((void(*)(id,SEL))objc_msgSend)(table,NSSelectorFromString(@"reloadData"));
    }
}
static void FinderLayout(UIView *table,SEL s) {
    if(!NSThread.isMainThread || [objc_getAssociatedObject(table,&finderBusyKey) boolValue]) { ((void(*)(id,SEL))tableLayoutOriginal)(table,s); return; }
    objc_setAssociatedObject(table,&finderBusyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        if(!WUNativeEnabled(@"homeFinder")) @try { RestoreFinder(table); } @catch(NSException *e) {}
        ((void(*)(id,SEL))tableLayoutOriginal)(table,s);
        @try {
            if(!WUNativeEnabled(@"homeFinder")) RestoreFinder(table);
            else if(!ProjectionValid(table)) { RestoreFinder(table); FilterFinder(table); }
        } @catch(NSException *e) { @try { RestoreFinder(table); } @catch(NSException *ignored) {} }
    } @finally {
        @try {
            if(!WUNativeEnabled(@"homeFinder") && RestoreFinder(table) && Matches(table,@"reloadData","v",@[]))
                ((void(*)(id,SEL))objc_msgSend)(table,NSSelectorFromString(@"reloadData"));
        } @catch(NSException *e) {}
        objc_setAssociatedObject(table,&finderBusyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
void WUInstallNativeEntries(void) {
    if(!WUNativeGuardAllowsHooks()) return;
    if(!experimentOriginal) WUHook(@"ExptService",@"getExpt:withBoolDef:",NO,@encode(BOOL),@[@"@",@(@encode(BOOL))],(IMP)ExperimentNormal,&experimentOriginal);
    if(!readOnlyOriginal) WUHook(@"ExptService",@"getExptReadOnly:withBoolDef:",NO,@encode(BOOL),@[@"@",@(@encode(BOOL))],(IMP)ExperimentReadOnly,&readOnlyOriginal);
    static dispatch_once_t once; dispatch_once(&once, ^{
        finderTables=NSHashTable.weakObjectsHashTable;
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            for(UIView *table in finderTables.allObjects) {
                if([objc_getAssociatedObject(table,&finderBusyKey) boolValue]) continue;
                @try {
                    if(RestoreFinder(table) && Matches(table,@"reloadData","v",@[])) ((void(*)(id,SEL))objc_msgSend)(table,NSSelectorFromString(@"reloadData"));
                    if(Matches(table,@"setNeedsLayout","v",@[])) ((void(*)(id,SEL))objc_msgSend)(table,NSSelectorFromString(@"setNeedsLayout"));
                } @catch(NSException *e) {}
            }
        }];
    });
    Class table=NSClassFromString(@"MMTableView"), manager=NSClassFromString(@"WCTableViewManager"), cell=NSClassFromString(@"MMTableViewCell");
    Class center=NSClassFromString(@"MMServiceCenter"); Method service=class_getInstanceMethod(center,NSSelectorFromString(@"getService:"));
    finderReady=Matches(center,@"defaultCenter","@",@[]) && (WUMatches(service,"@",@[@"#"]) || WUMatches(service,"@",@[@"@"])) &&
        WUMatches(class_getInstanceMethod(table,NSSelectorFromString(@"reloadData")),"v",@[]) &&
        WUMatches(class_getInstanceMethod(table,NSSelectorFromString(@"m_delegate")),"@",@[]) &&
        WUMatches(class_getInstanceMethod(manager,NSSelectorFromString(@"sections")),"@",@[]) &&
        WUMatches(class_getInstanceMethod(manager,NSSelectorFromString(@"tableView")),"@",@[]) &&
        WUMatches(class_getInstanceMethod(cell,NSSelectorFromString(@"cellInfo")),"@",@[]) &&
        WUMatches(class_getInstanceMethod(NSClassFromString(@"MMLanguageMgr"),NSSelectorFromString(@"getStringForCurLanguage:")),"@",@[@"@"]);
    if(finderReady && !tableLayoutOriginal) WUHook(@"MMTableView",@"layoutSubviews",NO,"v",@[],(IMP)FinderLayout,&tableLayoutOriginal);
    finderReady=finderReady && tableLayoutOriginal;
}
BOOL WUNativeEntryAvailable(NSString *key) {
    if([key isEqual:@"rewardFast"]) return experimentOriginal || readOnlyOriginal;
    if([key isEqual:@"homeFinder"]) return finderReady;
    return NO;
}
