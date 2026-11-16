#import <Foundation/Foundation.h>
// Included after the production Core/Groups configuration functions by test_p0.py.
static NSUInteger checks, failures;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { failures++; NSLog(@"FAIL configuration line %d",__LINE__); } } while(0)
int main(void) { @autoreleasepool {
    NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    CHECK([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL]);
    configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    NSString *mainPath=[dir stringByAppendingPathComponent:@"config.json"], *backupPath=[dir stringByAppendingPathComponent:@"backup.json"];
    NSData *brokenMain=[@"{invalid main" dataUsingEncoding:NSUTF8StringEncoding], *brokenBackup=[@"{invalid backup" dataUsingEncoding:NSUTF8StringEncoding];
    // Truly new installation: no files exists, saving is allowed.
    snapshot=LoadConfigSnapshot(); CHECK(!WUConfigReadOnly() && !WUEnabled(@"enabled"));
    CHECK(WUSave(@"words",@"first")); CHECK([ReadConfig(@"config.json",NULL)[@"words"] isEqual:@"first"]);
    // Both corrupt: preserve exact bytes and reject every attempted save.
    CHECK([brokenMain writeToFile:mainPath atomically:YES] && [brokenBackup writeToFile:backupPath atomically:YES]);
    snapshot=LoadConfigSnapshot(); CHECK(WUConfigReadOnly() && !WUEnabled(@"enabled"));
    CHECK(!WUSave(@"words",@"must-not-overwrite")); CHECK(!WUSave(@"enabled",@YES));
    CHECK([[NSData dataWithContentsOfFile:mainPath] isEqual:brokenMain]);
    CHECK([[NSData dataWithContentsOfFile:backupPath] isEqual:brokenBackup]);
    // A corrupt file paired with a missing file is not a first install either.
    CHECK([NSFileManager.defaultManager removeItemAtPath:backupPath error:NULL]);
    snapshot=LoadConfigSnapshot(); CHECK(WUConfigReadOnly() && !WUSave(@"enabled",@YES));
    CHECK([[NSData dataWithContentsOfFile:mainPath] isEqual:brokenMain]); CHECK(![NSFileManager.defaultManager fileExistsAtPath:backupPath]);
    CHECK([NSFileManager.defaultManager removeItemAtPath:mainPath error:NULL]);
    CHECK([brokenBackup writeToFile:backupPath atomically:YES]);
    snapshot=LoadConfigSnapshot(); CHECK(WUConfigReadOnly() && !WUSave(@"enabled",@YES));
    CHECK(![NSFileManager.defaultManager fileExistsAtPath:mainPath]); CHECK([[NSData dataWithContentsOfFile:backupPath] isEqual:brokenBackup]);
    // A dangling symlink is not ENOENT: O_NOFOLLOW must reject it without replacing it.
    CHECK([NSFileManager.defaultManager removeItemAtPath:backupPath error:NULL]);
    CHECK(symlink("missing-target",mainPath.fileSystemRepresentation)==0);
    snapshot=LoadConfigSnapshot(); CHECK(WUConfigReadOnly() && !WUSave(@"enabled",@YES));
    struct stat linkStat; CHECK(lstat(mainPath.fileSystemRepresentation,&linkStat)==0 && S_ISLNK(linkStat.st_mode));
    CHECK([NSFileManager.defaultManager removeItemAtPath:mainPath error:NULL]);
    // A valid backup remains a supported recovery path, including unknown fields.
    NSData *valid=[NSJSONSerialization dataWithJSONObject:@{@"schema":@1,@"enabled":@NO,@"words":@"recover",@"unknown":@"preserve"} options:0 error:NULL];
    CHECK([brokenMain writeToFile:mainPath atomically:YES] && [valid writeToFile:backupPath atomically:YES]);
    snapshot=LoadConfigSnapshot(); CHECK(!WUConfigReadOnly() && [WUValue(@"words") isEqual:@"recover"]);
    CHECK(WUSave(@"enabled",@YES)); CHECK([ReadConfig(@"config.json",NULL)[@"unknown"] isEqual:@"preserve"]);
    snapshot=LoadConfigSnapshot(); CHECK(!WUConfigReadOnly() && WUEnabled(@"enabled") && [WUValue(@"unknown") isEqual:@"preserve"]);
    // An inaccessible config directory is not a new installation.
    close(configDir); configDir=-1; snapshot=LoadConfigSnapshot(); CHECK(WUConfigReadOnly() && !WUSave(@"enabled",@YES));
    configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    CHECK([NSFileManager.defaultManager removeItemAtPath:mainPath error:NULL] && [NSFileManager.defaultManager removeItemAtPath:backupPath error:NULL]);
    snapshot=LoadConfigSnapshot(); CHECK(!WUConfigReadOnly());
    CHECK(!WUEnabled(@"officialRecoFlow") && !WUEnabled(@"officialRecCard"));
    CHECK(WUSave(@"officialRecoFlow",@YES) && WUSave(@"officialRecCard",@NO));
    snapshot=ReadConfig(@"config.json",NULL);
    CHECK([WUValue(@"officialRecoFlow") boolValue] && ![WUValue(@"officialRecCard") boolValue]);
    CHECK(!WUEnabled(@"officialRecoFlow"));
    CHECK(WUSave(@"enabled",@YES) && WUEnabled(@"officialRecoFlow") && !WUEnabled(@"officialRecCard"));
    CHECK(WUSave(@"officialRecoFlow",@NO) && WUSave(@"officialRecCard",@YES));
    close(configDir); configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); snapshot=ReadConfig(@"config.json",NULL);
    CHECK(!WUEnabled(@"officialRecoFlow") && WUEnabled(@"officialRecCard"));
    CHECK(!WUSave(@"officialRecoFlow",@"YES") && !WUSave(@"officialRecCard",@[]));
    CHECK(WUSave(@"enabled",@NO));
    CHECK(!WUEnabled(@"miniBannerAds") && !WUEnabled(@"miniInterstitialAds"));
    CHECK(WUSave(@"miniBannerAds",@YES) && WUSave(@"miniInterstitialAds",@NO));
    snapshot=ReadConfig(@"config.json",NULL);
    CHECK(!WUEnabled(@"miniBannerAds"));
    CHECK(WUSave(@"enabled",@YES));
    CHECK(WUEnabled(@"miniBannerAds") && !WUEnabled(@"miniInterstitialAds"));
    CHECK(WUSave(@"miniBannerAds",@NO) && WUSave(@"miniInterstitialAds",@YES));
    snapshot=ReadConfig(@"config.json",NULL);
    CHECK(!WUEnabled(@"miniBannerAds") && WUEnabled(@"miniInterstitialAds"));
    NSData *adsBefore=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
    CHECK(!WUSave(@"miniBannerAds",@"YES") && !WUSave(@"miniInterstitialAds",@[]));
    CHECK([[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]] isEqual:adsBefore]);
    CHECK(WUSave(@"enabled",@NO));
    CHECK(!WUEnabled(@"miniInterstitialAds"));
    CHECK(!WUEnabled(@"hideDictationIcon") && !WUEnabled(@"dictationPreventMistouch"));
    CHECK(WUSave(@"hideDictationIcon",@YES)); CHECK(WUSave(@"dictationPreventMistouch",@NO));
    snapshot=ReadConfig(@"config.json",NULL);
    CHECK([WUValue(@"hideDictationIcon") boolValue] && ![WUValue(@"dictationPreventMistouch") boolValue]);
    CHECK(!WUEnabled(@"hideDictationIcon")); CHECK(WUSave(@"enabled",@YES)); CHECK(WUEnabled(@"hideDictationIcon"));
    CHECK(WUSave(@"hideDictationIcon",@NO)); CHECK(WUSave(@"dictationPreventMistouch",@YES));
    close(configDir); configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); snapshot=ReadConfig(@"config.json",NULL);
    CHECK(!WUEnabled(@"hideDictationIcon") && WUEnabled(@"dictationPreventMistouch"));
    NSData *dictationBefore=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
    CHECK(!WUSave(@"hideDictationIcon",@"YES") && !WUSave(@"dictationPreventMistouch",@[]));
    CHECK([[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]] isEqual:dictationBefore]);
    CHECK(WUSave(@"enabled",@NO)); CHECK(!WUEnabled(@"dictationPreventMistouch"));
    // Existing legacy data, including malformed/unknown shapes, must not reset config.
    for(id legacy in @[@{@"enabled":@YES,@"names":@{@"OldVC":@"legacy"}}, @[@"unrecognised"], [NSNull null]]) {
        NSMutableDictionary *existing=[snapshot mutableCopy]; existing[@"pluginHub"]=legacy;
        NSData *data=[NSJSONSerialization dataWithJSONObject:existing options:0 error:NULL];
        CHECK(WriteConfig(data,@"config.json")); snapshot=ReadConfig(@"config.json",NULL);
        CHECK(snapshot != nil && [WUValue(@"pluginHub") isEqual:legacy]);
        CHECK(!WUSave(@"pluginHub",@{}));
        CHECK(WUSave(@"words",@"legacy-preserved")); snapshot=ReadConfig(@"config.json",NULL);
        CHECK([WUValue(@"pluginHub") isEqual:legacy] && [WUValue(@"words") isEqual:@"legacy-preserved"]);
    }
    NSDictionary *themeOptions=@{@"sort":@"modified",@"ascending":@NO,@"cards":@YES,@"pinned":@[]};
    NSDictionary *styles=@{@"searchSurface":@{@"radius":@18,@"text":@"#123456",@"backgroundDark":@"#0a0a0a",@"fontSize":@20}};
    CHECK(WUSave(@"themeOptions",themeOptions)); CHECK(WUSave(@"surfaceStyles",styles));
    snapshot=ReadConfig(@"config.json",NULL); CHECK([WUValue(@"themeOptions") isEqual:themeOptions]); CHECK([WUValue(@"surfaceStyles") isEqual:styles]);
    NSData *styleBefore=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
    CHECK(!WUSave(@"themeOptions",@{@"sort":@"unknown"})); CHECK(!WUSave(@"surfaceStyles",@{@"searchSurface":@{@"radius":@(-1)}}));
    CHECK([[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]] isEqual:styleBefore]);
    for(NSString *role in @[@"referMessageSurface",@"textPreviewSurface",@"quickReplySurface",@"hostPopupSurface"]) {
        CHECK(!WUEnabled(role));
        CHECK(WUSave(role,@YES));
        NSDictionary *style=@{@"radius":@12,@"background":@"#123456",@"backgroundDark":@"#abcdef",@"fontSize":@18};
        NSMutableDictionary *all=[WUValue(@"surfaceStyles") mutableCopy]; all[role]=style;
        CHECK(WUSave(@"surfaceStyles",all));
        close(configDir); configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); snapshot=ReadConfig(@"config.json",NULL);
        CHECK([WUValue(role) boolValue] && [WUValue(@"surfaceStyles")[role] isEqual:style]);
        CHECK(!WUEnabled(role)); CHECK(WUSave(@"enabled",@YES)); CHECK(WUEnabled(role));
        NSData *saved=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
        CHECK(!WUSave(role,@"YES")); all[role]=@{@"radius":@(-1)};
        CHECK(!WUSave(@"surfaceStyles",all));
        CHECK([[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]] isEqual:saved]);
        CHECK(WUSave(role,@NO)); snapshot=ReadConfig(@"config.json",NULL);
        CHECK(!WUEnabled(role) && [WUValue(@"surfaceStyles")[role] isEqual:style]);
        CHECK(WUSave(@"enabled",@NO));
    }
    NSDictionary *on=@{@"enabled":@YES,@"monitor":@[@"friend"],@"exclude":@[@"excluded"],@"days":@30};
    NSMutableDictionary *off=[on mutableCopy]; off[@"enabled"]=@NO;
    CHECK(WUSaveAccountOption(@"A",@"momentsCache",on));
    CHECK([WUAccountOptions(@"A")[@"momentsCache"] isEqual:on]);
    snapshot=ReadConfig(@"config.json",NULL);
    CHECK([WUAccountOptions(@"A")[@"momentsCache"] isEqual:on]);
    CHECK(WUSaveAccountOption(@"A",@"momentsCache",off));
    close(configDir); configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); snapshot=ReadConfig(@"config.json",NULL);
    CHECK([WUAccountOptions(@"A")[@"momentsCache"] isEqual:off]);
    CHECK(WUSaveAccountOption(@"A",@"momentsCache",on));
    NSData *before=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
    currentAccount=@"B";
    CHECK(!WUSaveAccountOption(@"A",@"momentsCache",off)); CHECK(WUAccountOptions(@"A").count==0);
    CHECK(WUSaveAccountOption(@"B",@"momentsCache",off));
    CHECK([WUAccountOptions(@"B")[@"momentsCache"] isEqual:off]);
    currentAccount=@"A"; snapshot=ReadConfig(@"config.json",NULL);
    CHECK([WUAccountOptions(@"A")[@"momentsCache"] isEqual:on]);
    before=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]];
    CHECK(!WUSaveAccountOption(@"A",@"momentsCache",@{@"enabled":@YES,@"monitor":@[],@"exclude":@[],@"days":@0}));
    CHECK(!WUSaveAccountOption(@"A",@"unknown",on));
    CHECK([[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.json"]] isEqual:before]);
    CHECK([ReadConfig(@"backup.json",NULL)[@"accounts"] isKindOfClass:NSDictionary.class]);
    close(configDir); configDir=-1; CHECK(!WUSaveAccountOption(@"A",@"momentsCache",off));
    CHECK([NSFileManager.defaultManager removeItemAtPath:dir error:NULL]);
    printf("P0_CONFIG: %lu checks, %lu failures (production save/disk/reload/account gate)\n",(unsigned long)checks,(unsigned long)failures);
} return failures?1:0; }
