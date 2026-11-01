#import <Foundation/Foundation.h>
#import "MomentsCacheLogic.h"
#import "DraftMediaLogic.h"
#import "LocalVideoContainer.h"
static NSUInteger checks;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { NSLog(@"FAIL line %d",__LINE__); abort(); } } while(0)
static void U32(uint8_t *p,uint32_t n) { p[0]=n>>24;p[1]=n>>16;p[2]=n>>8;p[3]=n; }
static NSData *Box(const char *type,NSData *body) { NSMutableData *out=[NSMutableData dataWithLength:8]; U32(out.mutableBytes,(uint32_t)body.length+8); memcpy((char *)out.mutableBytes+4,type,4); [out appendData:body]; return out; }
static NSData *VideoEnvelope(void) {
    uint8_t dref[20]={0}; U32(dref+4,1); U32(dref+8,12); memcpy(dref+12,"url ",4); U32(dref+16,1);
    NSData *body=Box("dref",[NSData dataWithBytes:dref length:20]); for(NSString *type in @[@"dinf",@"minf",@"mdia",@"trak",@"moov"]) body=Box(type.UTF8String,body);
    const char brand[8]={'i','s','o','m',0,0,0,0}; NSMutableData *out=[Box("ftyp",[NSData dataWithBytes:brand length:8]) mutableCopy]; [out appendData:body]; [out appendData:Box("mdat",[NSData dataWithBytes:"x" length:1])]; return out;
}
static NSDictionary *WUTestComment(NSString *i,NSString *body,NSNumber *time) { return @{@"id":i,@"author":@"synthetic-author",@"text":body,@"time":time,@"replyTo":@""}; }
int main(void) { @autoreleasepool {
    BOOL (^yes)(void)=^BOOL{ return YES; }; NSError *error=nil;
    NSArray *one=@[WUTestComment(@"1",@"first",@100)], *two=@[WUTestComment(@"2",@"second",@0)];
    NSArray *merged=WUMCacheMergeComments(one,two,&error); CHECK(merged.count==2); CHECK([merged[0][@"id"] isEqual:@"1"]);
    CHECK([WUMCacheMergeComments(merged,@[],NULL) isEqual:merged]); CHECK([WUMCacheMergeComments(merged,one,NULL) isEqual:merged]);
    CHECK(!WUMCacheMergeComments(@[],@[WUTestComment(@"1",@"conflict A",@1),WUTestComment(@"1",@"conflict B",@1)],NULL));
    CHECK(!WUMCacheMergeComments(@[],@[WUTestComment(@"",@"bad",@1)],NULL)); CHECK(!WUMCacheMergeComments(@[],@[WUTestComment(@"1",@"bad",@(-1))],NULL));
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES].URLByResolvingSymlinksInPath;
    NSURL *base=[root URLByAppendingPathComponent:@"MomentsCache"], *text=[base URLByAppendingPathComponent:@"Text"],*media=[base URLByAppendingPathComponent:@"Media"], *source=[root URLByAppendingPathComponent:@"synthetic.mp4"];
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSData *video=VideoEnvelope(); CHECK(WULocalVideoContainer(video.bytes,video.length)); CHECK([video writeToURL:source atomically:YES]);
    NSDictionary *item=WUMCacheNormalize(@"123",@"synthetic-owner",@"body");
    // Structural synthetic envelope is not a playable codec fixture; this tests the real copy/index path.
    CHECK(WUMCacheStoreMedia(text,media,@"a",item,@"video-backup",@[WUDraftMediaReadSource(source,64*1024*1024)],100,[NSSet set],yes,&error));
    NSArray *rows=WUMCacheLoad(text,@"a",NULL), *resources=WUDraftMediaLoad(media,@"a",NULL); CHECK(rows.count==1 && resources.count==1);
    NSString *identifier=rows[0][@"id"]; CHECK([identifier isEqual:resources[0][@"id"]]); CHECK([resources[0][@"kind"] isEqual:@"video-backup"]);
    NSArray *urls=WUDraftMediaURLs(media,@"a",resources[0],NULL); CHECK(urls.count==1); CHECK(![urls[0] isEqual:source]);
    CHECK([NSFileManager.defaultManager removeItemAtURL:source error:NULL]); CHECK([WUDraftMediaReadSource(urls[0],64*1024*1024) isEqual:video]);
    CHECK(!WUMCacheSaveComments(text,@"b",@"synthetic-owner",@"123",one,101,yes,NULL));
    CHECK(WUMCacheSaveComments(text,@"a",@"synthetic-owner",@"123",one,101,yes,NULL)); CHECK(WUMCacheSaveComments(text,@"a",@"synthetic-owner",@"123",two,102,yes,NULL));
    CHECK([WUMCacheLoad(text,@"a",NULL)[0][@"comments"] count]==2);
    CHECK(WUMCacheSaveComments(text,@"a",@"synthetic-owner",@"123",@[],103,yes,NULL)); CHECK([WUMCacheLoad(text,@"a",NULL)[0][@"comments"] count]==2);
    NSURL *textIndex=[text URLByAppendingPathComponent:@"61.plist"]; NSData *before=[NSData dataWithContentsOfURL:textIndex];
    CHECK(!WUMCacheSaveComments(text,@"a",@"synthetic-owner",@"123",@[WUTestComment(@"3",@"cancelled",@2)],104,^BOOL{ return NO; },NULL)); CHECK([[NSData dataWithContentsOfURL:textIndex] isEqual:before]);
    CHECK(!WUMCacheStoreMedia(text,media,@"a",item,@"video-backup",@[[NSData dataWithBytes:"bad" length:3]],105,[NSSet set],yes,NULL)); CHECK([[NSData dataWithContentsOfURL:textIndex] isEqual:before]);
    NSDictionary *later=WUMCacheNormalize(@"124",@"synthetic-owner",@"later video");
    CHECK(WUMCacheStore(text,media,@"a",later,@[[NSData dataWithBytes:"img" length:3]],110,yes,NULL));
    NSString *laterID=WUMCacheLoad(text,@"a",NULL)[0][@"id"];
    CHECK(!WUMCacheStoreMedia(text,media,@"a",later,@"video-backup",@[video],111,[NSSet setWithObject:laterID],yes,NULL));
    CHECK([WUDraftMediaLoad(media,@"a",NULL)[0][@"kind"] isEqual:@"images"]);
    CHECK(WUMCacheStoreMedia(text,media,@"a",later,@"video-backup",@[video],112,[NSSet set],yes,NULL));
    CHECK([WUDraftMediaLoad(media,@"a",NULL)[0][@"kind"] isEqual:@"video-backup"]);
    CHECK(WUMCacheFavoriteChecked(text,@"a",identifier,yes,NULL)); CHECK(WUMCacheReclaim(text,media,@"a",1,200000,[NSSet set],yes,NULL)!=nil); CHECK([NSFileManager.defaultManager fileExistsAtPath:[urls[0] path]]);
    CHECK(WUMCacheFavoriteChecked(text,@"a",identifier,yes,NULL)); CHECK(WUMCacheReclaim(text,media,@"a",1,200000,[NSSet setWithObject:identifier],yes,NULL)!=nil); CHECK([NSFileManager.defaultManager fileExistsAtPath:[urls[0] path]]);
    NSURL *index=[media URLByAppendingPathComponent:@"61/index.plist"]; CHECK([[@"corrupt" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:index atomically:YES]);
    CHECK(WUMCacheReclaim(text,media,@"a",1,200000,[NSSet set],yes,NULL)==nil); CHECK([NSFileManager.defaultManager fileExistsAtPath:[urls[0] path]]);
    CHECK([NSFileManager.defaultManager removeItemAtURL:root error:NULL]);
    printf("Moments video copy/comments/lease/corrupt-index path: %lu checks passed\n",(unsigned long)checks);
} return 0; }
