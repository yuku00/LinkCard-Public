#import "WUStatsHostProfile.h"
#import "WUHostRead.h"
#include <math.h>
static id Get(id o, NSString *s) { return WUHostObject(o,s,nil,NO); }
static BOOL ID(NSString *s) { return [s isKindOfClass:NSString.class] && s.length && s.length<=256 && [s rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location==NSNotFound; }
static id Contact(id manager, NSString *name) {
    if(!NSThread.isMainThread || !WUHostIs(manager,@"CContactMgr") || !ID(name)) return nil;
    id contact=WUHostObject(manager,@"getContactByName:",name,YES);
    return WUHostIs(contact,@"CContact") && [WUHostString(Get(contact,@"m_nsUsrName"),256) isEqual:name]?contact:nil;
}
static NSNumber *DateField(id contact, NSString *name, NSTimeInterval now) {
    NSNumber *n=WUHostUInt32(contact,name);
    return n && n.unsignedIntValue>1000000000U && n.doubleValue<=now?n:nil;
}
NSDictionary *WUStatsContactProfile(id manager, NSString *name, NSTimeInterval now) {
    if(!ID(name) || !isfinite(now) || now<=0) return nil;
    id c=Contact(manager,name); NSNumber *sex=WUHostUInt32(c,@"m_uiSex"), *age=WUHostUInt32(c,@"m_uiAge");
    NSString *country=WUHostString(Get(c,@"m_nsCountry"),128), *province=WUHostString(Get(c,@"m_nsProvince"),128);
    NSString *source=@"m_uiLocalAddContactTime"; NSNumber *added=DateField(c,source,now);
    if(!added) { source=@"m_uiAddCreateTime"; added=DateField(c,source,now); }
    // Directly supplied biological-age field only: never derive age from relationship dates.
    if(!age || age.unsignedIntValue<1 || age.unsignedIntValue>120) age=nil;
    return @{@"id":[name copy],@"available":@(c!=nil),@"sex":sex.unsignedIntValue==1?@"male":sex.unsignedIntValue==2?@"female":@"unknown",
        @"country":country?:@"",@"province":province?:@"",@"age":age?:NSNull.null,
        @"friend":WUHostBool(c,@"isMyContact")?:NSNull.null,@"added":added?:NSNull.null,@"addedSource":added?source:@"",
        @"joined":[name hasSuffix:@"@chatroom"]?(DateField(c,@"m_uiChatRoomJoinTime",now)?:NSNull.null):NSNull.null};
}
NSDictionary *WUStatsParseMembers(id raw) {
    NSString *text=WUHostString(raw,262144);
    if(!text.length) return @{@"ids":@[],@"complete":@NO};
    NSMutableOrderedSet *ids=[NSMutableOrderedSet orderedSet]; BOOL complete=YES;
    for(NSString *part in [text componentsSeparatedByString:@";"]) {
        NSString *s=[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(!s.length) continue;
        if(!ID(s) || [s hasSuffix:@"@chatroom"]) { complete=NO; continue; }
        if(ids.count==800 && ![ids containsObject:s]) { complete=NO; break; }
        [ids addObject:s];
    }
    return @{@"ids":[ids.array copy],@"complete":@(complete && ids.count>0)};
}
@interface WUHostProfileRead : NSObject
@property(nonatomic,strong) id manager;
@property(nonatomic,copy) NSString *account;
@property(nonatomic,copy) NSString *session;
@property(nonatomic,copy) NSArray *rooms;
@property(nonatomic,copy) NSArray *members;
@property(nonatomic,copy) NSArray *privateIDs;
@property(nonatomic,strong) NSMutableArray *friendProfiles;
@property(nonatomic) NSUInteger privateIndex;
@property(nonatomic) NSUInteger nonFriendCount;
@property(nonatomic) NSUInteger unknownFriendCount;
@property(nonatomic) BOOL privateTruncated;
@property(nonatomic) BOOL rosterAvailable;
@property(nonatomic) BOOL rosterMalformed;
@property(nonatomic) NSTimeInterval profileDeadline;
@property(nonatomic) NSTimeInterval roomDeadline;
@property(nonatomic,strong) id rosterRaw;
@property(nonatomic,strong) NSMutableArray *rosterNames;
@property(nonatomic) NSUInteger rosterIndex;
@property(nonatomic) NSUInteger rosterCount;
@property(nonatomic,copy) NSArray *known;
@property(nonatomic,strong) NSMutableArray *profiles;
@property(nonatomic,strong) NSMutableArray *common;
@property(nonatomic,copy) NSDictionary *peer;
@property(nonatomic,copy) BOOL (^current)(void);
@property(nonatomic,copy) void (^done)(NSDictionary *);
@property(nonatomic) NSUInteger roomIndex;
@property(nonatomic) NSUInteger memberIndex;
@property(nonatomic) NSUInteger unknownRooms;
@property(nonatomic) BOOL truncated;
@property(nonatomic) BOOL membersComplete;
- (void)step;
- (void)readRoster;
- (void)prepareCandidates;
@end
@implementation WUHostProfileRead
- (BOOL)valid { @try { return self.current && self.current(); } @catch(__unused NSException *e) { return NO; } }
- (void)drop { self.done=nil; self.current=nil; self.manager=nil; self.profiles=nil; self.common=nil; self.peer=nil; self.members=nil; self.privateIDs=nil; self.friendProfiles=nil; self.rosterRaw=nil; self.rosterNames=nil; self.known=nil; self.rooms=nil; }
- (void)finish {
    if(![self valid]) { [self drop]; return; }
    NSDictionary *friends=WUStatsProfileSummary(@{@"members":self.friendProfiles});
    NSMutableDictionary *friendSummary=[friends mutableCopy];
    [friendSummary addEntriesFromDictionary:@{ @"scanned":@(self.privateIndex),@"nonFriend":@(self.nonFriendCount),@"unknownFriend":@(self.unknownFriendCount),@"truncated":@(self.privateTruncated),@"rosterAvailable":@(self.rosterAvailable),@"rosterMalformed":@(self.rosterMalformed)}];
    NSDictionary *value=@{@"loadedFriends":[friendSummary copy],@"peer":self.peer,@"members":[self.profiles copy],@"commonGroups":[self.common copy],@"group":@([self.session hasSuffix:@"@chatroom"]),@"membersComplete":@(self.membersComplete),@"roomsChecked":@(self.roomIndex),@"unknownRooms":@(self.unknownRooms),@"truncated":@(self.truncated),@"scope":@"当前联系人/群的本地资料；共同群来自本地用户名名册及已加载群会话候选，名册范围未经证实，非服务器关系证明。"};
    void (^done)(NSDictionary *)=self.done; [self drop]; if(done) done(value);
}
- (void)step {
    if(![self valid]) { [self drop]; return; }
    if(self.roomIndex<self.rooms.count && NSDate.timeIntervalSinceReferenceDate>=self.roomDeadline) { self.truncated=YES; self.rooms=[self.rooms subarrayWithRange:NSMakeRange(0,self.roomIndex)]; }
    if(self.roomIndex<self.rooms.count) {
        NSString *room=self.rooms[self.roomIndex++];
        id c=Contact(self.manager,room); NSString *raw=WUHostString(Get(c,@"m_nsChatRoomMemList"),262144);
        // Parse potentially long member strings off main. No host object crosses queues.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            NSDictionary *parsed=WUStatsParseMembers(raw);
            dispatch_async(dispatch_get_main_queue(),^{
                if(![self valid]) { [self drop]; return; }
                NSArray *ids=parsed[@"ids"]; BOOL complete=[parsed[@"complete"] boolValue];
                if([self.session hasSuffix:@"@chatroom"]) { self.members=ids; self.membersComplete=complete; }
                else if([ids containsObject:self.account] && [ids containsObject:self.session]) [self.common addObject:room];
                if(!complete) self.unknownRooms++;
                [self step];
            });
        }); return;
    }
    if(!self.profileDeadline) self.profileDeadline=NSDate.timeIntervalSinceReferenceDate+1.5;
    if(self.privateIndex<self.privateIDs.count && NSDate.timeIntervalSinceReferenceDate>=self.profileDeadline) {
        self.privateTruncated=YES;
        self.privateIDs=[self.privateIDs subarrayWithRange:NSMakeRange(0,self.privateIndex)];
    }
    NSUInteger privateEnd=MIN(self.privateIndex+8,self.privateIDs.count);
    while(self.privateIndex<privateEnd) {
        if(![self valid]) { [self drop]; return; }
        NSDictionary *row=WUStatsContactProfile(self.manager,self.privateIDs[self.privateIndex++],NSDate.date.timeIntervalSince1970);
        id flag=row[@"friend"];
        if(![flag isKindOfClass:NSNumber.class]) self.unknownFriendCount++;
        else if([flag boolValue]) [self.friendProfiles addObject:row];
        else self.nonFriendCount++;
    }
    if(self.privateIndex<self.privateIDs.count) { dispatch_async(dispatch_get_main_queue(),^{ [self step]; }); return; }
    NSUInteger end=MIN(self.memberIndex+8,self.members.count);
    while(self.memberIndex<end) {
        if(![self valid]) { [self drop]; return; }
        NSString *name=self.members[self.memberIndex++];
        NSDictionary *row=WUStatsContactProfile(self.manager,name,NSDate.date.timeIntervalSince1970);
        if(row) [self.profiles addObject:row];
    }
    if(self.memberIndex<self.members.count) dispatch_async(dispatch_get_main_queue(),^{ [self step]; });
    else [self finish];
}
- (void)readRoster {
    if(![self valid]) { [self drop]; return; }
    @try {
        NSUInteger end=MIN(self.rosterIndex+128,self.rosterCount);
        while(self.rosterIndex<end) {
            id name=self.rosterRaw[self.rosterIndex++];
            if(ID(name)) [self.rosterNames addObject:[name copy]]; else self.rosterMalformed=YES;
        }
    } @catch(__unused NSException *e) { self.rosterAvailable=NO; self.rosterMalformed=YES; [self.rosterNames removeAllObjects]; self.rosterIndex=self.rosterCount; }
    if(self.rosterIndex<self.rosterCount) { dispatch_async(dispatch_get_main_queue(),^{ [self readRoster]; }); return; }
    self.rosterRaw=nil; [self prepareCandidates];
}
- (void)prepareCandidates {
    NSArray *known=self.known, *roster=[self.rosterNames copy]; NSString *session=self.session, *account=self.account;
    BOOL available=self.rosterAvailable, malformed=self.rosterMalformed;
    self.rosterNames=nil; self.known=nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSMutableOrderedSet *rooms=[NSMutableOrderedSet orderedSet]; BOOL truncated=NO;
        if([session hasSuffix:@"@chatroom"]) [rooms addObject:session];
        else {
            for(id row in known) {
                if(![row isKindOfClass:NSDictionary.class] || ![row[@"kind"] isEqual:@"chatroom"]) continue;
                NSString *name=row[@"username"];
                if(ID(name) && [name hasSuffix:@"@chatroom"]) [rooms addObject:[name copy]];
            }
            for(NSString *name in roster) if([name hasSuffix:@"@chatroom"]) [rooms addObject:name];
            if(rooms.count>2000) { truncated=YES; [rooms removeObjectsInRange:NSMakeRange(2000,rooms.count-2000)]; }
            if(malformed) truncated=YES;
        }
        NSMutableSet *unique=[NSMutableSet set];
        for(id row in known) {
            if(![row isKindOfClass:NSDictionary.class] || ![row[@"kind"] isEqual:@"private"]) continue;
            NSString *name=row[@"username"];
            if(ID(name) && ![name isEqual:account] && ![name hasSuffix:@"@chatroom"]) [unique addObject:[name copy]];
        }
        for(NSString *name in roster) if(![name isEqual:account] && ![name hasSuffix:@"@chatroom"]) [unique addObject:name];
        NSArray *all=[[unique allObjects] sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger limit=available?2000:500; BOOL privateTruncated=all.count>limit || malformed;
        NSArray *privateIDs=all.count>limit?[all subarrayWithRange:NSMakeRange(0,limit)]:all;
        NSArray *snapshot=[rooms.array copy];
        dispatch_async(dispatch_get_main_queue(),^{
            if(![self valid]) { [self drop]; return; }
            self.rooms=snapshot; self.truncated=truncated; self.privateIDs=privateIDs; self.privateTruncated=privateTruncated;
            self.roomDeadline=NSDate.timeIntervalSinceReferenceDate+1.5; [self step];
        });
    });
}
@end
void WUStatsReadHostProfile(id manager, NSString *account, NSString *session, NSArray *sessions, BOOL (^current)(void), void (^done)(NSDictionary *)) {
    if(!NSThread.isMainThread || !ID(account) || !ID(session) || !current || !done || !current()) return;
    WUHostProfileRead *job=[WUHostProfileRead new]; job.manager=manager; job.account=[account copy]; job.session=[session copy]; job.current=current; job.done=done;
    job.peer=WUStatsContactProfile(manager,session,NSDate.date.timeIntervalSince1970); job.profiles=[NSMutableArray array]; job.common=[NSMutableArray array]; job.members=@[]; job.friendProfiles=[NSMutableArray array]; job.known=[sessions copy]; job.rosterNames=[NSMutableArray array];
    // Public third-party 8.0.55 header: CContactMgr getAllContactUserName; scope is undocumented.
    @try {
        id raw=WUHostIs(manager,@"CContactMgr")?Get(manager,@"getAllContactUserName"):nil;
        if([raw isKindOfClass:NSArray.class]) {
            job.rosterAvailable=YES; job.rosterRaw=raw; job.rosterCount=MIN([raw count],20000);
            if([raw count]>20000) job.rosterMalformed=YES;
        }
    } @catch(__unused NSException *e) { job.rosterAvailable=NO; job.rosterMalformed=YES; }
    [job readRoster];
}
NSDictionary *WUStatsProfileSummary(NSDictionary *snapshot) {
    if(![snapshot isKindOfClass:NSDictionary.class]) return nil;
    NSArray *members=[snapshot[@"members"] isKindOfClass:NSArray.class]?snapshot[@"members"]:@[];
    NSMutableDictionary *sex=[@{@"male":@0,@"female":@0,@"unknown":@0} mutableCopy], *regions=[NSMutableDictionary dictionary], *ages=[NSMutableDictionary dictionary];
    NSUInteger unknownContact=0,unknownRegion=0,unknownAge=0,friends=0,unknownFriend=0;
    for(NSDictionary *p in members) {
        NSString *s=p[@"sex"]; if(!sex[s]) s=@"unknown"; sex[s]=@([sex[s] unsignedIntegerValue]+1);
        if(![p[@"available"] boolValue]) unknownContact++;
        id f=p[@"friend"]; if(![f isKindOfClass:NSNumber.class]) unknownFriend++; else if([f boolValue]) friends++;
        NSString *country=p[@"country"], *province=p[@"province"];
        if(!country.length && !province.length) unknownRegion++;
        else { NSArray *key=@[country,province]; regions[key]=@([regions[key] unsignedIntegerValue]+1); }
        id age=p[@"age"]; if(![age isKindOfClass:NSNumber.class]) unknownAge++; else { NSString *key=[age stringValue]; ages[key]=@([ages[key] unsignedIntegerValue]+1); }
    }
    NSMutableArray *rows=[NSMutableArray array];
    for(NSArray *key in regions) [rows addObject:@{@"country":key[0],@"province":key[1],@"count":regions[key]}];
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult n=[b[@"count"] compare:a[@"count"]];
        if(n==NSOrderedSame) n=[a[@"country"] compare:b[@"country"] options:NSLiteralSearch];
        return n==NSOrderedSame?[a[@"province"] compare:b[@"province"] options:NSLiteralSearch]:n;
    }];
    NSMutableDictionary *result=[snapshot mutableCopy]; [result removeObjectForKey:@"members"];
    [result addEntriesFromDictionary:@{@"memberCount":@(members.count),@"sex":sex,@"regions":rows,@"unknownContact":@(unknownContact),@"unknownRegion":@(unknownRegion),@"ages":ages,@"unknownAge":@(unknownAge),@"friends":@(friends),@"unknownFriend":@(unknownFriend)}];
    return [result copy];
}
NSArray<NSString *> *WUStatsProfileLines(NSDictionary *p, NSTimeZone *zone) {
    if(!p) return @[@"尚未读取宿主资料"];
    NSDictionary *peer=p[@"peer"]; BOOL group=[p[@"group"] boolValue];
    NSMutableArray *lines=[NSMutableArray arrayWithObjects:p[@"scope"],@"资料为本次扫描时的本地快照，不受消息日期范围筛选；空值/异常/未知枚举均保留未知。未刷新资料、未联网、未持久化画像。",nil];
    NSDictionary *loaded=p[@"loadedFriends"];
    if([loaded isKindOfClass:NSDictionary.class]) {
        NSString *source=[loaded[@"rosterAvailable"] boolValue]?@"本地用户名名册及已加载私聊会话的去重候选（名册范围未经证实）":@"已加载私聊会话候选（名册接口不可用）";
        [lines addObject:[NSString stringWithFormat:@"%@：检查 %@，好友标志为是 %@、否 %@、未知 %@%@%@。仅本地快照，不是全好友名册或好友总数。",source,loaded[@"scanned"],loaded[@"memberCount"],loaded[@"nonFriend"],loaded[@"unknownFriend"],[loaded[@"truncated"] boolValue]?@"；受数量/时间/数据异常限制，结果已截断或不完整":@"",[loaded[@"rosterMalformed"] boolValue]?@"；名册有异常条目或超出输入上限":@""]];
        [lines addObject:[NSString stringWithFormat:@"上述标志为是的资料性别：男 %@ · 女 %@ · 未知 %@；地区未知 %@ · 年龄未知 %@。",loaded[@"sex"][@"male"],loaded[@"sex"][@"female"],loaded[@"sex"][@"unknown"],loaded[@"unknownRegion"],loaded[@"unknownAge"]]];
        for(NSDictionary *row in loaded[@"regions"]) [lines addObject:[NSString stringWithFormat:@"好友标志资料地区 %@ / %@：%@",[row[@"country"] length]?row[@"country"]:@"未知",[row[@"province"] length]?row[@"province"]:@"未知",row[@"count"]]];
        for(NSString *age in [[loaded[@"ages"] allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) [lines addObject:[NSString stringWithFormat:@"好友标志资料年龄 %@ 岁：%@",age,loaded[@"ages"][age]]];
    }
    NSDateFormatter *f=[NSDateFormatter new]; f.locale=[NSLocale localeWithLocaleIdentifier:@"zh_CN"]; f.timeZone=zone; f.dateFormat=@"yyyy-MM-dd HH:mm:ss zzz";
    NSString *(^date)(id)=^NSString *(id n) { return [n isKindOfClass:NSNumber.class]?[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:[n doubleValue]]]:@"未知"; };
    if(group) {
        [lines addObject:[NSString stringWithFormat:@"本地成员 %@（%@）；资料缺失 %@。",p[@"memberCount"],[p[@"membersComplete"] boolValue]?@"当前字符串已解析；非服务端完整保证":@"不完整/未知",p[@"unknownContact"]]];
        [lines addObject:[NSString stringWithFormat:@"资料性别：男 %@ · 女 %@ · 未知 %@",p[@"sex"][@"male"],p[@"sex"][@"female"],p[@"sex"][@"unknown"]]];
        [lines addObject:[NSString stringWithFormat:@"资料好友标志：是 %@ · 未知 %@（含本人原始标志，不作为好友总数）",p[@"friends"],p[@"unknownFriend"]]];
        [lines addObject:[NSString stringWithFormat:@"本地入群日期字段：%@；不保证首次加入或服务端证明",date(peer[@"joined"])]];
        [lines addObject:[NSString stringWithFormat:@"地区未知 %@；以下为资料原值，未定位/翻译/推断：",p[@"unknownRegion"]]];
        for(NSDictionary *row in p[@"regions"]) [lines addObject:[NSString stringWithFormat:@"%@ / %@：%@",[row[@"country"] length]?row[@"country"]:@"未知",[row[@"province"] length]?row[@"province"]:@"未知",row[@"count"]]];
        [lines addObject:[NSString stringWithFormat:@"资料年龄未知 %@；非关系年限，未用生日/聊天时间推算。",p[@"unknownAge"]]];
        for(NSString *age in [[p[@"ages"] allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) [lines addObject:[NSString stringWithFormat:@"资料年龄 %@ 岁：%@",age,p[@"ages"][age]]];
    } else {
        NSString *sex=@{@"male":@"男",@"female":@"女",@"unknown":@"未知"}[peer[@"sex"]]?:@"未知";
        [lines addObject:[NSString stringWithFormat:@"资料性别 %@ · 年龄 %@（字段原值，非关系年限）",sex,peer[@"age"]==NSNull.null?@"未知":[peer[@"age"] description]]];
        [lines addObject:[NSString stringWithFormat:@"地区原值：%@ / %@",[peer[@"country"] length]?peer[@"country"]:@"未知",[peer[@"province"] length]?peer[@"province"]:@"未知"]];
        [lines addObject:[NSString stringWithFormat:@"本地添加日期：%@；来源 %@，不保证首次添加",date(peer[@"added"]),[peer[@"addedSource"] length]?peer[@"addedSource"]:@"未知"]];
        [lines addObject:[NSString stringWithFormat:@"已确认本地共同群下界 %lu；检查 %@ 个本地群候选，%@ 个成员表不完整/未知%@。未发现不等于没有共同群。",(unsigned long)[p[@"commonGroups"] count],p[@"roomsChecked"],p[@"unknownRooms"],[p[@"truncated"] boolValue]?@"；已截断":@""]];
        [lines addObjectsFromArray:p[@"commonGroups"]];
    }
    return lines;
}
