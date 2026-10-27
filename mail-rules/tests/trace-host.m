#import <Foundation/Foundation.h>
#import "Trace.h"
#import "NativeCore.h"
#import <assert.h>
static MR5PredicateTransform Deferred;
static NSUInteger Calls;
static id Factory(id cls,SEL cmd,id boxes,id repo,BOOL oldest,BOOL display,id sort,MR5PredicateTransform transform,id ignore) {
    Calls++;Deferred=[transform copy];return repo;
}
static BOOL Has(NSString *stage,NSString *status) {
    for(NSDictionary *e in MRDSnapshot()[@"events"])if([e[@"stage"] isEqual:stage] && [e[@"status"] isEqual:status])return YES;
    return NO;
}
int main(void){@autoreleasepool {
    assert(!MRDActive());MRD(@"ui.entry",@"success",@"entered",nil,nil);assert([MRDSnapshot()[@"events"] count]==0);
    MRDDeclare(@"install.query",@"_reloadDataSource","v16@0:8","v24@0:8@16",NO);
    MRDStart();assert(MRDActive() && !MRDCanSubmit());assert(Has(@"install.query",@"skipped"));
    NSObject *owner=[NSObject new];NSNumber *a=MRDAccount(@"private-account-name@example.invalid");assert(a.unsignedIntegerValue==1);assert([a isEqual:MRDAccount(@"private-account-name@example.invalid")]);assert(![a isEqual:MRDAccount(@"another-account")]);
    // Synthetic host injects events at the API seam; source coverage separately verifies actual UI/hook callsites.
    NSArray *features=@[@"ui.entry",@"ui.click",@"ui.transition",@"ui.lifecycle",@"scope.resolve",@"sender.factory",@"sender.selftest",@"rule.edit",@"rule.manage",@"rule.save",@"rule.toggle",@"rule.delete",@"reload.request",@"reload.enter",@"reload.local",@"reload.exit",@"thread.path",@"factory.hit",@"list.refresh",@"selection.map",@"selection.item",@"preview.begin",@"preview.end",@"move.open",@"move.delegate",@"move.validate",@"move.perform",@"move.completion",@"create.open",@"create.commit",@"create.completion",@"theme.toggle",@"theme.apply",@"theme.section"];
    for(NSString *stage in features){MRD(stage,@"success",@"test",owner,@{@"accountID":a,@"count":@2});assert(Has(stage,@"success"));}
    MRDTag(@"preview");
    NSError *error=[NSError errorWithDomain:@"secret@example.invalid:/mailbox/path" code:77 userInfo:@{NSLocalizedDescriptionKey:@"TOP_SECRET_BODY_PASSWORD"}];
    MRD(@"error",@"failed",@"TOP_SECRET_BODY_PASSWORD",owner,MRDError(error));
    MRD(@"rule.save",@"failed",@"sync_failed",nil,@{@"path":@"private-account-name@example.invalid",@"body":@"TOP_SECRET_BODY_PASSWORD",@"count":@3});
    MRDAST([NSPredicate predicateWithFormat:@"ANY senderList.stringValue ==[c] %@",@"private-sender@example.invalid"]);
    NSString *text=MRDText(MRDSnapshot());
    for(NSString *secret in @[@"private-account",@"private-sender",@"another-account",@"TOP_SECRET",@"/mailbox/path",@"secret@example"])assert([text rangeOfString:secret].location==NSNotFound);
    assert([text containsString:@"not reached"] && [text containsString:@"senderList.stringValue"] && [text containsString:@"errorCode"]);
    MRD(@"abi",@"failed",@"abi_mismatch",owner,MRDABIFields(@"setDelegate:","v24@0:8@16","v16@0:8"));assert([MRDText(MRDSnapshot()) containsString:@"v24@0:8@16"]);
    __block NSUInteger transformed=0;
    NSPredicate *local=[NSPredicate predicateWithValue:YES];
    MR5PredicateTransform original=^NSPredicate *(NSPredicate *base){transformed++;return base;};
    id result=MR5InvokeFactory(Factory,owner,@selector(description),@[],owner,YES,NO,nil,original,nil,local);
    assert(result==owner && Calls==1);assert(Deferred(local));assert(transformed==1 && Has(@"factory.transform",@"success") && Has(@"query.generated",@"success"));
    for(NSUInteger i=0;i<1200;i++)MRD(@"ui.lifecycle",@"success",@"test",owner,@{@"count":@(i)});
    NSDictionary *capped=MRDSnapshot();assert([capped[@"events"] count]<=856 && [capped[@"dropped"] unsignedIntegerValue]>0);assert(Has(@"rule.save",@"failed"));
    MRDAllowTestSubmit(YES);assert(MRDCanSubmit());MRDAllowTestSubmit(NO);assert(!MRDCanSubmit());
    NSUInteger old=MRDSession();MRDStop();NSUInteger count=[MRDSnapshot()[@"events"] count];MRD(@"rule.save",@"success",@"test",nil,nil);assert(count==[MRDSnapshot()[@"events"] count]);
    MRDControl(@"pending",@"entered",@"share");MRDControl(@"cancelled",@"user_cancel",@"share");assert(Has(@"share.lifecycle",@"cancelled") && !MRDActive());MRDShareError(error);assert(![MRDText(MRDSnapshot()) containsString:@"TOP_SECRET"]);
    MRDStart();assert(MRDSession()!=old && !MRDCanSubmit());MRDAt(old,@"move.completion",@"success",@"test",nil,nil);assert(!Has(@"move.completion",@"success"));
    assert(Deferred(local));assert(!Has(@"query.generated",@"success"));[Deferred release];Deferred=nil;
    assert(MRDAccount(@"new-session-account").unsignedIntegerValue==1);
    MRDClear();assert(!MRDActive() && [MRDSnapshot()[@"events"] count]==0);MRDControl(@"success",@"ok",@"share");assert([MRDSnapshot()[@"events"] count]==0);
    [owner release];puts("PASS trace host: all operation seams, real factory transform/once ownership, explicit opt-in, bounded ring/critical, redaction/AST/ABI, stop/restart/stale callbacks, manual share cancellation and clear");
}return 0;}
