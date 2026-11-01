#import <Foundation/Foundation.h>
#import "MomentsCacheLogic.h"
#import "RepositoryLogic.h"
#import "DraftMediaLogic.h"
#import "GroupLogic.h"
#include <assert.h>
#include <math.h>
static NSDictionary *Item(NSString *tid, NSString *text) { return WUMCacheNormalize(tid,@"friend",text); }
int main(void) { @autoreleasepool {
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
