#import <Foundation/Foundation.h>
#import "LinkLogic.h"
#import "RepeatOptions.h"
#import "GroupLogic.h"
#include <assert.h>
#include <stdio.h>
static NSArray *Links(NSUInteger type,NSString *content) { return WULinkCandidates(@[@{@"type":@(type),@"content":content}]); }
int main(void) { @autoreleasepool {
    assert(WULinkSafeURL(@"https://example.com/a?q=1"));
    for(NSString *s in @[@"javascript:alert(1)",@"file:///etc/passwd",@"data:text/html,a",@"ftp://example.com",@"https://user:pass@example.com",@"https://@example.com",@"https://example.com/%0Aevil",@"https://example.com:65536/",@"https://example.com:0/",@"https://example.com/\\evil",@"https://example.com/\u202eevil",@"https://exa mple.com",@"https://example.com/%zz"]) assert(!WULinkSafeURL(s));
    NSArray *plain=Links(1,@"打开 https://example.com/a ，再看 https://example.org/b ，重复 https://example.com/a");
    assert(plain.count==2); assert([plain[0][@"source"] isEqual:@"消息 1 · 文本"]);
    assert(!Links(47,@"https://example.com").count);
    assert(!Links(3,@"https://example.com").count);
    NSArray *xml=Links(49,@"<msg><appmsg><url><![CDATA[https://example.com/?a=1&b=2]]></url><des>https://ignored.example</des><thumburl>https://thumb.example</thumburl></appmsg></msg>");
    assert(xml.count==1 && [[xml[0][@"url"] host] isEqual:@"example.com"]);
    assert(!Links(49,@"<msg><appmsg url='https://ignored.example'><des>https://ignored.example</des></appmsg></msg>").count);
    assert(!Links(49,@"<msg><appmsg><url>https://one.example</url><url>https://two.example</url></appmsg></msg>").count);
    assert(!Links(49,@"<msg><appmsg><url>https://example.com").count);
    assert(!Links(49,@"<!DOCTYPE msg [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><msg><appmsg><url>&x;</url></appmsg></msg>").count);
    assert(!Links(49,@"<msg><appmsg><url>https://example.com<b>/x</b></url></appmsg></msg>").count);
    assert(!Links(49,@"<other><msg><appmsg><url>https://example.com</url></appmsg></msg></other>").count);
    assert(!Links(1,[@"x" stringByPaddingToLength:8193 withString:@"x" startingAtIndex:0]).count);
    NSMutableArray *many=[NSMutableArray array]; for(int i=0;i<21;i++) [many addObject:@{@"type":@1,@"content":@"https://example.com"}]; assert(!WULinkCandidates(many).count);
    NSURL *risk=[NSURL URLWithString:@"https://weixin110.qq.com/cgi-bin/mmspamsupport-bin/newredirectconfirmcgi?url=https%3A%2F%2Foriginal.example%2Fa%3Fx%3D1%26y%3D2"];
    NSDictionary *resolved=WULinkDestination(risk); assert([resolved[@"risk"] boolValue]); assert([[resolved[@"url"] absoluteString] isEqual:@"https://original.example/a?x=1&y=2"]);
    assert(WULinkDestination([NSURL URLWithString:@"https://weixin110.qq.com/unknown?url=https://example.com"])[@"error"]);
    assert(WULinkDestination([NSURL URLWithString:@"https://weixin110.qq.com/cgi-bin/mmspamsupport-bin/newredirectconfirmcgi"])[@"error"]);
    assert(WULinkDestination([NSURL URLWithString:@"https://weixin110.qq.com/cgi-bin/mmspamsupport-bin/newredirectconfirmcgi?url=javascript%3Aalert(1)"])[@"error"]);
    assert(WULinkDestination([NSURL URLWithString:@"https://weixin110.qq.com/cgi-bin/mmspamsupport-bin/newredirectconfirmcgi?url=https://a.example&url=https://b.example"])[@"error"]);
    assert(WULinkDestination([NSURL URLWithString:@"https://weixin110.qq.com/cgi-bin/mmspamsupport-bin/newredirectconfirmcgi?url=https%253A%252F%252Fexample.com"])[@"error"]);
    assert(![WULinkDestination([NSURL URLWithString:@"https://example.com/?url=https://other.example"])[@"risk"] boolValue]);
    NSDictionary *defaults=WURepeatDefaults(); assert(WUValidRepeatOptions(defaults));
    assert([defaults[@"imageButton"] boolValue] && [defaults[@"themeIcon"] boolValue] && [defaults[@"longDownload"] boolValue]);
    for(NSString *key in @[@"normalRepeat",@"themeIcon",@"imageButton",@"longDownload"]) { NSMutableDictionary *o=[defaults mutableCopy]; o[key]=@NO; assert(WUValidRepeatOptions(o)); }
    for(NSString *key in @[@"menuRepeat",@"fileOnly"]) { NSMutableDictionary *o=[defaults mutableCopy]; o[key]=@YES; assert(!WUValidRepeatOptions(o)); }
    NSMutableDictionary *o=[defaults mutableCopy]; o[@"userIcon"]=@"../../private"; assert(!WUValidRepeatOptions(o)); o[@"userIcon"]=NSUUID.UUID.UUIDString; assert(WUValidRepeatOptions(o)); o[@"longDownload"]=@2; assert(!WUValidRepeatOptions(o));
    assert([WUToolbarActions(@[@"messageLinks",@"messageLinks",@"unknown"]) isEqual:@[@"messageLinks"]]);
    puts("PASS selected-message link parsing, risk target refusal, repeat defaults and toolbar policy");
} return 0; }
