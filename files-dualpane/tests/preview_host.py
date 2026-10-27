from pathlib import Path
import sys
r=Path(__file__).resolve().parents[1]
prefix='''#import <Foundation/Foundation.h>
#include <assert.h>
@protocol QLPreviewItem @end
@interface NSURL (HostPreview) <QLPreviewItem> @end
@protocol QLPreviewControllerDataSource @end
@interface QLPreviewController : NSObject @end
@implementation QLPreviewController @end
static int stopped;
@interface TestScope : NSObject
- (void)stopAccessingSecurityScopedResource;
@end
@implementation TestScope
- (void)stopAccessingSecurityScopedResource { stopped++; }
@end
'''
main='''
int main(void) { @autoreleasepool {
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSFileManager *fm=NSFileManager.defaultManager;
    assert([fm createDirectoryAtURL:root withIntermediateDirectories:NO attributes:nil error:nil]);
    NSURL *file=[root URLByAppendingPathComponent:@"long-unicode-文件名-fixture.txt"];
    assert([@"fixture" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    assert(CheckPreviewURLs(@[file])==nil);
    assert(CheckPreviewURLs(@[[root URLByAppendingPathComponent:@"missing"]])!=nil);
    @autoreleasepool {
        FPScopedPreview *left=[FPScopedPreview new], *right=[FPScopedPreview new];
        left.urls=@[file]; right.urls=@[];
        left.scopes=(id)@[[TestScope new]];
        assert([left numberOfPreviewItemsInPreviewController:left]==1);
        assert([right numberOfPreviewItemsInPreviewController:right]==0);
        assert([left previewController:left previewItemAtIndex:0]==(id)file);
        assert(stopped==0);
        left=nil;
    }
    assert(stopped==1);
    assert([fm removeItemAtURL:root error:nil]);
    puts("PASS production coordinated preview: temporary fixture, missing-file error, independent lists, scope released on destruction");
} return 0; }
'''
Path(sys.argv[1]).write_text(prefix+(r/'ScopedPreview.inc').read_text()+main)
