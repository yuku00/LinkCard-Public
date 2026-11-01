#import <Foundation/Foundation.h>
#import "GroupLogic.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSString *a=@"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", *b=@"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", *gid=@"11111111-1111-4111-8111-111111111111";
    NSDictionary *base=WUEmptyEmojiGroups();
    assert(WUValidAccountOptions(@{}));
    assert(WUValidAccountOptions(@{@"account-A":@{@"emoji":base,@"toolbar":@[]}}));
    assert(!WUValidAccountOptions(@{@"":@{}}));
    assert(!WUValidAccountOptions(@{@"A":@{@"unknown":@YES}}));
    // Unsupported actions still reject; repository is now an explicitly implemented manual action.
    assert(!WUValidAccountOptions(@{@"A":@{@"toolbar":@[@"autoReply"]}}));
    assert(WUValidAccountOptions(@{@"A":@{@"toolbar":@[@"repository"]}}));
    assert(WUValidAccountOptions(@{@"A":@{@"toolbar":@[@"emojiSave"]}}));
    assert(!WUValidAccountOptions(@{@"A":@{@"toolbar":@[@"search",@"search"]}}));
    assert(WUValidMD5(a)); assert(!WUValidMD5(@"bad")); assert(!WUValidMD5(@"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"));
    NSArray *ids=@[a,@"custom_emoticon_pid",b];
    assert([WUEmojiIndexes(ids,base) isEqual:(@[@0,@1,@2])]);
    NSMutableDictionary *s=[base mutableCopy]; s[@"enabled"]=@YES; s[@"groups"]=@[@{@"id":gid,@"name":@"收藏"}]; s[@"membership"]=@{a:gid}; s[@"selected"]=gid;
    assert(WUValidAccountOptions(@{@"A":@{@"emoji":s}}));
    assert([WUEmojiIndexes(ids,s) isEqual:(@[@0,@1])]);
    assert([ids isEqual:(@[a,@"custom_emoticon_pid",b])]); // Host array unchanged.
    s[@"selected"]=@"__ungrouped__";
    assert([WUEmojiIndexes(ids,s) isEqual:(@[@1,@2])]);
    assert(WUEmojiIndexes(@[@"unidentified"],s)==nil);
    s[@"selected"]=@"__all__"; assert([WUEmojiIndexes(ids,s) isEqual:(@[@0,@1,@2])]);
    s[@"selected"]=gid; s[@"enabled"]=@NO; assert([WUEmojiIndexes(ids,s) isEqual:(@[@0,@1,@2])]);
    s[@"enabled"]=@YES;
    NSDictionary *removed=WURemoveEmojiGroup(s,gid);
    assert([removed[@"groups"] count]==0); assert([removed[@"membership"] count]==0); assert([removed[@"selected"] isEqual:@"__all__"]);
    assert([s[@"membership"] count]==1); assert([s[@"groups"] count]==1);
    assert([WURemoveEmojiGroup(s,@"__all__") isEqual:s]);
    NSDictionary *accounts=@{@"A":@{@"emoji":s},@"B":@{@"emoji":base}};
    assert(WUValidAccountOptions(accounts)); assert([WUEmojiIndexes(ids,accounts[@"B"][@"emoji"]) count]==3);
    assert([WUEmojiIndexes(ids,accounts[@"A"][@"emoji"]) count]==2);
    NSMutableDictionary *bad=[s mutableCopy]; bad[@"selected"]=@"missing"; assert(!WUValidAccountOptions(@{@"A":@{@"emoji":bad}}));
    bad=[s mutableCopy]; bad[@"membership"]=@{a:@"missing"}; assert(!WUValidAccountOptions(@{@"A":@{@"emoji":bad}}));
    bad=[s mutableCopy]; bad[@"groups"]=@[@{@"id":gid,@"name":@""}]; assert(!WUValidAccountOptions(@{@"A":@{@"emoji":bad}}));
    bad=[s mutableCopy]; bad[@"groups"]=@[@{@"id":gid,@"name":@"One"},@{@"id":gid,@"name":@"Two"}]; assert(!WUValidAccountOptions(@{@"A":@{@"emoji":bad}}));
    assert([WUToolbarActions(@[@"search",@"autoReply",@"stats",@"search",@"settings"]) isEqual:(@[@"search",@"stats",@"settings"])]);
    assert([WUToolbarActions(@[@"repository",@"search",@"repository"]) isEqual:(@[@"repository",@"search"])]);
    assert(WUToolbarActions(NSNull.null).count==0);
    puts("GroupLogic: 35 native assertions passed (filter, placeholder, deletion, isolation, validation, manual toolbar allowlist)");
} return 0; }
