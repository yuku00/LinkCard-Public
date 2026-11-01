#import "TestHost.h"
static unsigned experimentCalls,readOnlyCalls,actions;
static BOOL originalThrows,missingLanguage,disableDuringLanguage,disableDuringReload;
static id seenKey;
static BOOL seenDefault;
#if defined(WU_TEST_ENTRY_BAD_ABI)
typedef long long EntryDefault;
#else
typedef BOOL EntryDefault;
#endif
@interface ExptService : NSObject
- (BOOL)getExpt:(id)key withBoolDef:(EntryDefault)value;
- (BOOL)getExptReadOnly:(id)key withBoolDef:(EntryDefault)value;
@end
@implementation ExptService
- (BOOL)getExpt:(id)key withBoolDef:(EntryDefault)value { experimentCalls++; seenKey=key; seenDefault=value; if(originalThrows) @throw [NSException exceptionWithName:@"expt" reason:nil userInfo:nil]; return value; }
- (BOOL)getExptReadOnly:(id)key withBoolDef:(EntryDefault)value { readOnlyCalls++; seenKey=key; seenDefault=value; return !value; }
@end
@interface MMLanguageMgr : NSObject - (id)getStringForCurLanguage:(id)key; @end
@implementation MMLanguageMgr
- (id)getStringForCurLanguage:(id)key {
    if(disableDuringLanguage) { disableDuringLanguage=NO; TestConfig(@{}); }
    if(missingLanguage) return key;
    return [key isEqual:@"WCFinder_WXProfile_Finder"]?@"视频号":@"Channels and live";
}
@end
@interface MMServiceCenter : NSObject + (id)defaultCenter; - (id)getService:(Class)cls; @end
@implementation MMServiceCenter
+ (id)defaultCenter { static id center; if(!center) center=[self new]; return center; }
- (id)getService:(Class)cls { return [cls new]; }
@end
@interface WCTableViewManager : NSObject
@property(nonatomic,strong) id tableView;
@property(nonatomic,strong) NSArray *sections;
@end
@implementation WCTableViewManager @end
@interface OtherManager : WCTableViewManager @end
@implementation OtherManager @end
@interface Section : NSObject @property(nonatomic,strong) NSMutableArray *cells; @end
@implementation Section @end
@interface Row : NSObject - (void)activate; @end
@implementation Row - (void)activate { actions++; } @end
@interface MMTableViewCell : UIView
@property(nonatomic,strong) id cellInfo;
@property(nonatomic,copy) NSString *accessibilityLabel;
@end
@implementation MMTableViewCell @end
@interface EntryLabel : UILabel @property(nonatomic,copy) NSString *accessibilityLabel; @end
@implementation EntryLabel @end
@interface MMTableView : UIView
@property(nonatomic,strong) id m_delegate;
@property(nonatomic) unsigned layouts,reloads;
@property(nonatomic) BOOL throws;
#if defined(WU_TEST_ENTRY_BAD_ABI)
- (BOOL)layoutSubviews;
#else
- (void)layoutSubviews;
#endif
- (void)reloadData;
@end
@implementation MMTableView
#if defined(WU_TEST_ENTRY_BAD_ABI)
- (BOOL)layoutSubviews { self.layouts++; return YES; }
#else
- (void)layoutSubviews { self.layouts++; if(self.throws) @throw [NSException exceptionWithName:@"layout" reason:nil userInfo:nil]; }
#endif
- (void)reloadData { self.reloads++; if(disableDuringReload) { disableDuringReload=NO; TestConfig(@{}); } }
@end
static MMTableView *Table(Class managerClass,NSArray *rows,id target,NSString *label) {
    MMTableView *table=[MMTableView new]; WCTableViewManager *manager=[managerClass new];
    manager.tableView=table; table.m_delegate=manager; Section *section=[Section new]; section.cells=[rows mutableCopy]; manager.sections=@[section];
    MMTableViewCell *cell=[MMTableViewCell new]; cell.cellInfo=target; cell.accessibilityLabel=label; [table addSubview:cell]; return table;
}
static Section *First(MMTableView *t) { return [(WCTableViewManager *)t.m_delegate sections][0]; }
int main(void) { @autoreleasepool {
    TestInit(); WUInstallNative(); ExptService *expt=[ExptService new];
#if defined(WU_TEST_ENTRY_BAD_ABI)
    assert(!WUNativeAvailable(@"rewardFast") && !WUNativeAvailable(@"homeFinder"));
    assert(!WUNativeSave(@"rewardFast",YES) && !WUNativeSave(@"homeFinder",YES));
    assert([expt getExpt:@"x" withBoolDef:1]); puts("PASS wrong ABI: neither native entry installed"); return 0;
#endif
    assert(WUNativeAvailable(@"rewardFast") && WUNativeAvailable(@"homeFinder"));
    NSArray *flags=@[@"clicfg_miniprogram_open_admb2_in_motivating",@"clicfg_miniprogram_open_admb2_in_motivating_test"];
    assert(WUNativeSave(@"rewardFast",YES));
    for(NSString *key in flags) { assert([expt getExpt:key withBoolDef:NO]); assert([expt getExptReadOnly:key withBoolDef:YES]); }
    assert(!experimentCalls && !readOnlyCalls);
    NSString *upper=[flags[0] uppercaseString];
    assert(![expt getExpt:upper withBoolDef:NO] && [seenKey isEqual:upper]);
    assert(![expt getExptReadOnly:upper withBoolDef:YES] && [seenKey isEqual:upper]);
    assert(experimentCalls==1 && readOnlyCalls==1);
    assert(![expt getExpt:@"other" withBoolDef:NO] && !seenDefault && [seenKey isEqual:@"other"]);
    assert([expt getExpt:nil withBoolDef:YES] && seenKey==nil && seenDefault);
    id opaque=[NSObject new]; assert(![expt getExptReadOnly:opaque withBoolDef:YES] && seenKey==opaque);
    assert(![expt getExpt:[flags[0] stringByAppendingString:@"_unrelated"] withBoolDef:NO]);
    originalThrows=YES; @try { [expt getExpt:@"other" withBoolDef:NO]; assert(0); } @catch(NSException *e) { assert([e.name isEqual:@"expt"]); } originalThrows=NO;
    assert(WUNativeSave(@"rewardFast",NO)); assert(![expt getExpt:flags[0] withBoolDef:NO]);
    assert(WUNativeSave(@"rewardFast",YES)); testMaster=NO; assert(![expt getExpt:flags[1] withBoolDef:NO]); testMaster=YES;
    Row *a=[Row new],*finder=[Row new],*b=[Row new]; NSArray *all=@[a,finder,b], *filtered=@[a,b];
    MMTableView *table=Table(WCTableViewManager.class,all,finder,@"视频号");
    assert(WUNativeSave(@"homeFinder",YES)); [table layoutSubviews];
    assert(table.layouts==1 && table.reloads==1 && [First(table).cells isEqual:filtered]);
    [(Row *)First(table).cells[1] activate]; assert(actions==1);
    [table layoutSubviews]; [table layoutSubviews]; assert(table.reloads==1); // no reload/layout cycle
    assert(WUNativeSave(@"homeFinder",NO)); assert([First(table).cells isEqual:all]);
    [(Row *)First(table).cells[1] activate]; assert(actions==2); // original row/action object restored
    assert(WUNativeSave(@"homeFinder",YES)); [table layoutSubviews]; testMaster=NO;
    [NSNotificationCenter.defaultCenter postNotificationName:WUChanged object:nil]; assert([First(table).cells isEqual:all]); testMaster=YES;
    MMTableView *other=Table(OtherManager.class,all,finder,@"视频号"); [other layoutSubviews]; assert([First(other).cells isEqual:all]);
    MMTableView *notInModel=Table(WCTableViewManager.class,all,[Row new],@"视频号"); [notInModel layoutSubviews]; assert([First(notInModel).cells isEqual:all]);
    MMTableView *unrelated=Table(WCTableViewManager.class,all,finder,@"发现页其它入口"); [unrelated layoutSubviews]; assert([First(unrelated).cells isEqual:all]);
    missingLanguage=YES; [table layoutSubviews]; assert([First(table).cells isEqual:all]); missingLanguage=NO;
    disableDuringLanguage=YES; [table layoutSubviews]; assert([First(table).cells isEqual:all]);
    assert(WUNativeSave(@"homeFinder",YES)); disableDuringReload=YES; [table layoutSubviews]; assert([First(table).cells isEqual:all]);
    assert(WUNativeSave(@"homeFinder",YES)); [table layoutSubviews];
    Row *fresh=[Row new]; First(table).cells=[@[fresh] mutableCopy]; assert(WUNativeSave(@"homeFinder",NO)); assert([First(table).cells isEqual:@[fresh]]);
    table.throws=YES; @try { [table layoutSubviews]; assert(0); } @catch(NSException *e) { assert([e.name isEqual:@"layout"]); } table.throws=NO;
    // Brand localization uses the same identity-scoped row filter; ordinary UILabel is never consulted.
    assert(WUNativeSave(@"homeFinder",YES)); MMTableView *brand=Table(WCTableViewManager.class,all,finder,@"Channels and live");
    EntryLabel *label=[EntryLabel new]; label.accessibilityLabel=@"视频号"; [brand addSubview:label];
    [brand layoutSubviews]; assert([First(brand).cells isEqual:filtered] && label.superview==brand);
    puts("PASS production WUHook: two local BOOL flags, default/exception/off fallback, exact profile row identity, original actions, reversible projection, rebuild and reentry");
} return 0; }
