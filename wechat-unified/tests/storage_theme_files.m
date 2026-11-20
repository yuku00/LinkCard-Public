#import <Foundation/Foundation.h>
#import "ThemeLibrary.h"
#include <assert.h>
static NSData *D(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
int main(void) { @autoreleasepool {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([fm createDirectoryAtPath:root withIntermediateDirectories:NO attributes:nil error:NULL]);
    NSString *a=@"11111111-1111-4111-8111-111111111111", *b=@"22222222-2222-4222-8222-222222222222";
    NSDictionary *old=@{@"nested/icon.png":D(@"synthetic bytes"),@"dark/icon.png":D(@"dark bytes")};
    NSDictionary *next=@{@"nested/icon.png":D(@"new bytes"),@"new.png":D(@"new image")};
    NSError *error=nil;
    assert(WUThemeCommitPack(root,a,old,@{@"name":@"Synthetic"},&error));
    NSString *path=[root stringByAppendingPathComponent:a];
    assert([WUThemeReadPackFiles(path,NULL) isEqual:old]);
    assert(WUThemeCommitPack(root,a,next,@{@"name":@"Replacement"},&error));
    assert([WUThemeReadPackFiles(path,NULL) isEqual:next]);
    assert([WUThemePackMetadata(path)[@"name"] isEqual:@"Replacement"]);
    assert(!WUThemeCommitPack(root,a,@{@"../escape":D(@"bad")},@{@"name":@"Bad"},NULL));
    assert([WUThemeReadPackFiles(path,NULL) isEqual:next]);
    NSString *empty=[root stringByAppendingPathComponent:b];
    assert([fm createDirectoryAtPath:empty withIntermediateDirectories:NO attributes:nil error:NULL]);
    assert(!WUThemeCommitPack(root,b,@{},@{@"name":@"Empty"},NULL));
    assert(!WUThemePackMetadata(empty));
    assert([fm createSymbolicLinkAtPath:[path stringByAppendingPathComponent:@"link.png"] withDestinationPath:@"/etc/passwd" error:NULL]);
    assert(!WUThemeReadPackFiles(path,NULL));
    assert([fm removeItemAtPath:root error:NULL]);
    puts("Theme production storage PASS: synced writes, final readback, atomic exchange, invalid-write retention, empty-remnant rejection, links");
} return 0; }
