#import <Foundation/Foundation.h>
#import "RepositoryLogic.h"
static NSUInteger checks=0;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { NSLog(@"FAIL line %d",__LINE__); abort(); } } while(0)
@interface Sender : NSObject
@property(nonatomic) NSUInteger calls;
@property(nonatomic) BOOL raises;
@property(nonatomic,strong) id first;
@property(nonatomic,strong) id second;
- (BOOL)sendMsg:(id)text toContactUsrName:(id)target;
- (void)ForwardMsg:(id)wrap ToContact:(id)contact;
- (int)wrong:(id)a target:(id)b;
- (void)width:(unsigned int)n target:(id)b;
@end
@implementation Sender
- (BOOL)sendMsg:(id)text toContactUsrName:(id)target { self.calls++; self.first=text; self.second=target; if(self.raises) [NSException raise:@"fixture" format:@"after submission"]; return NO; }
- (void)ForwardMsg:(id)wrap ToContact:(id)contact { self.calls++; self.first=wrap; self.second=contact; }
- (int)wrong:(id)a target:(id)b { self.calls++; return 1; }
- (void)width:(unsigned int)n target:(id)b { self.calls++; }
@end
int main(void) { @autoreleasepool {
    NSURL *dir=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES]; NSError *e=nil;
    NSDictionary *text=@{@"kind":@"text",@"text":@"独立文本\n第二行"};
    NSDictionary *identity=@{@"from":@"a",@"to":@"filehelper",@"real":@"",@"id":@123,@"local":@1,@"time":@2,@"type":@3};
    NSDictionary *ref=@{@"kind":@"reference",@"identity":identity};
    NSDictionary *entry=@{@"id":NSUUID.UUID.UUIDString,@"name":@"备注",@"parts":@[text,ref]};
    CHECK(WURepositoryValid(@[entry])); CHECK(WURepositoryValid(@[]));
    CHECK(!WURepositoryValid(@{})); CHECK(!WURepositoryValid(@[entry,entry]));
    NSMutableDictionary *bad=[entry mutableCopy]; bad[@"name"]=@""; CHECK(!WURepositoryValid(@[bad]));
    bad=[entry mutableCopy]; bad[@"parts"]=@[]; CHECK(!WURepositoryValid(@[bad]));
    bad[@"parts"]=@[@{@"kind":@"reference",@"identity":@{}}]; CHECK(!WURepositoryValid(@[bad]));
    bad[@"parts"]=@[@{@"kind":@"text",@"text":[@"x" stringByPaddingToLength:10001 withString:@"x" startingAtIndex:0]}]; CHECK(!WURepositoryValid(@[bad]));
    NSMutableArray *large=[NSMutableArray array]; for(NSUInteger i=0;i<201;i++) [large addObject:@{@"id":NSUUID.UUID.UUIDString,@"name":@"n",@"parts":@[text]}]; CHECK(!WURepositoryValid(large));
    NSMutableArray *parts=[NSMutableArray array]; for(NSUInteger i=0;i<51;i++) [parts addObject:text]; bad[@"parts"]=parts; CHECK(!WURepositoryValid(@[bad]));
    CHECK([WURepositoryLoad(dir,@"a",&e) isEqual:@[]]); CHECK(WURepositorySave(dir,@"a",@[entry],&e));
    CHECK([WURepositoryLoad(dir,@"a",&e) isEqual:@[entry]]); CHECK([WURepositoryLoad(dir,@"b",&e) isEqual:@[]]);
    NSMutableArray *oversize=[NSMutableArray array];
    for(NSUInteger i=0;i<120;i++) { NSString *body=[[NSString stringWithFormat:@"%lu:",(unsigned long)i] stringByPaddingToLength:10000 withString:@"X" startingAtIndex:0]; [oversize addObject:@{@"id":NSUUID.UUID.UUIDString,@"name":@"large",@"parts":@[@{@"kind":@"text",@"text":body}]}]; }
    CHECK(!WURepositorySave(dir,@"a",oversize,&e)); CHECK([WURepositoryLoad(dir,@"a",&e) isEqual:@[entry]]);
    CHECK(WURepositorySave(dir,@"b",@[],&e)); CHECK([WURepositoryLoad(dir,@"a",&e) isEqual:@[entry]]);
    CHECK(!WURepositorySave(dir,@"a",@[bad],&e)); CHECK([WURepositoryLoad(dir,@"a",&e) isEqual:@[entry]]);
    CHECK(!WURepositorySave(dir,@"",@[],&e)); CHECK(!WURepositoryLoad(dir,@"",&e));
    CHECK(WURepositorySave(dir,@"../escaped",@[entry],&e)); CHECK([WURepositoryLoad(dir,@"../escaped",&e) isEqual:@[entry]]);
    CHECK(WURepositorySave(dir,@"a",@[],&e)); CHECK([WURepositoryLoad(dir,@"a",&e) isEqual:@[]]);
    NSURL *file=[dir URLByAppendingPathComponent:@"61.plist"]; CHECK([[@"bad plist" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:file atomically:YES]); CHECK(WURepositoryLoad(dir,@"a",&e)==nil);
    NSData *before=[NSData dataWithContentsOfURL:file]; CHECK(!WURepositorySave(dir,@"a",@[bad],&e)); CHECK([before isEqual:[NSData dataWithContentsOfURL:file]]);
    NSURL *blocked=[dir URLByAppendingPathComponent:@"blocked"]; CHECK([before writeToURL:blocked atomically:YES]); CHECK(!WURepositorySave(blocked,@"a",@[entry],&e));
    Sender *sender=[Sender new]; CHECK(WURepositoryCanInvoke(sender,@"sendMsg:toContactUsrName:")); CHECK(WURepositoryCanInvoke(sender,@"ForwardMsg:ToContact:"));
    CHECK(!WURepositoryCanInvoke(sender,@"wrong:target:")); CHECK(!WURepositoryCanInvoke(sender,@"width:target:")); CHECK(!WURepositoryCanInvoke(sender,@"missing:target:"));
    CHECK([WURepositoryInvoke(sender,@"wrong:target:",@"a",@"b") hasPrefix:@"失败"]); CHECK(sender.calls==0);
    CHECK([WURepositoryInvoke(sender,@"sendMsg:toContactUsrName:",@"text",@"target") hasPrefix:@"已请求"]); CHECK(sender.calls==1); CHECK([sender.first isEqual:@"text"] && [sender.second isEqual:@"target"]);
    sender.raises=YES; CHECK([WURepositoryInvoke(sender,@"sendMsg:toContactUsrName:",@"text",@"target") hasPrefix:@"未知"]); CHECK(sender.calls==2);
    CHECK([WURepositoryInvoke(sender,@"ForwardMsg:ToContact:",ref,@"contact") hasPrefix:@"已请求"]); CHECK(sender.calls==3 && sender.first==ref);
    CHECK([WURepositoryInvoke(sender,@"ForwardMsg:ToContact:",nil,@"contact") hasPrefix:@"失败"]); CHECK(sender.calls==3);
    CHECK([NSFileManager.defaultManager removeItemAtURL:dir error:&e]);
    printf("Repository production logic and native host mocks: %lu assertions passed\n",(unsigned long)checks);
} return 0; }
