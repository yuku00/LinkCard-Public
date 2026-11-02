#import <Foundation/Foundation.h>
// Included after the production Core/Groups configuration functions by test_p0.py.
static NSUInteger checks, failures;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { failures++; NSLog(@"FAIL configuration line %d",__LINE__); } } while(0)
int main(void) { @autoreleasepool {
    NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    CHECK([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL]);
    configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    snapshot=@{@"schema":@1,@"enabled":@NO,@"words":@""};
    CHECK(!WUEnabled(@"miniBannerAds") && !WUEnabled(@"miniInterstitialAds"));
    CHECK(WUSave(@"miniBannerAds",@YES) && WUSave(@"miniInterstitialAds",@NO));
    snapshot=ReadConfig(@"config.json");
    CHECK(!WUEnabled(@"miniBannerAds"));
    CHECK(WUSave(@"enabled",@YES));
    CHECK(WUEnabled(@"miniBannerAds") && !WUEnabled(@"miniInterstitialAds"));
    CHECK(WUSave(@"miniBannerAds",@NO) && WUSave(@"miniInterstitialAds",@YES));
    snapshot=ReadConfig(@"config.json");
    CHECK(!WUEnabled(@"miniBannerAds") && WUEnabled(@"miniInterstitialAds"));
    NSData *adsBefore=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
    CHECK(!WUSave(@"miniBannerAds",@"YES") && !WUSave(@"miniInterstitialAds",@[]));
    CHECK([[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]] isEqual:adsBefore]);
    CHECK(WUSave(@"enabled",@NO));
    CHECK(!WUEnabled(@"miniInterstitialAds"));
    CHECK(!WUEnabled(@"hideDictationIcon") && !WUEnabled(@"dictationPreventMistouch"));
    CHECK(WUSave(@"hideDictationIcon",@YES)); CHECK(WUSave(@"dictationPreventMistouch",@NO));
    snapshot=ReadConfig(@"config.json");
    CHECK([WUValue(@"hideDictationIcon") boolValue] && ![WUValue(@"dictationPreventMistouch") boolValue]);
    CHECK(!WUEnabled(@"hideDictationIcon")); CHECK(WUSave(@"enabled",@YES)); CHECK(WUEnabled(@"hideDictationIcon"));
    CHECK(WUSave(@"hideDictationIcon",@NO)); CHECK(WUSave(@"dictationPreventMistouch",@YES));
    close(configDir); configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); snapshot=ReadConfig(@"config.json");
    CHECK(!WUEnabled(@"hideDictationIcon") && WUEnabled(@"dictationPreventMistouch"));
    NSData *dictationBefore=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
    CHECK(!WUSave(@"hideDictationIcon",@"YES") && !WUSave(@"dictationPreventMistouch",@[]));
    CHECK([[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]] isEqual:dictationBefore]);
    CHECK(WUSave(@"enabled",@NO)); CHECK(!WUEnabled(@"dictationPreventMistouch"));
    // Existing legacy data, including malformed/unknown shapes, must not reset config.
    for(id legacy in @[@{@"enabled":@YES,@"names":@{@"OldVC":@"legacy"}}, @[@"unrecognised"], [NSNull null]]) {
        NSMutableDictionary *existing=[snapshot mutableCopy]; existing[@"pluginHub"]=legacy;
        NSData *data=[NSJSONSerialization dataWithJSONObject:existing options:0 error:NULL];
        CHECK(WriteConfig(data,@"config.json")); snapshot=ReadConfig(@"config.json");
        CHECK(snapshot != nil && [WUValue(@"pluginHub") isEqual:legacy]);
        CHECK(!WUSave(@"pluginHub",@{}));
        CHECK(WUSave(@"words",@"legacy-preserved")); snapshot=ReadConfig(@"config.json");
        CHECK([WUValue(@"pluginHub") isEqual:legacy] && [WUValue(@"words") isEqual:@"legacy-preserved"]);
    }
    NSDictionary *themeOptions=@{@"sort":@"modified",@"ascending":@NO,@"cards":@YES,@"pinned":@[]};
    NSDictionary *styles=@{@"searchSurface":@{@"radius":@18,@"text":@"#123456",@"backgroundDark":@"#0a0a0a",@"fontSize":@20}};
    CHECK(WUSave(@"themeOptions",themeOptions)); CHECK(WUSave(@"surfaceStyles",styles));
    snapshot=ReadConfig(@"config.json"); CHECK([WUValue(@"themeOptions") isEqual:themeOptions]); CHECK([WUValue(@"surfaceStyles") isEqual:styles]);
    NSData *styleBefore=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
    CHECK(!WUSave(@"themeOptions",@{@"sort":@"unknown"})); CHECK(!WUSave(@"surfaceStyles",@{@"searchSurface":@{@"radius":@(-1)}}));
    CHECK([[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]] isEqual:styleBefore]);
    for(NSString *role in @[@"referMessageSurface",@"textPreviewSurface",@"quickReplySurface",@"hostPopupSurface"]) {
        CHECK(!WUEnabled(role));
        CHECK(WUSave(role,@YES));
        NSDictionary *style=@{@"radius":@12,@"background":@"#123456",@"backgroundDark":@"#abcdef",@"fontSize":@18};
        NSMutableDictionary *all=[WUValue(@"surfaceStyles") mutableCopy]; all[role]=style;
        CHECK(WUSave(@"surfaceStyles",all));
        close(configDir); configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); snapshot=ReadConfig(@"config.json");
        CHECK([WUValue(role) boolValue] && [WUValue(@"surfaceStyles")[role] isEqual:style]);
        CHECK(!WUEnabled(role)); CHECK(WUSave(@"enabled",@YES)); CHECK(WUEnabled(role));
        NSData *saved=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
        CHECK(!WUSave(role,@"YES")); all[role]=@{@"radius":@(-1)};
        CHECK(!WUSave(@"surfaceStyles",all));
        CHECK([[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]] isEqual:saved]);
        CHECK(WUSave(role,@NO)); snapshot=ReadConfig(@"config.json");
        CHECK(!WUEnabled(role) && [WUValue(@"surfaceStyles")[role] isEqual:style]);
        CHECK(WUSave(@"enabled",@NO));
    }
    NSDictionary *on=@{@"enabled":@YES,@"monitor":@[@"friend"],@"exclude":@[@"excluded"],@"days":@30};
    NSMutableDictionary *off=[on mutableCopy]; off[@"enabled"]=@NO;
    CHECK(WUSaveAccountOption(@"A",@"momentsCache",on));
    CHECK([WUAccountOptions(@"A")[@"momentsCache"] isEqual:on]);
    snapshot=ReadConfig(@"config.json");
    CHECK([WUAccountOptions(@"A")[@"momentsCache"] isEqual:on]);
    CHECK(WUSaveAccountOption(@"A",@"momentsCache",off));
    close(configDir); configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); snapshot=ReadConfig(@"config.json");
    CHECK([WUAccountOptions(@"A")[@"momentsCache"] isEqual:off]);
    CHECK(WUSaveAccountOption(@"A",@"momentsCache",on));
    NSData *before=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
    currentAccount=@"B";
    CHECK(!WUSaveAccountOption(@"A",@"momentsCache",off)); CHECK(WUAccountOptions(@"A").count==0);
    CHECK(WUSaveAccountOption(@"B",@"momentsCache",off));
    CHECK([WUAccountOptions(@"B")[@"momentsCache"] isEqual:off]);
    currentAccount=@"A"; snapshot=ReadConfig(@"config.json");
    CHECK([WUAccountOptions(@"A")[@"momentsCache"] isEqual:on]);
    before=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
    CHECK(!WUSaveAccountOption(@"A",@"momentsCache",@{@"enabled":@YES,@"monitor":@[],@"exclude":@[],@"days":@0}));
    CHECK(!WUSaveAccountOption(@"A",@"unknown",on));
    CHECK([[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]] isEqual:before]);
    CHECK([ReadConfig(@"backup.json")[@"accounts"] isKindOfClass:NSDictionary.class]);
    close(configDir); configDir=-1; CHECK(!WUSaveAccountOption(@"A",@"momentsCache",off));
    CHECK([NSFileManager.defaultManager removeItemAtPath:dir error:NULL]);
    printf("P0_CONFIG: %lu checks, %lu failures (production save/disk/reload/account gate)\n",(unsigned long)checks,(unsigned long)failures);
} return failures?1:0; }
