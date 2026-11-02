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
    assert(WUValidAccountOptions(@{@"A":@{@"toolbar":@[@"messageLinks",@"imageEmoji",@"emoticonLibrary"]}}));
    assert([WUToolbarActions(@[@"emoticonLibrary",@"emoticonLibrary",@"imageEmoji"]) isEqual:(@[@"emoticonLibrary",@"imageEmoji"])]);
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
    NSString *gid2=@"22222222-2222-4222-8222-222222222222", *gid3=@"33333333-3333-4333-8333-333333333333";
    NSMutableDictionary *ordered=[s mutableCopy];
    ordered[@"groups"]=@[@{@"id":gid,@"name":@"一"},@{@"id":gid2,@"name":@"二"},@{@"id":gid3,@"name":@"三"}];
    NSDictionary *renamed=WURenameEmojiGroup(ordered,gid2,@"  改名  ");
    assert([renamed[@"groups"][1][@"name"] isEqual:@"改名"]);
    assert([ordered[@"groups"][1][@"name"] isEqual:@"二"]);
    assert([renamed[@"membership"] isEqual:ordered[@"membership"]]);
    assert([renamed[@"selected"] isEqual:gid]);
    assert(WURenameEmojiGroup(ordered,gid,@"  \n ")==nil);
    assert(WURenameEmojiGroup(ordered,@"missing",@"不会创建")==nil);
    assert(WURenameEmojiGroup(ordered,@"__all__",@"不变")==nil);
    assert(WURenameEmojiGroup(ordered,gid,[NSString stringWithFormat:@"%@x",[@"a" stringByPaddingToLength:40 withString:@"a" startingAtIndex:0]])==nil);
    NSDictionary *moved=WUMoveEmojiGroup(renamed,gid3,0);
    assert([moved[@"groups"][0][@"id"] isEqual:gid3]);
    assert([moved[@"groups"][1][@"id"] isEqual:gid]);
    assert([moved[@"groups"][2][@"id"] isEqual:gid2]);
    assert([moved[@"membership"] isEqual:ordered[@"membership"]]);
    assert([moved[@"selected"] isEqual:gid]);
    assert([WUEmojiIndexes(ids,moved) isEqual:WUEmojiIndexes(ids,ordered)]);
    assert(WUMoveEmojiGroup(ordered,gid,-1)==nil);
    assert(WUMoveEmojiGroup(ordered,gid,3)==nil);
    assert(WUMoveEmojiGroup(ordered,@"missing",1)==nil);
    assert(WUMoveEmojiGroup(ordered,@"__ungrouped__",1)==nil);
    assert([WUMoveEmojiGroup(ordered,gid,0) isEqual:ordered]);
    assert(WURenameEmojiGroup(bad,gid,@"拒绝坏结构")==nil);
    assert(WUMoveEmojiGroup(bad,gid,0)==nil);
    NSDictionary *otherAccount=@{@"A":@{@"emoji":ordered},@"B":@{@"emoji":base}};
    NSMutableDictionary *withRename=[otherAccount mutableCopy]; withRename[@"A"]=@{@"emoji":renamed};
    assert([withRename[@"B"] isEqual:otherAccount[@"B"]]);
    assert(WUValidAccountOptions(withRename));
    puts("GroupLogic: native assertions passed (filter, placeholder, deletion, stable-ID rename/reorder, isolation, validation, manual toolbar allowlist)");
} return 0; }
