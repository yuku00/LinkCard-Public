#import <Foundation/Foundation.h>
#import "PluginHubLogic.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSDictionary *o=WUHubDefaultOptions();
    assert(WUHubValidOptions(o)); assert(!WUHubValidOptions(@[]));
    assert(WUHubValidControllerName(@"SettingsVC")); assert(WUHubValidControllerName(@"_TtC5Demo8Settings"));
    assert(!WUHubValidControllerName(@"../Settings")); assert(!WUHubValidControllerName(@"Some Controller")); assert(!WUHubValidControllerName(@""));
    NSArray *registry=@[@{@"controller":@"BSettings",@"title":@"B",@"version":@"2"},@{@"controller":@"ASettings",@"title":@"A"},@{@"controller":@"BSettings",@"title":@"duplicate"},@{@"controller":@"../bad",@"title":@"invalid"},@42];
    NSArray *rows=WUHubRows(registry,o,NO);
    assert(rows.count==2); assert([rows[0][@"controller"] isEqual:@"ASettings"]); assert([rows[1][@"version"] isEqual:@"2"]);
    NSDictionary *edited=WUHubSetEntry(o,@"ASettings",@"  我的设置  ",@"  美化 ",YES);
    assert(WUHubValidOptions(edited)); assert([edited[@"names"][@"ASettings"] isEqual:@"我的设置"]);
    assert([edited[@"groups"][@"ASettings"] isEqual:@"美化"]); assert([edited[@"hidden"] count]==1);
    assert([o[@"names"] count]==0 && [o[@"hidden"] count]==0);
    assert(WUHubRows(registry,edited,NO).count==1); assert(WUHubRows(registry,edited,YES).count==2);
    NSArray *searchable=WUHubRows(registry,edited,YES);
    assert(WUHubFilterRows(searchable,@"  我的  ").count==1);
    assert([WUHubFilterRows(searchable,@"asetTINGS")[0][@"controller"] isEqual:@"ASettings"]);
    assert(WUHubFilterRows(searchable,@"美化").count==1);
    assert(WUHubFilterRows(searchable,@"无结果").count==0);
    assert([WUHubFilterRows(searchable,@"  ") isEqual:searchable]);
    assert(WUHubFilterRows(WUHubRows(registry,edited,NO),@"ASettings").count==0);
    assert(WUHubFilterRows(@[@42,@{@"title":@42}],@"42").count==0);
    NSDictionary *visible=WUHubSetEntry(edited,@"ASettings",@"我的设置",@"美化",NO);
    assert([visible[@"hidden"] count]==0 && WUHubRows(registry,visible,NO).count==2);
    NSDictionary *moved=WUHubMove(o,registry,@"BSettings",-1);
    assert(moved && [WUHubRows(registry,moved,NO)[0][@"controller"] isEqual:@"BSettings"]);
    assert([WUHubMove(moved,registry,@"BSettings",1)[@"order"] isEqual:(@[@"ASettings",@"BSettings"])]);
    assert(!WUHubMove(o,registry,@"ASettings",-1)); assert(!WUHubMove(o,registry,@"BSettings",1));
    assert(!WUHubMove(o,registry,@"missing",1)); assert(!WUHubMove(o,registry,@"ASettings",0));
    NSMutableDictionary *withMissing=[o mutableCopy]; withMissing[@"order"]=@[@"ASettings",@"OfflineSettings",@"BSettings"];
    NSDictionary *preserved=WUHubMove(withMissing,registry,@"BSettings",-1);
    assert([preserved[@"order"] isEqual:(@[@"BSettings",@"OfflineSettings",@"ASettings"])]);
    assert([withMissing[@"order"] isEqual:(@[@"ASettings",@"OfflineSettings",@"BSettings"])]);
    NSMutableArray *full=[NSMutableArray array]; for(unsigned i=0;i<100;i++) [full addObject:[NSString stringWithFormat:@"Offline%u",i]];
    withMissing[@"order"]=full; assert(!WUHubMove(withMissing,registry,@"BSettings",-1)); assert([withMissing[@"order"] count]==100);
    assert(!WUHubSetEntry(o,@"bad/name",@"title",@"group",NO)); assert(!WUHubSetEntry(o,@"ASettings",@"  ",@"group",NO));
    assert(!WUHubSetEntry(o,@"ASettings",@"title",@"\n",NO));
    NSMutableDictionary *bad=[o mutableCopy]; bad[@"enabled"]=@2; assert(!WUHubValidOptions(bad));
    bad=[o mutableCopy]; bad[@"hidden"]=@[@"ASettings",@"ASettings"]; assert(!WUHubValidOptions(bad));
    bad=[o mutableCopy]; bad[@"extra"]=@YES; assert(!WUHubValidOptions(bad));
    bad=[o mutableCopy]; bad[@"custom"]=@{@"ValidSettings":@"本地自定义"}; assert(WUHubValidOptions(bad));
    bad[@"custom"]=@{@"/unsafe":@"拒绝"}; assert(!WUHubValidOptions(bad));
    assert(WUHubRows(registry,bad,NO).count==0);
    NSMutableArray *many=[NSMutableArray array]; for(unsigned i=0;i<101;i++) [many addObject:[NSString stringWithFormat:@"VC%u",i]];
    bad=[o mutableCopy]; bad[@"order"]=many; assert(!WUHubValidOptions(bad));
    NSDictionary *same=WUHubSetEntry(edited,@"ASettings",@"我的设置",@"美化",YES); assert([same[@"hidden"] count]==1);
    puts("PluginHub production model: configuration validation, identity, dedup, group/name, hidden, stable order and limits PASS");
} return 0; }
