#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "DraftMediaLogic.h"
static int checks;
#define CHECK(x) do { checks++; if(!(x)) { NSLog(@"FAIL %s line %d",#x,__LINE__); abort(); } } while(0)
static BOOL failIndex, failCopy;
@interface NSData (MediaFailure)
- (BOOL)wu_media_write:(NSURL *)url options:(NSDataWritingOptions)options error:(NSError **)error;
@end
@implementation NSData (MediaFailure)
- (BOOL)wu_media_write:(NSURL *)url options:(NSDataWritingOptions)options error:(NSError **)error {
    if((failIndex && [url.lastPathComponent isEqual:@"index.plist"]) || (failCopy && (options & NSDataWritingWithoutOverwriting))) { if(error) *error=[NSError errorWithDomain:@"SyntheticFailure" code:1 userInfo:nil]; return NO; }
    return [self wu_media_write:url options:options error:error];
}
@end
int main(void) { @autoreleasepool {
    method_exchangeImplementations(class_getInstanceMethod(NSData.class,@selector(writeToURL:options:error:)),class_getInstanceMethod(NSData.class,@selector(wu_media_write:options:error:)));
    NSFileManager *fm=NSFileManager.defaultManager;
    NSURL *root=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES].URLByResolvingSymlinksInPath;
    CHECK([fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSData *image=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5foAAAAASUVORK5CYII=" options:0];
    NSData *video=[[NSData alloc] initWithBase64EncodedString:@"AAAAHGZ0eXBpc29tAAACAGlzb21pc28ybXA0MQAAAAhmcmVlAAAAGm1kYXQAAAGzABAHAAABthBgUYI9t+8AAAMxbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAACgAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAlt0cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAACgAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAABAAAAAQAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAAAoAAAAAAABAAAAAAHTbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAAAyAAAAAgBVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABfm1pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAT5zdGJsAAAA2nN0c2QAAAAAAAAAAQAAAMptcDR2AAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAABAAEABIAAAASAAAAAAAAAABE0xhdmM2MC4zMS4xMDIgbXBlZzQAAAAAAAAAAAAAAAAAGP//AAAAYGVzZHMAAAAAA4CAgE8AAQAEgICAQSARAAAAAAMNQAAADhAFgICALwAAAbABAAABtYkTAAABAAAAASAAxI2IAM0AhAIUYwAAAbJMYXZjNjAuMzEuMTAyBoCAgAECAAAAFGJ0cnQAAAAAAAMNQAAADhAAAAAYc3R0cwAAAAAAAAABAAAAAQAAAgAAAAAcc3RzYwAAAAAAAAABAAAAAQAAAAEAAAABAAAAFHN0c3oAAAAAAAAAEgAAAAEAAAAUc3RjbwAAAAAAAAABAAAALAAAAGJ1ZHRhAAAAWm1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAG1kaXJhcHBsAAAAAAAAAAAAAAAALWlsc3QAAAAlqXRvbwAAAB1kYXRhAAAAAQAAAABMYXZmNjAuMTYuMTAw" options:0];
    CHECK(video.length>0);
    NSURL *source=[root URLByAppendingPathComponent:@"synthetic-video.mp4"]; CHECK([video writeToURL:source atomically:YES]);
    NSString *uuid=NSUUID.UUID.UUIDString; NSError *e=nil;
    CHECK(WUDraftMediaLoad(root,@"a",&e).count==0);
    CHECK(WUDraftMediaPut(root,@"a",uuid,@"caption",@"images",@[image],&e));
    NSArray *rows=WUDraftMediaLoad(root,@"a",&e); CHECK(rows.count==1); CHECK([rows[0][@"id"] isEqual:uuid]);
    NSArray *urls=WUDraftMediaURLs(root,@"a",rows[0],&e); CHECK(urls.count==1); NSURL *old=urls[0];
    CHECK(WUDraftMediaLoad(root,@"b",&e).count==0);
    CHECK(!WUDraftMediaURLs(root,@"b",rows[0],&e));
    // Copy failure must retain committed row and all original resources.
    CHECK(!WUDraftMediaPut(root,@"a",uuid,@"failed",@"video-backup",@[[root URLByAppendingPathComponent:@"missing"]],&e));
    CHECK([e.localizedDescription containsString:@"源媒体不可读"]);
    CHECK([WUDraftMediaLoad(root,@"a",&e) isEqual:rows]); CHECK([fm fileExistsAtPath:old.path]);
    failCopy=YES; CHECK(!WUDraftMediaPut(root,@"a",uuid,@"copy failed",@"images",@[image],&e)); failCopy=NO;
    CHECK([WUDraftMediaLoad(root,@"a",&e) isEqual:rows]); CHECK([fm fileExistsAtPath:old.path]);
    NSURL *large=[root URLByAppendingPathComponent:@"oversize"];
    CHECK([fm createFileAtPath:large.path contents:nil attributes:nil]);
    NSFileHandle *sparse=[NSFileHandle fileHandleForWritingAtPath:large.path]; CHECK(sparse!=nil);
    [sparse truncateFileAtOffset:64ULL*1024*1024+1]; [sparse closeFile];
    CHECK(!WUDraftMediaPut(root,@"a",uuid,@"oversize",@"video-backup",@[large],&e));
    CHECK([WUDraftMediaLoad(root,@"a",&e) isEqual:rows]);
    // Real atomic writer failure injected at index commit, after immutable resource write.
    failIndex=YES; CHECK(!WUDraftMediaPut(root,@"a",uuid,@"failed index",@"images",@[image],&e)); failIndex=NO;
    CHECK([WUDraftMediaLoad(root,@"a",&e) isEqual:rows]); CHECK([fm fileExistsAtPath:old.path]);
    // Same owned source path update always copies to a fresh immutable resource.
    CHECK(WUDraftMediaPut(root,@"a",uuid,@"same path",@"images",@[old],&e));
    rows=WUDraftMediaLoad(root,@"a",&e); NSArray *fresh=WUDraftMediaURLs(root,@"a",rows[0],&e); CHECK(fresh.count==1); CHECK(![fresh[0] isEqual:old]); CHECK([fm fileExistsAtPath:old.path]);
    // Shared reference fixture: two rows deliberately reference the same owned file.
    NSURL *index=[[root URLByAppendingPathComponent:@"61"] URLByAppendingPathComponent:@"index.plist"];
    NSMutableDictionary *shared=[rows[0] mutableCopy]; shared[@"id"]=NSUUID.UUID.UUIDString;
    NSDictionary *v=@{@"version":@1,@"account":@"a",@"rows":@[rows[0],shared]};
    NSData *plist=[NSPropertyListSerialization dataWithPropertyList:v format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL]; CHECK([plist writeToURL:index atomically:YES]);
    CHECK(WUDraftMediaDelete(root,@"a",uuid,&e)); CHECK(WUDraftMediaURLs(root,@"a",shared,&e).count==1);
    // Open file emulates an in-flight editor; deletion cannot unlink its backing path.
    NSFileHandle *editing=[NSFileHandle fileHandleForReadingAtPath:[fresh[0] path]]; CHECK(editing!=nil);
    CHECK(WUDraftMediaDelete(root,@"a",shared[@"id"],&e)); CHECK([fm fileExistsAtPath:[fresh[0] path]]); CHECK([editing readDataToEndOfFile].length==image.length); [editing closeFile];
    NSString *videoID=NSUUID.UUID.UUIDString; CHECK(WUDraftMediaPut(root,@"a",videoID,@"",@"video-backup",@[source],&e));
    CHECK([NSData dataWithContentsOfURL:source].length==video.length);
    rows=WUDraftMediaLoad(root,@"a",&e); CHECK(WUDraftMediaURLs(root,@"a",rows[0],&e).count==1);
    // Traversal and symlink resource rejection.
    NSMutableDictionary *bad=[rows[0] mutableCopy]; NSMutableDictionary *r=[bad[@"resources"][0] mutableCopy]; r[@"file"]=@"../synthetic-video"; bad[@"resources"]=@[r]; CHECK(!WUDraftMediaURLs(root,@"a",bad,&e));
    NSURL *link=[[root URLByAppendingPathComponent:@"61"] URLByAppendingPathComponent:NSUUID.UUID.UUIDString]; CHECK([fm createSymbolicLinkAtURL:link withDestinationURL:source error:NULL]);
    r[@"file"]=link.lastPathComponent; bad[@"resources"]=@[r]; CHECK(!WUDraftMediaURLs(root,@"a",bad,&e));
    CHECK(!WUDraftMediaPut(root,@"a",uuid,@"",@"video-backup",@[link],&e));
    // Corrupt index cannot trigger overwrite, deletion or cleanup.
    NSData *corrupt=[@"bad-index" dataUsingEncoding:NSUTF8StringEncoding]; CHECK([corrupt writeToURL:index atomically:YES]);
    CHECK(!WUDraftMediaLoad(root,@"a",&e)); CHECK(!WUDraftMediaDelete(root,@"a",videoID,&e)); CHECK(!WUDraftMediaPut(root,@"a",uuid,@"",@"images",@[image],&e));
    CHECK([[NSData dataWithContentsOfURL:index] isEqual:corrupt]); CHECK([fm fileExistsAtPath:old.path]); CHECK([fm fileExistsAtPath:source.path]);
    CHECK(!WUDraftMediaPut(root,@"b",uuid,@"",@"images",@[],&e));
    // Only the synthetic temporary test container is removed, never production storage.
    CHECK([fm removeItemAtURL:root error:NULL]); printf("Draft media production transactions: %d assertions passed\n",checks);
} return 0; }
