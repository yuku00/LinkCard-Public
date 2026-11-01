#import "WUStats.h"
#import <math.h>

NSArray<NSString *> *WUStatsOptionalSections(void) {
    return @[@"sessions",@"visits",@"overview",@"selfPeer",@"journey",@"types",@"days",@"hours",@"speakers",@"replies",@"openers",@"closers",@"icebreakers",@"bursts",@"words",@"rank",@"private",@"chatroom",@"myGroups"];
}
NSArray<NSString *> *WUStatsSectionOrder(id stored) {
    NSArray *known=WUStatsOptionalSections();
    if(![stored isKindOfClass:NSArray.class] || [stored count]>known.count) return known;
    NSMutableArray *out=[NSMutableArray array];
    for(id key in stored) {
        if(![key isKindOfClass:NSString.class] || ![known containsObject:key] || [out containsObject:key]) return known;
        [out addObject:key];
    }
    return out; // Empty is an intentional hide-all; controls/status/limitations remain visible.
}
NSArray<NSDictionary *> *WUStatsMyGroupRanking(NSArray<NSDictionary *> *rows) {
    NSMutableArray *groups=[NSMutableArray array];
    for(NSDictionary *row in rows) if([row[@"kind"] isEqual:@"chatroom"] && [row[@"selfCount"] isKindOfClass:NSNumber.class]) {
        NSMutableDictionary *g=[row mutableCopy]; g[@"count"]=row[@"selfCount"]; [groups addObject:g];
    }
    return [groups sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult c=[b[@"count"] compare:a[@"count"]]; return c==NSOrderedSame?[a[@"id"] compare:b[@"id"] options:NSLiteralSearch]:c;
    }];
}
static void Increment(NSMutableDictionary *d, NSString *k) { d[k]=@([d[k] unsignedIntegerValue]+1); }
NSDictionary *WUStatsDetails(NSArray<NSDictionary *> *records, NSString *account, NSString *peer, BOOL group, NSTimeZone *zone) {
    NSCalendar *calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone=zone;
    NSMutableDictionary *sides=[NSMutableDictionary dictionary];
    for(NSString *key in @[@"self",@"peer",@"others",@"unknown"]) sides[key]=[@{@"count":@0,@"authoredCount":@0,@"types":[NSMutableDictionary dictionary],@"days":[NSMutableDictionary dictionary]} mutableCopy];
    NSMutableDictionary *days=[NSMutableDictionary dictionary],*firstByType=[NSMutableDictionary dictionary];
    NSNumber *first=nil,*last=nil; NSUInteger dated=0;
    for(NSDictionary *r in records) {
        NSString *sender=r[@"sender"],*type=r[@"type"];
        NSString *side=!account.length || !sender.length || (group && [sender isEqual:peer])?@"unknown":([sender isEqual:account]?@"self":(group?@"others":([sender isEqual:peer]?@"peer":@"unknown")));
        NSMutableDictionary *bucket=sides[side]; Increment(bucket,@"count"); Increment(bucket[@"types"],type);
        if(![@[@"system",@"pat"] containsObject:type]) Increment(bucket,@"authoredCount");
        NSNumber *time=r[@"time"]; if(time.doubleValue<=0 || !isfinite(time.doubleValue)) continue;
        dated++;
        if(!first || [time compare:first]==NSOrderedAscending) first=time;
        if(!last || [time compare:last]==NSOrderedDescending) last=time;
        if(!bucket[@"first"] || [time compare:bucket[@"first"]]==NSOrderedAscending) bucket[@"first"]=time;
        if(!bucket[@"last"] || [time compare:bucket[@"last"]]==NSOrderedDescending) bucket[@"last"]=time;
        if(!firstByType[type] || [time compare:firstByType[type]]==NSOrderedAscending) firstByType[type]=time;
        NSDateComponents *c=[calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:[NSDate dateWithTimeIntervalSince1970:time.doubleValue]];
        NSString *day=[NSString stringWithFormat:@"%04ld-%02ld-%02ld",(long)c.year,(long)c.month,(long)c.day];
        Increment(bucket[@"days"],day);
        if(!days[day]) days[day]=[@{@"day":day,@"count":@0,@"self":@0,@"peer":@0,@"others":@0,@"unknown":@0} mutableCopy];
        Increment(days[day],@"count"); Increment(days[day],side);
    }
    for(NSString *key in sides) {
        NSMutableDictionary *bucket=sides[key];
        bucket[@"activeDays"]=@([bucket[@"days"] count]); [bucket removeObjectForKey:@"days"];
        bucket[@"shareOfTotal"]=records.count?@([bucket[@"count"] doubleValue]/records.count):NSNull.null;
    }
    NSMutableArray *timeline=[NSMutableArray array];
    for(NSString *day in [days.allKeys sortedArrayUsingSelector:@selector(compare:)]) [timeline addObject:days[day]];
    return @{@"summary":sides,@"denominator":@(records.count),@"dated":@(dated),@"first":first?:NSNull.null,@"last":last?:NSNull.null,@"firstByType":firstByType,@"timeline":timeline};
}
