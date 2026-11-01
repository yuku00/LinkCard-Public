#import <Foundation/Foundation.h>
// Included after the production Core/Groups configuration functions by test_p0.py.
static NSUInteger checks, failures;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { failures++; NSLog(@"FAIL configuration line %d",__LINE__); } } while(0)
int main(void) { @autoreleasepool {
    NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    CHECK([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL]);
    configDir=open(dir.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    snapshot=@{@"schema":@1,@"enabled":@NO,@"words":@""};
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
