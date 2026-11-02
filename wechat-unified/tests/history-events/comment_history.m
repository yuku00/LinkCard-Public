#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "MomentsCacheLogic.h"
#include <assert.h>
static NSUInteger checks;
#define CHECK(x) do { checks++; assert((x)); } while(0)
// No UIKit/real WeChat: production trampolines are extracted verbatim by the runner.
@interface UIViewController : NSObject @end
@implementation UIViewController @end
static char bindingKey,commentCompletionDepthKey;
static IMP commentDeleteFinished;
static BOOL bound=YES,originalReturned,failOriginal,switchBinding;
static NSUInteger originalCalls,refreshes;
static uint64_t received;
static id expectedComment,expectedParent;
static NSURL *root;
static NSArray *visible;
static BOOL Bound(id object) { return bound; }
static void ObserveDisplayedComments(UIViewController *o, NSNumber *code) {
    if([objc_getAssociatedObject(o,&commentCompletionDepthKey) unsignedIntegerValue]) return;
    CHECK(originalReturned); CHECK([code isEqual:@0]); refreshes++;
    CHECK(WUMCacheSaveCommentCompletion(root,@"account",@"owner",@"99",code.longLongValue,visible,200,^BOOL{ return YES; },NULL));
}
#include "CommentCompletion.inc"
static void OriginalBody(UIViewController *o,uint64_t ret,id cid,id did) {
    originalCalls++; received=ret; CHECK(cid==expectedComment && did==expectedParent);
    CHECK([objc_getAssociatedObject(o,&commentCompletionDepthKey) unsignedIntegerValue]==1);
    // Simulates the host's synchronous reload while completing; own observer is gated.
    ObserveDisplayedComments(o,nil);
    if(switchBinding) objc_setAssociatedObject(o,&bindingKey,@[@"other",@2],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(failOriginal) [NSException raise:@"host-error" format:@"synthetic"];
    originalReturned=YES;
}
static void OriginalI32(UIViewController *o,SEL s,int32_t r,id c,id d) { OriginalBody(o,(uint64_t)r,c,d); }
static void OriginalU32(UIViewController *o,SEL s,uint32_t r,id c,id d) { OriginalBody(o,r,c,d); }
static void OriginalI64(UIViewController *o,SEL s,int64_t r,id c,id d) { OriginalBody(o,(uint64_t)r,c,d); }
static void OriginalU64(UIViewController *o,SEL s,uint64_t r,id c,id d) { OriginalBody(o,r,c,d); }
static NSDictionary *Row(NSString *cid, NSString *author) { return @{@"id":cid,@"author":author,@"text":@"same body",@"replyTo":@"",@"time":@0}; }
static NSArray *Comments(void) { return [WUMCacheLoad(root,@"account",NULL) firstObject][@"comments"]; }
static NSDictionary *ByID(NSString *cid) { for(NSDictionary *r in Comments()) if([r[@"id"] isEqual:cid]) return r; return nil; }
static NSData *Bytes(void) { return [NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"6163636f756e74.plist"]]; }
static void States(void) {
    BOOL (^yes)(void)=^BOOL{ return YES; };
    visible=@[Row(@"c32:7",@"self"),Row(@"c64:7",@"friend")];
    CHECK(!WUMCacheSaveCommentCompletion(root,@"account",@"owner",@"99",0,visible,100,yes,NULL));
    CHECK(!Comments().count); // Completion cannot invent an unseen parent.
    CHECK(WUMCacheObserve(root,@"account",WUMCacheNormalize(@"99",@"owner",@"visible parent"),100,NULL));
    CHECK(WUMCacheSaveComments(root,@"account",@"owner",@"99",visible,101,yes,NULL));
    CHECK(Comments().count==2); CHECK([ByID(@"c32:7")[@"visibility"] isEqual:@"visibleSnapshot"]);
    NSData *before=Bytes();
    CHECK(!WUMCacheSaveCommentCompletion(root,@"account",@"owner",@"99",1,@[],110,yes,NULL)); CHECK([Bytes() isEqual:before]);
    CHECK(!WUMCacheSaveCommentCompletion(root,@"account",@"owner",@"99",-1,@[],110,yes,NULL)); CHECK([Bytes() isEqual:before]);
    CHECK(!WUMCacheSaveCommentCompletion(root,@"account",@"owner",@"99",INT64_C(1)<<32,@[],110,yes,NULL)); CHECK([Bytes() isEqual:before]);
    CHECK(!WUMCacheSaveCommentCompletion(root,@"other",@"owner",@"99",0,@[],110,yes,NULL)); CHECK([Bytes() isEqual:before]);
    CHECK(!WUMCacheSaveCommentCompletion(root,@"account",@"owner",@"100",0,@[],110,yes,NULL)); CHECK([Bytes() isEqual:before]);
    CHECK(!WUMCacheSaveCommentCompletion(root,@"account",@"other-owner",@"99",0,@[],110,yes,NULL)); CHECK([Bytes() isEqual:before]);
    CHECK(!WUMCacheSaveCommentCompletion(root,@"account",@"owner",@"99",0,@[],110,^BOOL{ return NO; },NULL)); CHECK([Bytes() isEqual:before]);
    CHECK(WUMCacheSaveCommentCompletion(root,@"account",@"owner",@"99",0,@[],111,yes,NULL));
    for(NSDictionary *r in Comments()) { CHECK([r[@"visibility"] isEqual:@"historical"]); CHECK([r[@"time"] isEqual:@0]); CHECK(!r[@"deletedAt"]); }
    CHECK([WUMCacheCommentStateText(ByID(@"c32:7")) containsString:@"真实删除未确认"]);
    CHECK([WUMCacheCommentStateText(ByID(@"c32:7")) containsString:@"创建/删除时间未知"]);
    CHECK(WUMCacheSaveComments(root,@"account",@"owner",@"99",@[visible[0]],112,yes,NULL));
    CHECK([ByID(@"c32:7")[@"visibility"] isEqual:@"visibleSnapshot"]); CHECK([ByID(@"c64:7")[@"visibility"] isEqual:@"historical"]); CHECK(Comments().count==2);
    // Same decimal/body but different namespace/author cannot clear another mark.
    CHECK(WUMCacheSaveComments(root,@"account",@"owner",@"99",@[Row(@"c64:7",@"new-author")],113,yes,NULL));
    CHECK(Comments().count==3); CHECK([ByID(@"c32:7")[@"visibility"] isEqual:@"historical"]);
    CHECK(WUMCacheSaveComments(root,@"account",@"owner",@"99",@[Row(@"legacy-opaque",@"self")],114,yes,NULL));
    CHECK([ByID(@"legacy-opaque")[@"visibility"] isEqual:@"historical"]);
}
static void Callbacks(void) {
    UIViewController *v=[UIViewController new]; SEL selector=NSSelectorFromString(@"onCommentItemDeleteFinished:commentItemID:dataItemID:");
    expectedComment=[NSObject new]; expectedParent=[NSObject new]; visible=@[];
    IMP originals[]={(IMP)OriginalI32,(IMP)OriginalU32,(IMP)OriginalI64,(IMP)OriginalU64};
    for(NSUInteger width=0;width<4;width++) for(NSUInteger mode=0;mode<4;mode++) {
        commentDeleteFinished=originals[width]; originalReturned=NO; switchBinding=mode==2; bound=mode!=3;
        objc_setAssociatedObject(v,&bindingKey,@[@"account",@1],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSUInteger prior=refreshes, calls=originalCalls; NSData *before=Bytes(); uint64_t ret=mode==1?(width>=2?(UINT64_C(1)<<32):1):0;
        switch(width) {
            case 0: CommentFinishedI32(v,selector,(int32_t)ret,expectedComment,expectedParent); break;
            case 1: CommentFinishedU32(v,selector,(uint32_t)ret,expectedComment,expectedParent); break;
            case 2: CommentFinishedI64(v,selector,(int64_t)ret,expectedComment,expectedParent); break;
            case 3: CommentFinishedU64(v,selector,ret,expectedComment,expectedParent); break;
        }
        CHECK(originalCalls==calls+1 && originalReturned && received==ret); CHECK(refreshes==prior+(mode==0?1:0));
        CHECK([objc_getAssociatedObject(v,&commentCompletionDepthKey) unsignedIntegerValue]==0);
        if(mode!=0) CHECK([Bytes() isEqual:before]);
    }
    commentDeleteFinished=(IMP)OriginalI64; failOriginal=YES; switchBinding=NO; bound=YES; originalReturned=NO;
    NSData *before=Bytes(); BOOL threw=NO;
    @try { CommentFinishedI64(v,selector,0,expectedComment,expectedParent); } @catch(NSException *e) { threw=YES; }
    CHECK(threw && !originalReturned && [Bytes() isEqual:before]); CHECK([objc_getAssociatedObject(v,&commentCompletionDepthKey) unsignedIntegerValue]==0);
}
int main(void) { @autoreleasepool {
    root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    States(); Callbacks(); [NSFileManager.defaultManager removeItemAtURL:root error:NULL];
    printf("history-events production cache/trampoline: %lu assertions\n",(unsigned long)checks);
} return 0; }
