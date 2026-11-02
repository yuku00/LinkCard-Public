#import <Foundation/Foundation.h>
#import "../Sources/ExperimentalDelete.h"
static NSString *root, *ident = @"A.webclip";
static BOOL blocked, managed, throwCheck; static int calls, checks, flip;
@interface Mock : NSObject @end
@implementation Mock
+ (id)webClipWithIdentifier:(id)x { return [self new]; }
+ (id)pathForWebClipWithIdentifier:(id)x { return [root stringByAppendingPathComponent:x]; }
- (id)identifier { return ident; }
- (BOOL)removalDisallowed { if (throwCheck) @throw [NSException exceptionWithName:@"test" reason:nil userInfo:nil]; checks++; return blocked || (flip && checks > 1); }
- (BOOL)configurationIsManaged { return managed; }
- (BOOL)removeFromDisk { calls++; return YES; }
@end
@interface NoConfig : NSObject @end
@implementation NoConfig
+ (id)webClipWithIdentifier:(id)x { return [self new]; }
+ (id)pathForWebClipWithIdentifier:(id)x { return [root stringByAppendingPathComponent:x]; }
- (id)identifier { return ident; }
- (BOOL)removalDisallowed { return blocked; }
- (BOOL)removeFromDisk { calls++; return YES; }
@end
@interface BadConfig : NoConfig @end
@implementation BadConfig
- (id)configurationIsManaged { return @NO; }
@end
static void run(NSDictionary *plist, Class cls, BOOL expected) {
    NSString *path = [[root stringByAppendingPathComponent:ident] stringByAppendingPathComponent:@"Info.plist"];
    NSCAssert([plist writeToFile:path atomically:YES], @"write"); calls=0; checks=0;
    NSDictionary *r = WCMExperimentalDeleteForTesting(ident,root,cls);
    if ([r[@"called"] boolValue] != expected || calls != (expected ? 1 : 0)) { NSLog(@"test failed: %@", r); exit(1); }
}
int main(void) { @autoreleasepool {
    root = [[[NSTemporaryDirectory() stringByResolvingSymlinksInPath] stringByAppendingPathComponent:NSUUID.UUID.UUIDString] copy];
    NSCAssert([[NSFileManager defaultManager] createDirectoryAtPath:[root stringByAppendingPathComponent:ident] withIntermediateDirectories:YES attributes:nil error:NULL], @"mkdir");
    NSDictionary *base=@{@"Title":@"WCM-DELETE-TEST", @"ConfigurationIsManaged":@NO};
    run(base,Mock.class,YES); run(base,NoConfig.class,YES);
    blocked=YES; run(base,Mock.class,NO); blocked=NO;
    managed=YES; run(base,Mock.class,NO); managed=NO;
    throwCheck=YES; run(base,Mock.class,NO); throwCheck=NO;
    flip=1; run(base,Mock.class,NO); flip=0;
    run(base,BadConfig.class,NO);
    run(@{@"Title":@"WCM-DELETE-TEST"},Mock.class,NO);
    run(@{@"Title":@"WCM-DELETE-TEST",@"ConfigurationIsManaged":@YES},Mock.class,NO);
    run(@{@"Title":@"WCM-DELETE-TEST",@"ConfigurationIsManaged":@0},Mock.class,NO);
    run(@{@"Title":@"WCM-DELETE-TEST",@"ConfigurationIsManaged":@NO,@"RemovalDisallowed":@1},Mock.class,NO);
    run(@{@"Title":@"WCM-DELETE-TEST",@"ConfigurationIsManaged":@NO,@"RemovalDisallowed":@YES},Mock.class,NO);
    run(@{@"Title":@"WCM-DELETE-TEST",@"ConfigurationIsManaged":@NO,@"RemovalDisallowed":@NO},Mock.class,YES);
    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL]; puts("ObjC synthetic delete checks passed");
} return 0; }
