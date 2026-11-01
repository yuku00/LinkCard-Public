#import <Foundation/Foundation.h>
#import "HomeLogic.h"
#import "GroupLogic.h"
#include <assert.h>
#include <stdio.h>
int main(void) { @autoreleasepool {
    NSDictionary *base=WUEmptyHomeGroups(); assert(WUValidHomeGroups(base));
    assert([WUHomeKind(@"alice",NO,NO,YES) isEqual:@"private"]);
    assert([WUHomeKind(@"a@chatroom",NO,NO,YES) isEqual:@"chatroom"]);
    assert([WUHomeKind(@"a@im.chatroom",NO,NO,NO) isEqual:@"chatroom"]);
    assert([WUHomeKind(@"chatroom_session_box",NO,NO,NO) isEqual:@"chatroom"]);
    assert([WUHomeKind(@"gh_test",NO,NO,YES) isEqual:@"other"]);
    assert([WUHomeKind(@"x@openim",NO,NO,YES) isEqual:@"other"]);
    assert([WUHomeKind(@"brandsessionholder",NO,NO,YES) isEqual:@"other"]);
    assert([WUHomeKind(@"brandservicesessionholder",NO,NO,YES) isEqual:@"other"]);
    assert([WUHomeKind(@"system",NO,NO,NO) isEqual:@"other"]);
    assert(WUHomeKind(@"",NO,NO,YES)==nil);
    NSDictionary *a=@{@"username":@"alice",@"kind":@"private"}, *g=@{@"username":@"g@chatroom",@"kind":@"chatroom"}, *o=@{@"username":@"gh_test",@"kind":@"other"};
    NSObject *pa=[NSObject new], *pg=[NSObject new], *po=[NSObject new];
    NSArray *sources=@[@[pa],@[pa,pg],@[po]], *rows=@[@[a],@[a,g],@[o]];
    NSMutableDictionary *s=[base mutableCopy]; s[@"enabled"]=@YES; s[@"selected"]=@"chatroom";
    NSDictionary *p=WUHomeProjection(sources,rows,s,9);
    assert([p[@"arrays"][0] count]==0); assert([p[@"arrays"][1] count]==1); assert(p[@"arrays"][1][0]==pg); assert([p[@"topCount"] unsignedIntegerValue]==1);
    s[@"selected"]=@"private"; p=WUHomeProjection(sources,rows,s,9); assert(p[@"arrays"][0][0]==pa); assert(p[@"arrays"][1][0]==pa); assert([p[@"arrays"][2] count]==0);
    s[@"selected"]=@"other"; p=WUHomeProjection(sources,rows,s,9); assert(p[@"arrays"][2][0]==po); assert([p[@"topCount"] unsignedIntegerValue]==0);
    s[@"enabled"]=@NO; p=WUHomeProjection(sources,rows,s,9); assert([p[@"arrays"] isEqual:sources]); assert([p[@"topCount"] unsignedIntegerValue]==9);
    s[@"enabled"]=@YES; s[@"selected"]=@"all"; p=WUHomeProjection(sources,rows,s,9); assert([p[@"arrays"] isEqual:sources]); assert([p[@"topCount"] unsignedIntegerValue]==9);
    NSString *gid=@"11111111-1111-4111-8111-111111111111"; s[@"groups"]=@[@{@"id":gid,@"name":@"Family"}]; s[@"membership"]=@{@"alice":gid}; s[@"selected"]=gid;
    assert(WUValidHomeGroups(s)); p=WUHomeProjection(sources,rows,s,9); assert(p[@"arrays"][0][0]==pa); assert([p[@"arrays"][1] count]==1);
    NSDictionary *removed=WURemoveHomeGroup(s,gid); assert([removed[@"selected"] isEqual:@"all"]); assert([removed[@"membership"] count]==0); assert([s[@"membership"] count]==1);
    NSDictionary *accounts=@{@"A":@{@"home":s},@"B":@{@"home":base}}; assert(WUValidAccountOptions(accounts)); assert([WUHomeProjection(sources,rows,accounts[@"B"][@"home"],9)[@"arrays"] isEqual:sources]);
    assert(WUHomeIndexes(@[a,a],s)==nil); assert(WUHomeIndexes(@[@{@"username":@"",@"kind":@"private"}],s)==nil);
    assert(WUHomeProjection(sources,@[@[g],@[a],@[o]],s,9)==nil);
    assert(WUHomeProjection(sources,@[@[a],@[a,g],@[a]],s,9)==nil);
    NSMutableDictionary *bad=[s mutableCopy]; bad[@"selected"]=@"missing"; assert(!WUValidHomeGroups(bad));
    bad=[s mutableCopy]; bad[@"membership"]=@{@"alice":@"all"}; assert(!WUValidHomeGroups(bad));
    assert(sources[0][0]==pa && sources[1][1]==pg && sources[2][0]==po);
    puts("HomeLogic: classification, original-object indexes, collapsed pins, counts, restoration, custom deletion and account isolation passed");
} return 0; }
