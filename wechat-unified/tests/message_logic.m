#import <Foundation/Foundation.h>
#import "MessageLogic.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSString *xml=@"<sysmsg type='revokemsg'><revokemsg><session><![CDATA[room@chatroom]]></session><newmsgid>123</newmsgid></revokemsg></sysmsg>";
    assert([WURevokeFields(xml)[@"id"] isEqual:@123]);
    assert([WURevokeFields(xml)[@"session"] isEqual:@"room@chatroom"]);
    for(NSString *bad in @[@"",@"<bad>",@"<sysmsg type='revokemsg'><revokemsg><session>x</session><newmsgid>-1</newmsgid></revokemsg></sysmsg>",@"<sysmsg type='revokemsg'><revokemsg><session>x</session><newmsgid>9223372036854775808</newmsgid></revokemsg></sysmsg>",@"<!DOCTYPE x [<!ENTITY a SYSTEM 'file:///etc/passwd'>]><sysmsg/>",@"<sysmsg type='revokemsg'><revokemsg><session>x</session><session>y</session><newmsgid>1</newmsgid></revokemsg></sysmsg>"]) assert(WURevokeFields(bad)==nil);
    assert(!WUOwnMessage(@"",@"room@chatroom",@"",@""));
    assert(WUOwnMessage(@"me",@"room@chatroom",@"room@chatroom",@"me"));
    assert(!WUOwnMessage(@"me",@"other",@"other",@"me"));
    NSMutableDictionary *m=[@{@"from":@"me",@"real":@"",@"id":@7,@"time":@100,@"type":@1} mutableCopy];
    assert(WURevokeEligible(@"me",@"peer",m,220)); assert(!WURevokeEligible(@"me",@"peer",m,221)); assert(!WURevokeEligible(@"me",@"peer",m,99));
    m[@"id"]=@0; assert(!WURevokeEligible(@"me",@"peer",m,110)); m[@"id"]=@7; m[@"from"]=@"other"; assert(!WURevokeEligible(@"me",@"peer",m,110));
    NSDictionary *a=@{@"session":@"s",@"sender":@"a",@"time":@100};
    NSMutableDictionary *b=[a mutableCopy]; b[@"time"]=@399; assert(WUGroupAdjacent(a,b)); b[@"time"]=@400; assert(!WUGroupAdjacent(a,b)); b[@"time"]=@100; assert(WUGroupAdjacent(a,b)); b[@"separator"]=@YES; assert(!WUGroupAdjacent(a,b)); [b removeObjectForKey:@"separator"]; b[@"session"]=@"other"; assert(!WUGroupAdjacent(a,b));
    puts("MessageLogic: 21 native assertions passed");
} return 0; }
