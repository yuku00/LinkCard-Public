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
@interface RepoTextWrap : NSObject
@property(nonatomic) unsigned int m_uiMessageType, m_uiStatus, m_uiCreateTime;
@property(nonatomic,copy) NSString *m_nsFromUsr, *m_nsToUsr, *m_nsContent;
@end
@implementation RepoTextWrap @end
@interface CMessageMgr : NSObject
@property(nonatomic) NSUInteger calls;
@property(nonatomic) BOOL raises;
@property(nonatomic,strong) id wrap;
@property(nonatomic,copy) NSString *target;
- (void)AddMsg:(id)target MsgWrap:(id)wrap;
@end
@implementation CMessageMgr
- (void)AddMsg:(id)target MsgWrap:(id)wrap { self.calls++; self.target=target; self.wrap=wrap; if(self.raises) [NSException raise:@"fixture" format:@"after AddMsg"]; }
@end
@interface MMNewSessionMgr : NSObject
- (unsigned int)GenSendMsgTime;
@end
@implementation MMNewSessionMgr
- (unsigned int)GenSendMsgTime { return 1234; }
@end
@interface RepoContact : NSObject
@property(nonatomic,copy) NSString *m_nsUsrName;
@end
@implementation RepoContact @end
@interface CContactMgr : NSObject
@property(nonatomic,strong) RepoContact *contact;
- (id)getContactByName:(id)name;
@end
@implementation CContactMgr
- (id)getContactByName:(id)name { (void)name; return self.contact; }
@end
@interface RepoProxy : NSProxy
@property(nonatomic,strong) id target;
@property(nonatomic) BOOL bad;
+ (instancetype)proxy:(id)target bad:(BOOL)bad;
@end
@implementation RepoProxy
+ (instancetype)proxy:(id)target bad:(BOOL)bad { RepoProxy *p=[RepoProxy alloc]; p.target=target; p.bad=bad; return p; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { if(self.bad && s==@selector(AddMsg:MsgWrap:)) return [NSMethodSignature signatureWithObjCTypes:"B@:@@"]; return [self.target methodSignatureForSelector:s]; }
- (void)forwardInvocation:(NSInvocation *)inv { [inv invokeWithTarget:self.target]; }
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
    NSURL *fresh=[dir URLByAppendingPathComponent:@"new/nested" isDirectory:YES];
    e=nil; CHECK(WURepositoryLoad(fresh,@"账号A",&e)==nil && e); e=nil;
    CHECK(!WURepositorySave(fresh,@"账号A",@[entry],&e)); e=nil;
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:[fresh URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&e]);
    e=nil; CHECK([WURepositoryLoad(fresh,@"账号A",&e) isEqual:@[]]); CHECK(e==nil);
    CHECK(WURepositorySave(fresh,@"账号A",@[entry],&e));
    CHECK([WURepositoryLoad(fresh,@"账号A",&e) isEqual:@[entry]]);
    CHECK([WURepositoryLoad(fresh,@"账号B",&e) isEqual:@[]]);
    CHECK(WURepositorySave(fresh,@"账号B",@[],&e));
    CHECK([WURepositoryLoad(fresh,@"账号A",&e) isEqual:@[entry]]);
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
    NSURL *blocked=[dir URLByAppendingPathComponent:@"blocked"]; CHECK([before writeToURL:blocked atomically:YES]);
    e=nil; CHECK(WURepositoryLoad(blocked,@"a",&e)==nil); CHECK(e!=nil);
    CHECK(!WURepositorySave(blocked,@"a",@[entry],&e));
    NSURL *occupied=[dir URLByAppendingPathComponent:@"63.plist"]; CHECK([NSFileManager.defaultManager createDirectoryAtURL:occupied withIntermediateDirectories:NO attributes:nil error:&e]); CHECK(!WURepositorySave(dir,@"c",@[entry],&e));
    NSData *wrongAccount=[NSPropertyListSerialization dataWithPropertyList:@{@"version":@1,@"account":@"b",@"items":@[entry]} format:NSPropertyListBinaryFormat_v1_0 options:0 error:&e]; CHECK([wrongAccount writeToURL:[dir URLByAppendingPathComponent:@"64.plist"] atomically:YES]); CHECK(WURepositoryLoad(dir,@"d",&e)==nil);
    Sender *sender=[Sender new]; CHECK(WURepositoryCanInvoke(sender,@"sendMsg:toContactUsrName:")); CHECK(WURepositoryCanInvoke(sender,@"ForwardMsg:ToContact:"));
    CHECK(!WURepositoryCanInvoke(sender,@"wrong:target:")); CHECK(!WURepositoryCanInvoke(sender,@"width:target:")); CHECK(!WURepositoryCanInvoke(sender,@"missing:target:"));
    CHECK([WURepositoryInvoke(sender,@"wrong:target:",@"a",@"b") hasPrefix:@"失败"]); CHECK(sender.calls==0);
    CHECK([WURepositoryInvoke(sender,@"sendMsg:toContactUsrName:",@"text",@"target") hasPrefix:@"已请求"]); CHECK(sender.calls==1); CHECK([sender.first isEqual:@"text"] && [sender.second isEqual:@"target"]);
    sender.raises=YES; CHECK([WURepositoryInvoke(sender,@"sendMsg:toContactUsrName:",@"text",@"target") hasPrefix:@"未知"]); CHECK(sender.calls==2);
    CHECK([WURepositoryInvoke(sender,@"ForwardMsg:ToContact:",ref,@"contact") hasPrefix:@"已请求"]); CHECK(sender.calls==3 && sender.first==ref);
    CHECK([WURepositoryInvoke(sender,@"ForwardMsg:ToContact:",nil,@"contact") hasPrefix:@"失败"]); CHECK(sender.calls==3);
    CContactMgr *contacts=[CContactMgr new]; contacts.contact=[RepoContact new]; contacts.contact.m_nsUsrName=@"target";
    CHECK(WURepositoryContact(contacts,@"target")==contacts.contact);
    CHECK(WURepositoryContact([RepoProxy proxy:contacts bad:NO],@"target")==contacts.contact);
    CHECK(!WURepositoryContact([RepoProxy proxy:contacts bad:NO],@"other"));
    CMessageMgr *manager=[CMessageMgr new]; MMNewSessionMgr *clock=[MMNewSessionMgr new];
    RepoTextWrap *message=[RepoTextWrap new]; message.m_uiMessageType=1;
    CHECK([WURepositorySendText(manager,clock,message,@"self",@"target",@"hello",^BOOL{ return YES; }) hasPrefix:@"已请求"]);
    CHECK(manager.calls==1 && manager.wrap==message && [manager.target isEqual:@"target"]);
    CHECK([message.m_nsFromUsr isEqual:@"self"] && [message.m_nsToUsr isEqual:@"target"] && [message.m_nsContent isEqual:@"hello"] && message.m_uiStatus==1 && message.m_uiCreateTime==1234);
    manager=[CMessageMgr new]; message=[RepoTextWrap new]; message.m_uiMessageType=1;
    RepoProxy *managerProxy=[RepoProxy proxy:manager bad:NO], *clockProxy=[RepoProxy proxy:clock bad:NO];
    CHECK([WURepositorySendText(managerProxy,clockProxy,message,@"self",@"target",@"hello",^BOOL{ return YES; }) hasPrefix:@"已请求"] && manager.calls==1);
    manager=[CMessageMgr new]; message=[RepoTextWrap new]; message.m_uiMessageType=1;
    CHECK([WURepositorySendText([RepoProxy proxy:manager bad:YES],clock,message,@"self",@"target",@"hello",^BOOL{ return YES; }) hasPrefix:@"失败"] && manager.calls==0);
    __block NSUInteger contextChecks=0;
    CHECK([WURepositorySendText(manager,clock,message,@"self",@"target",@"hello",^BOOL{ return ++contextChecks<2; }) hasPrefix:@"失败"] && manager.calls==0);
    message.m_uiMessageType=34;
    CHECK([WURepositorySendText(manager,clock,message,@"self",@"target",@"hello",^BOOL{ return YES; }) hasPrefix:@"失败"] && manager.calls==0);
    message.m_uiMessageType=1; manager.raises=YES;
    CHECK([WURepositorySendText(manager,clock,message,@"self",@"target",@"hello",^BOOL{ return YES; }) hasPrefix:@"未知"] && manager.calls==1);
    CHECK([NSFileManager.defaultManager removeItemAtURL:dir error:&e]);
    printf("Repository production logic and native host mocks: %lu assertions passed\n",(unsigned long)checks);
} return 0; }
