#import "MomentsCacheComments.h"
#import "MomentsCacheLogic.h"
#import "WUHostRead.h"
#include <string.h>
static id Get(id o, NSString *s) { return WUHostObject(o,s,nil,NO); }
static NSString *WUCommentIdentifier(id value, NSUInteger digits) {
    if([value isKindOfClass:NSNumber.class]) {
        const char *t=[value objCType];
        if(strlen(t)!=1 || !strchr("iIqQ",t[0]) || [value compare:@0]!=NSOrderedDescending) return nil;
        value=[value stringValue];
    }
    NSString *s=WUHostString(value,digits); if(!s.length) return nil;
    for(NSUInteger i=0;i<s.length;i++) if([s characterAtIndex:i]<'0' || [s characterAtIndex:i]>'9') return nil;
    while(s.length>1 && [s hasPrefix:@"0"]) s=[s substringFromIndex:1];
    if([s isEqual:@"0"]) return nil;
    NSString *max=digits==10?@"2147483647":@"18446744073709551615";
    if(s.length>max.length || (s.length==max.length && [s compare:max options:NSLiteralSearch]==NSOrderedDescending)) return nil;
    return s;
}
NSArray<NSDictionary *> *WUMomentsDecodeDisplayedComments(id item, NSArray *displayed) {
    if(!NSThread.isMainThread || !WUHostIs(item,@"WCDataItem") || ![displayed isKindOfClass:NSArray.class] || displayed.count>50) return nil;
    id source=Get(item,@"commentUsers"); if(![source isKindOfClass:NSArray.class] || [source count]>500) return nil;
    NSMutableArray *rows=[NSMutableArray array];
    for(id comment in displayed) {
        // Identity membership, not matching nicknames/IDs across parents.
        if(!WUHostIs(comment,@"WCUserComment") || [source indexOfObjectIdenticalTo:comment]==NSNotFound) continue;
        if([WUHostUInt32(comment,@"type") unsignedIntValue]!=2) continue; // Comment entries, not likes.
        NSNumber *local=WUHostBool(comment,@"isLocalAdded"); if(!local || local.boolValue) continue;
        NSString *cid=WUCommentIdentifier(Get(comment,@"commentID"),10), *prefix=@"c32:";
        if(!cid) { cid=WUCommentIdentifier(Get(comment,@"comment64ID"),20); prefix=@"c64:"; }
        NSString *author=WUHostString(Get(comment,@"username"),256), *text=WUHostString(Get(comment,@"content"),1000);
        if(!cid || !author.length || !text.length) continue;
        // These consumers prove content only. No time getter has a verified unit.
        NSString *reply=WUHostString(Get(comment,@"refUserName"),256)?:@"";
        [rows addObject:@{@"id":[prefix stringByAppendingString:cid],@"author":author,@"text":text,@"time":@0,@"replyTo":reply}];
    }
    return WUMCacheMergeComments(@[],rows,NULL);
}
