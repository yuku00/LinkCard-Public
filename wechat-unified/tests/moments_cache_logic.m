#import <Foundation/Foundation.h>
#import "MomentsCacheLogic.h"
#import "RepositoryLogic.h"
#import "DraftMediaLogic.h"
#import "GroupLogic.h"
#include <assert.h>
#include <math.h>
#include <dispatch/dispatch.h>
#include <sys/stat.h>
#include <unistd.h>
static NSDictionary *Item(NSString *tid, NSString *text) { return WUMCacheNormalize(tid,@"friend",text); }
static void ReclaimTests(void) {
    assert(!NSThread.isMainThread);
    NSURL *root=[[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString] URLByAppendingPathComponent:@"MomentsCache"].URLByResolvingSymlinksInPath;
    NSURL *text=[root URLByAppendingPathComponent:@"Text"], *media=[root URLByAppendingPathComponent:@"Media"], *dir=[media URLByAppendingPathComponent:@"41"];
    NSError *e=nil; BOOL (^yes)(void)=^BOOL{ return YES; }; BOOL (^no)(void)=^BOOL{ return NO; };
    NSData *data=[NSMutableData dataWithLength:32768];
    assert(WUMCacheStore(text,media,@"A",Item(@"1",@"one"),@[data],100,yes,&e));
    assert(WUMCacheStore(text,media,@"A",Item(@"2",@"two"),@[data],100,yes,&e));
    NSArray *rows=WUMCacheLoad(text,@"A",&e); NSString *one=rows[1][@"id"], *two=rows[0][@"id"];
    NSArray *resources=WUDraftMediaLoad(media,@"A",&e); NSURL *index=[dir URLByAppendingPathComponent:@"index.plist"];
    NSMutableArray *shared=[resources mutableCopy]; NSMutableDictionary *second=[shared[0] mutableCopy]; second[@"resources"]=shared[1][@"resources"]; shared[0]=second;
    NSDictionary *envelope=@{@"version":@1,@"account":@"A",@"rows":shared};
    NSData *plist=[NSPropertyListSerialization dataWithPropertyList:envelope format:NSPropertyListBinaryFormat_v1_0 options:0 error:&e]; assert([plist writeToURL:index atomically:YES]);
    NSURL *common=[dir URLByAppendingPathComponent:shared[0][@"resources"][0][@"file"]];
    assert(WUMCacheFavorite(text,@"A",two,&e));
    NSDictionary *result=WUMCacheReclaim(text,media,@"A",1,200000,[NSSet set],yes,&e);
    assert(result && !e && [result[@"files"] unsignedIntegerValue]==1); // unreferenced second copy only
    assert([NSFileManager.defaultManager fileExistsAtPath:common.path]);
    assert(WUMCacheLoad(text,@"A",&e).count==1 && WUDraftMediaLoad(media,@"A",&e).count==1);
    assert(WUMCacheFavorite(text,@"A",two,&e));
    result=WUMCacheReclaim(text,media,@"A",1,200000,[NSSet setWithObject:two],yes,&e);
    assert(result && [result[@"files"] unsignedIntegerValue]==0 && [NSFileManager.defaultManager fileExistsAtPath:common.path]);
    assert(WUMCacheLoad(text,@"A",&e).count==0); // expired text gone, browser's media reference remains
    struct stat before; assert(stat(common.path.fileSystemRepresentation,&before)==0);
    result=WUMCacheReclaim(text,media,@"A",1,200000,[NSSet set],yes,&e);
    assert(result && [result[@"files"] unsignedIntegerValue]==1 && [result[@"bytes"] unsignedLongLongValue]==(unsigned long long)before.st_blocks*512);
    assert(![NSFileManager.defaultManager fileExistsAtPath:common.path]);
    result=WUMCacheReclaim(text,media,@"A",1,200000,[NSSet set],yes,&e); assert(result && [result[@"files"] unsignedIntegerValue]==0);
    // New-account source or generation failure must preserve the previous record/index.
    assert(WUMCacheStore(text,media,@"A",Item(@"3",@"old"),@[data],100,yes,&e));
    NSArray *old=WUMCacheLoad(text,@"A",&e), *oldMedia=WUDraftMediaLoad(media,@"A",&e);
    assert(!WUMCacheStore(text,media,@"A",Item(@"3",@"changed"),@[data],300,no,&e)); e=nil;
    assert([old isEqual:WUMCacheLoad(text,@"A",&e)] && [oldMedia isEqual:WUDraftMediaLoad(media,@"A",&e)]);
    assert(!WUDraftMediaReadSource([root URLByAppendingPathComponent:@"missing"],8*1024*1024));
    assert(!WUMCacheReclaim(text,media,@"",1,200000,[NSSet set],yes,&e)); e=nil;
    assert(!WUMCacheReclaim(text,media,@"A",1,200000,[NSSet set],no,&e)); e=nil;
    assert([oldMedia isEqual:WUDraftMediaLoad(media,@"A",&e)]);
    // Index corruption, missing index and symlinks all fail closed before unlink.
    NSData *original=[NSData dataWithContentsOfURL:index]; NSData *bad=[@"bad" dataUsingEncoding:NSUTF8StringEncoding];
    assert([bad writeToURL:index atomically:YES]); assert(!WUMCacheReclaim(text,media,@"A",1,200000,[NSSet set],yes,&e)); e=nil;
    assert([original writeToURL:index atomically:YES]);
    assert(unlink(index.path.fileSystemRepresentation)==0); assert(!WUMCacheReclaim(text,media,@"A",1,200000,[NSSet set],yes,&e)); e=nil;
    assert([original writeToURL:index atomically:YES]);
    NSURL *textIndex=[text URLByAppendingPathComponent:@"41.plist"]; NSData *textBefore=[NSData dataWithContentsOfURL:textIndex];
    assert([bad writeToURL:textIndex atomically:YES]); assert(!WUMCacheReclaim(text,media,@"A",1,200000,[NSSet set],yes,&e)); e=nil;
    assert([textBefore writeToURL:textIndex atomically:YES]);
    NSURL *link=[dir URLByAppendingPathComponent:NSUUID.UUID.UUIDString]; assert(symlink(index.path.fileSystemRepresentation,link.path.fileSystemRepresentation)==0);
    assert(!WUMCacheReclaim(text,media,@"A",1,200000,[NSSet set],yes,&e)); e=nil; assert(unlink(link.path.fileSystemRepresentation)==0);
    NSURL *journal=[dir URLByAppendingPathComponent:@"reclaim.plist"];
    assert([bad writeToURL:journal atomically:YES]); assert(!WUMCacheReclaim(text,media,@"A",1,200000,[NSSet set],yes,&e)); e=nil;
    assert([oldMedia isEqual:WUDraftMediaLoad(media,@"A",&e)]); assert(unlink(journal.path.fileSystemRepresentation)==0);
    // Generation changes after a bounded copy: no new index entry, orphan is reclaimable.
    __block NSUInteger checks=0; NSString *aborted=NSUUID.UUID.UUIDString;
    assert(!WUDraftMediaPutChecked(media,@"A",aborted,@"cancel",@"images",@[data],^BOOL{ return ++checks<2; },&e)); e=nil;
    assert([oldMedia isEqual:WUDraftMediaLoad(media,@"A",&e)]);
    // Simulated commit failure after copy by invalidating the index destination; every resource stays.
    NSString *failed=NSUUID.UUID.UUIDString;
    assert(!WUDraftMediaPutChecked(media,@"A",failed,@"fail",@"images",@[data],^BOOL{
        if(++checks==4) { assert(unlink(index.path.fileSystemRepresentation)==0); assert([NSFileManager.defaultManager createDirectoryAtURL:index withIntermediateDirectories:NO attributes:nil error:NULL]); }
        return YES;
    },&e)); e=nil;
    assert([NSFileManager.defaultManager removeItemAtURL:index error:&e]); assert([original writeToURL:index atomically:YES]);
    result=WUMCacheReclaim(text,media,@"A",3650,200000,[NSSet set],yes,&e);
    assert(result && [result[@"files"] unsignedIntegerValue]==2); // failed and cancelled copies only
    assert(WUMCacheLoad(text,@"A",&e).count==1);
    // Draft roots are explicitly outside the reclamation capability.
    assert(!WUMCacheReclaim(text,[root URLByAppendingPathComponent:@"MomentsMediaDrafts"],@"A",1,200000,[NSSet set],yes,&e)); e=nil;
    (void)one;
    assert([NSFileManager.defaultManager removeItemAtURL:root.URLByDeletingLastPathComponent error:&e]);
}
int main(void) { @autoreleasepool {
    dispatch_queue_t io=dispatch_queue_create("test.moments.io",DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(io,^{ @autoreleasepool { ReclaimTests(); dispatch_semaphore_signal(done); } });
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC))==0);
    NSURL *root=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString].URLByResolvingSymlinksInPath;
    NSURL *media=[root URLByAppendingPathComponent:@"media"];
    NSError *e=nil;
    assert([WUMCacheNormalize(@18446744073709551615ULL,@"friend",@"body")[@"tid"] isEqual:@"18446744073709551615"]);
    assert([Item(@"0009",@"")[@"tid"] isEqual:@"9"]);
    assert(!WUMCacheNormalize(@1.5,@"friend",@"text"));
    assert(!Item(@"0",@"a") && !Item(@"-1",@"a") && !Item(@"١",@"a"));
    assert(!WUMCacheNormalize(@1,@"",@"x") && !WUMCacheNormalize(@1,@"a",NSNull.null));
    NSDictionary *r=WUMCacheObserve(root,@"A",Item(@"1",@"first"),100,&e); assert(r && !e);
    NSString *uuid=r[@"id"];
    assert([WUMCacheObserve(root,@"A",Item(@"001",@"first"),200,&e)[@"id"] isEqual:uuid]);
    assert(WUMCacheLoad(root,@"A",&e).count==1);
    assert(WUMCacheObserve(root,@"A",Item(@"2",@"next page"),300,&e));
    // A partial next page, empty/error callback or changed privacy never supplies deletion evidence.
    assert(!WUMCacheObserve(root,@"A",nil,400,&e)); e=nil;
    assert(WUMCacheObserve(root,@"A",Item(@"2",@"next page"),400,&e));
    NSArray *rows=WUMCacheLoad(root,@"A",&e); assert(rows.count==2);
    for(NSDictionary *row in rows) assert([row[@"status"] isEqual:@"seen"]);
    assert(WUMCacheLoad(root,@"B",&e).count==0);
    assert(WUMCacheObserve(root,@"B",Item(@"1",@"other account"),500,&e));
    assert(WUMCacheFavorite(root,@"A",uuid,&e));
    assert(WUMCacheClean(root,@"A",1,100000,&e));
    rows=WUMCacheLoad(root,@"A",&e); assert(rows.count==1 && [rows[0][@"favorite"] boolValue]);
    assert(WUMCacheLoad(root,@"B",&e).count==1);
    assert(WUMCacheObserve(root,@"A",Item(@"1",@"edited body"),100001,&e));
    assert([WUMCacheLoad(root,@"A",&e)[0][@"favorite"] boolValue]);
    NSData *before=[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"41.plist"]];
    NSString *large=[@"x" stringByPaddingToLength:10001 withString:@"x" startingAtIndex:0];
    assert(!WUMCacheObserve(root,@"A",@{@"tid":@"1",@"username":@"friend",@"text":large},200000,&e));
    assert([before isEqual:[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"41.plist"]]]); e=nil;
    // Existing transactional media copy failure leaves old resources and index intact.
    assert(WUDraftMediaPut(media,@"A",uuid,@"copy",@"images",@[[ @"synthetic" dataUsingEncoding:NSUTF8StringEncoding]],&e));
    NSArray *oldMedia=WUDraftMediaLoad(media,@"A",&e);
    assert(!WUDraftMediaPut(media,@"A",uuid,@"copy",@"images",@[[root URLByAppendingPathComponent:@"missing"]],&e)); e=nil;
    assert([oldMedia isEqual:WUDraftMediaLoad(media,@"A",&e)]);
    assert(WUDraftMediaURLs(media,@"A",oldMedia[0],&e).count==1);
    // Bad repository envelope must never turn into an empty cleanup candidate set.
    NSURL *index=[root URLByAppendingPathComponent:@"41.plist"];
    NSData *bad=[@"corrupt" dataUsingEncoding:NSUTF8StringEncoding]; assert([bad writeToURL:index atomically:YES]);
    assert(!WUMCacheLoad(root,@"A",&e)); assert(!WUMCacheClean(root,@"A",1,200000,&e));
    assert(!WUMCacheObserve(root,@"A",Item(@"3",@"new"),200000,&e));
    assert([bad isEqual:[NSData dataWithContentsOfURL:index]]); e=nil;
    assert([before writeToURL:index atomically:YES]);
    // Valid outer repository with malicious inner ID must fail without throwing or writing.
    NSString *json=@"{\"id\":3,\"tid\":\"1\",\"username\":\"friend\",\"text\":\"x\",\"favorite\":false,\"status\":\"seen\",\"first\":1,\"last\":2}";
    assert(WURepositorySave(root,@"A",@[@{@"id":uuid,@"name":@"bad",@"parts":@[@{@"kind":@"text",@"text":json}]}],&e));
    assert(!WUMCacheLoad(root,@"A",&e)); e=nil;
    assert([before writeToURL:index atomically:YES]);
    for(NSUInteger i=1;i<=200;i++) assert(WUMCacheObserve(root,@"limit",Item([@(i) stringValue],@"x"),100,&e));
    assert(!WUMCacheObserve(root,@"limit",Item(@"201",@"x"),100,&e)); e=nil;
    assert(WUMCacheLoad(root,@"limit",&e).count==200);
    assert(!WUMCacheClean(root,@"B",0,100000,&e)); assert(!WUMCacheClean(root,@"B",30,NAN,&e)); e=nil;
    assert(WUValidAccountOptions(@{@"A":@{@"momentsCache":@{@"enabled":@YES,@"monitor":@[@"friend"],@"exclude":@[],@"days":@30}}}));
    assert(!WUValidAccountOptions(@{@"A":@{@"momentsCache":@{@"enabled":@YES,@"monitor":@[],@"exclude":@[],@"days":@0}}}));
    assert(!WUValidAccountOptions(@{@"A":@{@"momentsCache":@{@"enabled":@YES,@"monitor":@[],@"exclude":@[],@"days":@1.5}}}));
    // A non-directory save failure must not touch the original file.
    NSURL *blocked=[root URLByAppendingPathComponent:@"blocked"]; assert([bad writeToURL:blocked atomically:YES]);
    assert(!WUMCacheObserve(blocked,@"A",Item(@"1",@"x"),100,&e)); assert([bad isEqual:[NSData dataWithContentsOfURL:blocked]]);
    assert([NSFileManager.defaultManager removeItemAtURL:root error:NULL]);
    puts("moments-cache production tests passed: normalization, pagination, dedup, isolation, retention, corrupt-index and failed-write preservation");
} return 0; }
