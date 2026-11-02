#import "WUStats.h"
#import "WUStatsHostProfile.h"
#import "WUHostRead.h"
#import <objc/runtime.h>
#import <limits.h>
#import <math.h>
#import <string.h>

@implementation WUStatsBinding
- (instancetype)init { if ((self = [super init])) { _account=@""; _session=@""; _verifiedEncoding=@""; _initialCursor=@{}; _timeZone=[NSTimeZone.localTimeZone copy]; _sessions=@[]; _pageLimit=100; } return self; }
@end

NSDictionary *WUStatsDateRange(NSString *start, NSString *end, NSTimeZone *zone) {
    if(![start isKindOfClass:NSString.class] || ![end isKindOfClass:NSString.class] || !zone) return nil;
    NSDateFormatter *f=[NSDateFormatter new]; f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSCalendar *cal=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; cal.timeZone=zone;
    f.calendar=cal; f.timeZone=zone; f.dateFormat=@"yyyy-MM-dd"; f.lenient=NO;
    NSDate *a=[f dateFromString:start], *b=[f dateFromString:end];
    if(!a || !b || ![[f stringFromDate:a] isEqual:start] || ![[f stringFromDate:b] isEqual:end] || [a compare:b]==NSOrderedDescending) return nil;
    NSDate *exclusive=[cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:b options:0];
    if(!exclusive || a.timeIntervalSince1970<0) return nil;
    return @{@"start":@(a.timeIntervalSince1970),@"end":@(exclusive.timeIntervalSince1970),@"label":[NSString stringWithFormat:@"%@ 至 %@（含） · %@ · [起日00:00,末日次日00:00)",start,end,zone.name]};
}
BOOL WUStatsTimeInRange(NSNumber *time, NSDictionary *range) {
    if(!range) return YES;
    return [time isKindOfClass:NSNumber.class] && isfinite(time.doubleValue) && time.doubleValue>0 && time.doubleValue>=[range[@"start"] doubleValue] && time.doubleValue<[range[@"end"] doubleValue];
}

static NSString *WUString(id value) { return [value isKindOfClass:NSString.class] ? [value copy] : @""; }
static NSString *WUID(id value) {
    NSString *s=WUString(value);
    if (!s.length || s.length>20 || [s rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound) return @"";
    // ASCII only; do not round 64-bit IDs through floating point.
    for (NSUInteger i=0;i<s.length;i++) if ([s characterAtIndex:i]<'0'||[s characterAtIndex:i]>'9') return @"";
    NSUInteger p=0; while(p<s.length && [s characterAtIndex:p]=='0') p++;
    return p==s.length ? @"" : [s substringFromIndex:p];
}
static void WUInc(NSMutableDictionary *d, NSString *key) { d[key]=@([d[key] unsignedIntegerValue]+1); }
static NSArray *WURank(NSDictionary *d) {
    NSArray *keys=[d.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b) {
        NSComparisonResult r=[d[b] compare:d[a]]; return r==NSOrderedSame ? [a compare:b options:NSLiteralSearch] : r;
    }];
    NSMutableArray *rows=[NSMutableArray array]; for (NSString *k in keys) [rows addObject:@{@"id":k,@"count":d[k]}]; return rows;
}
static NSSet *WUTypes(void) {
    static NSSet *s; static dispatch_once_t once; dispatch_once(&once, ^{s=[NSSet setWithArray:@[@"text",@"image",@"voice",@"video",@"emoji",@"link",@"file",@"location",@"system",@"pat",@"redpacket",@"transfer",@"appUnknown",@"other"]];}); return s;
}
static void WUWords(NSString *text, NSMutableDictionary *words) {
    // Local Foundation word boundaries, not semantic inference. No URLs/XML tokens.
    if (text.length>8192) text=[text substringToIndex:8192];
    if ([text containsString:@"<"] || [text containsString:@"http://"] || [text containsString:@"https://"]) return;
    NSSet *stop=[NSSet setWithArray:@[@"的",@"了",@"是",@"我",@"你",@"他",@"她",@"我们",@"你们",@"the",@"and",@"this",@"that",@"with",@"for"]];
    [text enumerateSubstringsInRange:NSMakeRange(0,text.length) options:NSStringEnumerationByWords usingBlock:^(NSString *s,NSRange r,NSRange er,BOOL *stopEnumeration) {
        NSString *word=[s lowercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        if (word.length>=2 && word.length<=32 && ![stop containsObject:word] && [word rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location!=NSNotFound) WUInc(words,word);
    }];
}

@interface WUStatsAccumulator ()
@property(nonatomic,copy) NSDictionary *dateRange;
@property(nonatomic,strong) NSMutableArray<NSMutableDictionary *> *records;
@property(nonatomic,strong) NSMutableDictionary *serverIndex;
@property(nonatomic,strong) NSMutableDictionary *localIndex;
@property(nonatomic,strong) NSCalendar *calendar;
@property(nonatomic) BOOL group;
@property(nonatomic) NSUInteger duplicates;
@property(nonatomic) NSUInteger interactionPhase;
@end
@implementation WUStatsAccumulator
- (instancetype)initWithTimeZone:(NSTimeZone *)zone group:(BOOL)group {
    if ((self=[super init])) { _records=[NSMutableArray array]; _serverIndex=[NSMutableDictionary dictionary]; _localIndex=[NSMutableDictionary dictionary]; _group=group;
        _calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; _calendar.timeZone=[zone copy]; }
    return self;
}
- (BOOL)addRecords:(NSArray<NSDictionary *> *)records {
    if (![records isKindOfClass:NSArray.class]) return NO;
    // Validate a whole page before mutation. Missing time is explicitly invalid, not epoch.
    for (id r in records) {
        if (![r isKindOfClass:NSDictionary.class]) return NO;
        for (NSString *key in @[@"sid",@"lid",@"source",@"sender",@"type",@"text"]) if (r[key] && ![r[key] isKindOfClass:NSString.class]) return NO;
        id t=r[@"time"]; if (t && (![t isKindOfClass:NSNumber.class] || !isfinite([t doubleValue]) || [t doubleValue]<0 || [t doubleValue]>253402300799.0 || floor([t doubleValue])!=[t doubleValue])) return NO;
    }
    for (NSDictionary *input in records) {
        if(!WUStatsTimeInRange(input[@"time"],self.dateRange)) continue;
        NSString *sid=WUID(input[@"sid"]), *lid=WUID(input[@"lid"]), *source=WUString(input[@"source"]);
        // A length-prefixed source prevents delimiter collisions.
        NSString *lk=lid.length && source.length ? [NSString stringWithFormat:@"%lu:%@:%@",(unsigned long)source.length,source,lid] : @"";
        NSNumber *index=sid.length ? self.serverIndex[sid] : nil;
        NSNumber *local=lk.length ? self.localIndex[lk] : nil;
        if (!index && local) {
            NSString *oldSID=self.records[local.unsignedIntegerValue][@"sid"];
            if (!sid.length || !oldSID.length || [oldSID isEqualToString:sid]) index=local;
        }
        NSString *type=[WUTypes() containsObject:input[@"type"]] ? input[@"type"] : @"other";
        if (index) {
            self.duplicates++;
            NSMutableDictionary *r=self.records[index.unsignedIntegerValue];
            BOOL payment=[type isEqual:@"redpacket"]||[type isEqual:@"transfer"];
            BOOL oldPayment=[@[@"redpacket",@"transfer"] containsObject:r[@"type"]];
            if(payment && oldPayment && ![type isEqual:r[@"type"]]) { r[@"type"]=@"appUnknown"; r[@"paymentConflict"]=@YES; }
            else if(![r[@"paymentConflict"] boolValue] && ([r[@"type"] isEqual:@"other"] || (payment && !oldPayment))) r[@"type"]=type;
            if (sid.length && ![r[@"sid"] length]) r[@"sid"]=sid;
            // Same confirmed message: fill missing observations only; never replace
            // a known value with a possibly conflicting copy from another source.
            if (![r[@"sender"] length] && WUString(input[@"sender"]).length) r[@"sender"]=WUString(input[@"sender"]);
            if (![r[@"text"] length] && WUString(input[@"text"]).length) r[@"text"]=WUString(input[@"text"]);
            if (![r[@"time"] longLongValue] && [input[@"time"] longLongValue]>0) r[@"time"]=input[@"time"];
            if (sid.length || lk.length) r[@"reliable"]=@YES;
        } else {
            index=@(self.records.count);
            [self.records addObject:[@{@"sid":sid,@"lid":lid,@"source":source,@"sender":WUString(input[@"sender"]),@"time":input[@"time"]?:@0,@"type":type,@"text":WUString(input[@"text"]),@"ordinal":index,@"phase":@(self.interactionPhase),@"reliable":@(sid.length || lk.length)} mutableCopy]];
        }
        if (sid.length) self.serverIndex[sid]=index;
        if (lk.length) self.localIndex[lk]=index;
    }
    return YES;
}
- (NSDictionary *)result {
    NSMutableDictionary *types=[NSMutableDictionary dictionary],*days=[NSMutableDictionary dictionary],*hours=[NSMutableDictionary dictionary],*speakers=[NSMutableDictionary dictionary],*words=[NSMutableDictionary dictionary];
    NSMutableDictionary *open=[NSMutableDictionary dictionary],*close=[NSMutableDictionary dictionary],*reply=[NSMutableDictionary dictionary],*burst=[NSMutableDictionary dictionary],*ice=[NSMutableDictionary dictionary];
    NSUInteger unknownTime=0,unknownID=0,unknownSender=0,night=0,replies=0; int64_t seconds=0;
    for (NSDictionary *r in self.records) {
        WUInc(types,r[@"type"]);
        NSString *sender=r[@"sender"]; if (sender.length) WUInc(speakers,sender); else unknownSender++;
        if (![r[@"reliable"] boolValue]) unknownID++;
        int64_t t=[r[@"time"] longLongValue];
        if (t>0) {
            NSDateComponents *c=[self.calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour fromDate:[NSDate dateWithTimeIntervalSince1970:t]];
            WUInc(days,[NSString stringWithFormat:@"%04ld-%02ld-%02ld",(long)c.year,(long)c.month,(long)c.day]);
            WUInc(hours,[NSString stringWithFormat:@"%02ld",(long)c.hour]); if (c.hour<6) night++;
        } else unknownTime++;
        if ([r[@"type"] isEqual:@"text"]) WUWords(r[@"text"],words);
    }
    // Unknown-time records remain barriers in ingestion order. Sort each known-time
    // segment, never move a zero-time record to the beginning and bridge across it.
    NSMutableArray *ordered=[NSMutableArray array],*segment=[NSMutableArray array];
    NSComparator compare=^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        NSComparisonResult c=[a[@"time"] compare:b[@"time"]]; if (c!=NSOrderedSame) return c;
        NSString *ka=[NSString stringWithFormat:@"%@/%@/%@/%@",a[@"sid"],a[@"source"],a[@"lid"],a[@"sender"]];
        NSString *kb=[NSString stringWithFormat:@"%@/%@/%@/%@",b[@"sid"],b[@"source"],b[@"lid"],b[@"sender"]];
        c=[ka compare:kb options:NSLiteralSearch]; return c==NSOrderedSame ? [a[@"ordinal"] compare:b[@"ordinal"]] : c;
    };
    NSNumber *phase=nil;
    for (NSDictionary *r in self.records) {
        if(phase && ![phase isEqual:r[@"phase"]]) { [segment sortUsingComparator:compare]; [ordered addObjectsFromArray:segment]; [segment removeAllObjects]; }
        phase=r[@"phase"];
        if ([r[@"time"] longLongValue]<=0) { [segment sortUsingComparator:compare]; [ordered addObjectsFromArray:segment]; [segment removeAllObjects]; [ordered addObject:r]; } else [segment addObject:r];
    }
    [segment sortUsingComparator:compare]; [ordered addObjectsFromArray:segment];
    NSDictionary *previous=nil;
    for (NSUInteger i=0;i<ordered.count;i++) {
        NSDictionary *r=ordered[i]; int64_t t=[r[@"time"] longLongValue]; NSString *sender=r[@"sender"];
        // Every member of an equal-time cluster is ambiguous, including its edges.
        if(previous && ![previous[@"phase"] isEqual:r[@"phase"]]) previous=nil;
        BOOL tied=(i>0 && [ordered[i-1][@"phase"] isEqual:r[@"phase"]] && [ordered[i-1][@"time"] longLongValue]==t)||(i+1<ordered.count && [ordered[i+1][@"phase"] isEqual:r[@"phase"]] && [ordered[i+1][@"time"] longLongValue]==t);
        if (!t || !sender.length || tied || [@[@"system",@"pat"] containsObject:r[@"type"]]) { previous=nil; continue; }
        if (previous) {
            int64_t delta=t-[previous[@"time"] longLongValue]; NSString *prior=previous[@"sender"];
            if (delta>=21600) { WUInc(open,sender); WUInc(close,prior); if(delta>=86400) WUInc(ice,sender); }
            else if (delta>0 && ![sender isEqual:prior]) { WUInc(reply,sender); replies++; seconds+=delta; }
            else if (delta>0 && delta<=300 && [sender isEqual:prior]) WUInc(burst,sender);
        }
        previous=r;
    }
    NSDateFormatter *df=[NSDateFormatter new]; df.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; df.calendar=self.calendar; df.timeZone=self.calendar.timeZone; df.dateFormat=@"yyyy-MM-dd";
    NSUInteger best=0,run=0; NSDate *last=nil;
    for (NSString *day in [days.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSDate *date=[df dateFromString:day]; NSInteger gap=last ? [self.calendar components:NSCalendarUnitDay fromDate:last toDate:date options:0].day : 0;
        run=(last && gap==1) ? run+1 : 1; best=MAX(best,run); last=date;
    }
    return @{@"algorithm":@"wu-local-1",@"group":@(self.group),@"timezone":self.calendar.timeZone.name,@"total":@(self.records.count),@"duplicates":@(self.duplicates),@"unknownID":@(unknownID),@"unknownTime":@(unknownTime),@"unknownSender":@(unknownSender),@"types":types,@"days":days,@"hours":hours,@"night":@(night),@"longestStreak":@(best),@"speakers":WURank(speakers),@"words":WURank(words),@"openers":WURank(open),@"closers":WURank(close),@"replies":WURank(reply),@"bursts":WURank(burst),@"icebreakers":WURank(ice),@"replyCount":@(replies),@"replyMeanSeconds":replies ? @((double)seconds/replies) : NSNull.null};
}
@end

// Static evidence 0x1599b44..b68: object, 32-bit ID/time/limit, pointer
// to a 32-bit left count; object return. Signedness/type encoding is NOT in
// the sample. Require an independently verified exact encoding before invoking.
static const char *WUUnqualified(const char *s) { while (*s && strchr("rnNoORV",*s)) s++; return s; }
static BOOL WUUInt32(id n) { return [n isKindOfClass:NSNumber.class] && isfinite([n doubleValue]) && [n doubleValue]>=0 && [n doubleValue]<=UINT32_MAX && floor([n doubleValue])==[n doubleValue]; }
// 0x1599790..a8: session, FromID, CreateTime, limit=200; object return.
// The sample writes w3/w4/w5. Runtime may widen integer parameters; marshal
// each independently at its actual width, never reinterpret pointers/objects.
NSString *WUStatsAppMethodEncoding(id manager) {
    if(!WUHostIs(manager,@"CMessageMgr")) return nil;
    Method m=class_getInstanceMethod(object_getClass(manager),NSSelectorFromString(@"GetAppMsgList:FromID:CreateTime:Limit:"));
    if(!m) return nil;
    NSMethodSignature *s=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
    if(s.numberOfArguments!=6 || strcmp(WUUnqualified(s.methodReturnType),"@") || strcmp(WUUnqualified([s getArgumentTypeAtIndex:2]),"@")) return nil;
    for(NSUInteger i=3;i<6;i++) { const char *t=WUUnqualified([s getArgumentTypeAtIndex:i]); if(strlen(t)!=1 || !strchr("iIqQ",*t)) return nil; }
    return [NSString stringWithUTF8String:method_getTypeEncoding(m)];
}
static NSArray *WUReadAppPage(WUStatsBinding *b, NSDictionary *cursor, NSString **failure) {
    NSString *encoding=WUStatsAppMethodEncoding(b.messageManager);
    if(!encoding || !b.appEncoding.length || ![encoding isEqual:b.appEncoding]) { *failure=@"已截断：App消息查询签名缺失或变化，普通消息结果保留"; return nil; }
    if(!WUUInt32(cursor[@"id"]) || !WUUInt32(cursor[@"time"])) { *failure=@"App游标无效"; return nil; }
    @try {
        NSMethodSignature *sig=[NSMethodSignature signatureWithObjCTypes:encoding.UTF8String];
        NSInvocation *call=[NSInvocation invocationWithMethodSignature:sig]; call.target=b.messageManager; call.selector=NSSelectorFromString(@"GetAppMsgList:FromID:CreateTime:Limit:");
        __unsafe_unretained NSString *session=b.session; [call setArgument:&session atIndex:2];
        NSArray *values=@[cursor[@"id"],cursor[@"time"],@200];
        for(NSUInteger i=3;i<6;i++) {
            uint64_t n=[values[i-3] unsignedLongLongValue]; const char *t=WUUnqualified([sig getArgumentTypeAtIndex:i]);
            if(*t=='i' && n>INT32_MAX) { *failure=@"App游标超出有符号32位范围"; return nil; }
            if(*t=='I') { uint32_t v=(uint32_t)n; [call setArgument:&v atIndex:i]; }
            else if(*t=='i') { int32_t v=(int32_t)n; [call setArgument:&v atIndex:i]; }
            else if(*t=='Q') { uint64_t v=n; [call setArgument:&v atIndex:i]; }
            else { int64_t v=(int64_t)n; [call setArgument:&v atIndex:i]; }
        }
        [call invoke]; __unsafe_unretained id result=nil; [call getReturnValue:&result];
        if([result isKindOfClass:NSArray.class] && [result count]<=200) return [result copy];
        *failure=@"App返回页无效；不将nil当作历史结束";
    } @catch(__unused NSException *e) { *failure=@"App读取异常；未记录消息正文"; }
    return nil;
}
// Only integer getters with a real Method. IDs never round-trip through double.
static NSNumber *WUStatsHostInteger(id object, NSString *name) {
    Method m=class_getInstanceMethod(object_getClass(object),NSSelectorFromString(name)); if(!m) return nil;
    NSMethodSignature *s=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
    const char *t=WUUnqualified(s.methodReturnType); if(s.numberOfArguments!=2 || strlen(t)!=1 || !strchr("iIqQ",*t)) return nil;
    NSInvocation *call=[NSInvocation invocationWithMethodSignature:s]; call.target=object; call.selector=NSSelectorFromString(name); [call invoke];
    if(*t=='I') { uint32_t n=0; [call getReturnValue:&n]; return @(n); }
    if(*t=='i') { int32_t n=0; [call getReturnValue:&n]; return n>=0?@(n):nil; }
    if(*t=='Q') { uint64_t n=0; [call getReturnValue:&n]; return @(n); }
    int64_t n=0; [call getReturnValue:&n]; return n>=0?@(n):nil;
}
static NSString *WUStatsAppType(id wrap) {
    id pay=WUHostObject(wrap,@"m_oWCPayInfoItem",nil,NO);
    NSString *url=WUHostString(WUHostObject(pay,@"m_c2cNativeUrl",nil,NO),8192);
    NSURLComponents *u=url.length?[NSURLComponents componentsWithString:url]:nil;
    BOOL native=[u.scheme.lowercaseString isEqual:@"wxpay"] && !u.user.length && !u.password.length && !u.port;
    BOOL red=native && [u.host.lowercaseString isEqual:@"c2cbizmessagehandler"] && [u.path isEqual:@"/hongbao/receivehongbao"];
    BOOL transfer=native && [u.host.lowercaseString isEqual:@"c2ctransfer"];
    NSNumber *inner=WUStatsHostInteger(wrap,@"m_uiAppMsgInnerType"), *scene=WUStatsHostInteger(pay,@"m_sceneId");
    // 0x1595188..51fc: inner=2001, scene=1003 => transfer, else redpacket.
    // Missing scene is unknown, NOT zero; do not copy textual/URL-substring heuristics.
    if(inner.unsignedLongLongValue==2001 && scene) { if(scene.unsignedLongLongValue==1003) transfer=YES; else red=YES; }
    if(red && transfer) return @"appUnknown";
    return red?@"redpacket":(transfer?@"transfer":@"appUnknown");
}
NSDictionary *WUStatsDecodeHostPage(NSArray *page, uint32_t left, NSString *account, NSString *session, BOOL app) {
    if(!NSThread.isMainThread || !account.length || !session.length || ![page isKindOfClass:NSArray.class] || page.count>200) return nil;
    @try {
        BOOL group=[session hasSuffix:@"@chatroom"]; uint32_t minID=0,minTime=0;
        NSMutableArray *records=[NSMutableArray arrayWithCapacity:page.count];
        for(id wrap in page) {
            if(!WUHostIs(wrap,@"CMessageWrap")) return nil;
            NSString *from=WUHostString(WUHostObject(wrap,@"m_nsFromUsr",nil,NO),256), *to=WUHostString(WUHostObject(wrap,@"m_nsToUsr",nil,NO),256);
            BOOL belongs=group?([from isEqual:session] || ([from isEqual:account] && [to isEqual:session])):(([from isEqual:account] && [to isEqual:session]) || ([from isEqual:session] && [to isEqual:account]));
            if(!from.length || !belongs) return nil;
            NSNumber *local=WUStatsHostInteger(wrap,@"m_uiMesLocalID"), *time=WUStatsHostInteger(wrap,@"m_uiCreateTime"), *type=WUStatsHostInteger(wrap,@"m_uiMessageType"), *sid=WUStatsHostInteger(wrap,@"m_n64MesSvrID");
            if(!WUUInt32(local) || !WUUInt32(time) || !WUUInt32(type)) return nil;
            uint32_t lid=local.unsignedIntValue,t=time.unsignedIntValue;
            // 0x1597798..7824: minimum positive local ID and minimum positive
            // time at that ID. Not lastObject; local IDs are source-scoped cursors.
            if(lid && (!minID || lid<minID)) { minID=lid; minTime=t; }
            else if(lid==minID && t && (!minTime || t<minTime)) minTime=t;
            NSString *sender=group?([from isEqual:account]?account:WUHostString(WUHostObject(wrap,@"m_nsRealChatUsr",nil,NO),256)):from;
            if(group && [sender isEqual:session]) sender=nil;
            NSString *kind=@"other";
            switch(type.unsignedIntValue) { case 1:kind=@"text";break; case 3:kind=@"image";break; case 34:kind=@"voice";break; case 43:case 62:kind=@"video";break; case 47:kind=@"emoji";break; case 48:kind=@"location";break; case 49:kind=WUStatsAppType(wrap);break; case 10000:kind=@"system";break; default:break; }
            id content=[kind isEqual:@"text"]?WUHostObject(wrap,@"m_nsContent",nil,NO):nil;
            NSString *text=[content isKindOfClass:NSString.class]?[content copy]:@"";
            if(text.length>8192) text=[text substringToIndex:8192];
            [records addObject:@{@"sid":sid.stringValue?:@"",@"lid":local.stringValue,@"source":app?@"app":@"normal",@"sender":sender?:@"",@"time":time,@"type":kind,@"text":text?:@""}];
        }
        if(page.count && !minID) return nil;
        return @{@"records":records,@"next":@{@"id":@(minID),@"time":@(minTime)},@"done":@(page.count==0 && (app || left==0))};
    } @catch(__unused NSException *e) { return nil; }
}
static NSArray *WUReadPage(WUStatsBinding *b,NSDictionary *cursor,uint32_t *left,NSString **failure) {
    SEL sel=NSSelectorFromString(@"GetMsgByCreateTime:FromID:FromCreateTime:Limit:LeftCount:");
    Class cls=NSClassFromString(@"CMessageMgr");
    if (!cls || ![b.messageManager isKindOfClass:cls] || !b.verifiedEncoding.length) { *failure=@"尚未接入：缺少经核验的 CMessageMgr 签名"; return nil; }
    Method method=class_getInstanceMethod(object_getClass(b.messageManager),sel);
    const char *encoding=method ? method_getTypeEncoding(method) : NULL;
    if (!encoding || strcmp(encoding,b.verifiedEncoding.UTF8String)!=0) { *failure=@"不可用：宿主签名与核验版本不匹配"; return nil; }
    NSMethodSignature *sig=[NSMethodSignature signatureWithObjCTypes:encoding];
    BOOL ok=sig.numberOfArguments==7 && strcmp(WUUnqualified(sig.methodReturnType),"@")==0;
    if (ok) ok=strcmp(WUUnqualified([sig getArgumentTypeAtIndex:2]),"@")==0;
    for (NSUInteger i=3;ok && i<=5;i++) { const char *t=WUUnqualified([sig getArgumentTypeAtIndex:i]); ok=!strcmp(t,"I") || !strcmp(t,"i"); }
    const char *out=ok ? WUUnqualified([sig getArgumentTypeAtIndex:6]) : "";
    ok=ok && (!strcmp(out,"^I") || !strcmp(out,"^i"));
    if (!ok || !WUUInt32(cursor[@"id"]) || !WUUInt32(cursor[@"time"])) { *failure=@"不可用：未支持的参数类型或游标"; return nil; }
    uint32_t mid=[cursor[@"id"] unsignedIntValue],time=[cursor[@"time"] unsignedIntValue],limit=200,count=0; uint32_t *countPtr=&count;
    if ((!strcmp(WUUnqualified([sig getArgumentTypeAtIndex:3]),"i") && mid>INT32_MAX) || (!strcmp(WUUnqualified([sig getArgumentTypeAtIndex:4]),"i") && time>INT32_MAX)) { *failure=@"不可用：游标超出已核验有符号参数范围"; return nil; }
    @try {
        NSInvocation *call=[NSInvocation invocationWithMethodSignature:sig]; call.target=b.messageManager; call.selector=sel;
        __unsafe_unretained NSString *session=b.session;
        [call setArgument:&session atIndex:2]; [call setArgument:&mid atIndex:3]; [call setArgument:&time atIndex:4]; [call setArgument:&limit atIndex:5]; [call setArgument:&countPtr atIndex:6]; [call invoke];
        __unsafe_unretained id value=nil; [call getReturnValue:&value];
        if (![value isKindOfClass:NSArray.class] || [value count]>200 || (!strcmp(out,"^i") && (int32_t)count<0)) { *failure=@"读取失败：返回页或剩余计数无效"; return nil; }
        *left=count; return [value copy];
    } @catch (__unused NSException *e) { *failure=@"读取失败：宿主异常（未记录聊天内容）"; return nil; }
}

@interface WUStatsJob ()
@property(nonatomic,strong) WUStatsBinding *binding;
@property(nonatomic,strong) WUStatsAccumulator *accumulator;
@property(nonatomic,strong) NSDictionary *cursor;
@property(nonatomic,strong) NSMutableSet *cursors;
@property(nonatomic,copy) void (^update)(NSDictionary *,NSString *);
@property(nonatomic,readwrite) BOOL cancelled;
@property(nonatomic) BOOL started;
@property(nonatomic) NSUInteger pages;
@property(nonatomic) NSUInteger phasePages;
@property(nonatomic) BOOL appPhase;
@property(nonatomic) NSUInteger readCount;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL finishing;
@property(nonatomic,copy) NSDictionary *profileSnapshot;
@property(nonatomic,copy) NSString *profileIssue;
@property(nonatomic) BOOL waitingForProfile;
- (void)acceptProfile:(NSDictionary *)snapshot issue:(NSString *)issue;
@end
@implementation WUStatsJob
- (instancetype)initWithBinding:(WUStatsBinding *)b {
    if ((self=[super init])) {
        // Freeze identity, callbacks and manager. Do not retain mutable external context.
        _binding=[WUStatsBinding new]; _binding.account=[b.account copy]; _binding.session=[b.session copy]; _binding.group=b.group; _binding.messageManager=b.messageManager;
        _binding.verifiedEncoding=[b.verifiedEncoding copy]; _binding.stillCurrent=[b.stillCurrent copy]; _binding.decodePage=[b.decodePage copy]; _binding.initialCursor=[b.initialCursor copy];
        _binding.readProfile=[b.readProfile copy];
        _binding.scanAppMessages=b.scanAppMessages; _binding.appEncoding=[b.appEncoding copy]; _binding.decodeAppPage=[b.decodeAppPage copy];
        _cursor=_binding.initialCursor; _cursors=[NSMutableSet set];
        _binding.dateRange=[b.dateRange copy]; _binding.pageLimit=MAX(1,MIN(100,b.pageLimit)); _binding.timeZone=[b.timeZone copy]; _binding.descendingTimeVerified=b.descendingTimeVerified;
        _accumulator=[[WUStatsAccumulator alloc] initWithTimeZone:_binding.timeZone group:b.group]; _accumulator.dateRange=_binding.dateRange;
    } return self;
}
- (void)cancel { NSAssert(NSThread.isMainThread,@"main thread required"); self.cancelled=YES; self.generation++; self.accumulator=nil; self.profileSnapshot=nil; self.profileIssue=nil; self.waitingForProfile=NO; self.update=nil; self.binding=nil; [self.cursors removeAllObjects]; }
- (BOOL)valid {
    if(self.cancelled) return NO;
    @try { return self.binding.account.length && self.binding.session.length && self.binding.stillCurrent && self.binding.stillCurrent(); }
    @catch (__unused NSException *e) { return NO; }
}
- (void)finish:(NSString *)status complete:(BOOL)complete {
    if (![self valid]) { void (^notify)(NSDictionary *,NSString *)=self.update; [self cancel]; if(notify) notify(nil,@"已停止：账号或会话已变化，结果已清除"); return; }
    if(self.finishing) return; self.finishing=YES;
    NSArray *records=[[NSArray alloc] initWithArray:self.accumulator.records copyItems:YES];
    NSTimeZone *zone=[self.accumulator.calendar.timeZone copy]; BOOL group=self.accumulator.group;
    NSString *account=[self.binding.account copy], *peer=[self.binding.session copy];
    NSUInteger duplicates=self.accumulator.duplicates, pages=self.pages, scanned=self.readCount, generation=self.generation;
    NSDictionary *profile=self.profileSnapshot; NSString *profileIssue=[self.profileIssue copy]; self.profileSnapshot=nil;
    self.accumulator=nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            WUStatsAccumulator *snapshot=[[WUStatsAccumulator alloc] initWithTimeZone:zone group:group];
            snapshot.records=[records mutableCopy]; snapshot.duplicates=duplicates;
            NSMutableDictionary *result=[[snapshot result] mutableCopy];
            result[@"details"]=WUStatsDetails(records,account,peer,group,zone);
            if(profile) result[@"profile"]=WUStatsProfileSummary(profile);
            if(profileIssue.length) result[@"profileIssue"]=profileIssue;
            result[@"complete"]=@(complete); result[@"pages"]=@(pages); result[@"scanned"]=@(scanned); result[@"scope"]=@"当前会话；仅经核验分页接口可见的本地记录";
            dispatch_async(dispatch_get_main_queue(),^{
                if(self.cancelled || generation!=self.generation) return;
                void (^notify)(NSDictionary *,NSString *)=self.update;
                if(![self valid]) { [self cancel]; if(notify) notify(nil,@"已停止：账号或会话已变化，结果已清除"); return; }
                self.update=nil; self.binding=nil; self.generation++; self.cancelled=YES;
                if(notify) notify(result,status);
            });
        }
    });
}
- (void)start:(void (^)(NSDictionary *,NSString *))update {
    NSAssert(NSThread.isMainThread,@"main thread required"); if(self.started || self.cancelled) return; self.started=YES; self.update=[update copy];
    if (![self valid] || !self.binding.decodePage) { void (^notify)(NSDictionary *,NSString *)=self.update; [self cancel]; if(notify) notify(nil,@"尚未接入：缺少稳定账号/会话校验或宿主页解码器"); return; }
    if(self.binding.readProfile) {
        self.waitingForProfile=YES; __weak WUStatsJob *weak=self;
        // Profile is optional. A failed or non-calling provider must not freeze local-message scanning.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5ull*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            [weak acceptProfile:nil issue:@"本地资料读取超时，画像保持未知；消息统计继续。"];
        });
        @try {
            self.binding.readProfile(^BOOL{ return [weak valid] && weak.waitingForProfile; },^(NSDictionary *snapshot) {
                [weak acceptProfile:snapshot issue:nil];
            });
        } @catch(__unused NSException *e) {
            [self acceptProfile:nil issue:@"本地资料适配异常，画像保持未知；消息统计继续。"];
        }
    } else [self step];
}
- (void)acceptProfile:(NSDictionary *)snapshot issue:(NSString *)issue {
    if(!NSThread.isMainThread) { __weak WUStatsJob *weak=self; dispatch_async(dispatch_get_main_queue(),^{ [weak acceptProfile:snapshot issue:issue]; }); return; }
    if(!self.waitingForProfile) return;
    if(![self valid]) { [self cancel]; return; }
    self.waitingForProfile=NO;
    BOOL shape=[snapshot isKindOfClass:NSDictionary.class] && [snapshot[@"peer"] isKindOfClass:NSDictionary.class] &&
        [snapshot[@"members"] isKindOfClass:NSArray.class] && [snapshot[@"commonGroups"] isKindOfClass:NSArray.class] && [snapshot[@"scope"] isKindOfClass:NSString.class];
    self.profileSnapshot=shape?[snapshot copy]:nil;
    self.profileIssue=shape?nil:(issue?:@"没有可用的本地资料快照；画像未知，消息统计继续。");
    [self step];
}
- (void)scheduleStep {
    if(self.update) self.update(nil,[NSString stringWithFormat:@"本地扫描 %lu 页 / %lu 条…",(unsigned long)self.pages,(unsigned long)self.readCount]);
    NSUInteger generation=self.generation; __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_main_queue(), ^{ WUStatsJob *job=weakSelf; if(job && !job.cancelled && job.generation==generation) [job step]; });
}
- (void)phaseFinished {
    if(!self.appPhase && self.binding.scanAppMessages) {
        if(!self.binding.decodeAppPage) { [self finish:@"已截断：App解码器不可用；普通消息结果保留" complete:NO]; return; }
        // 0x15994bc..9538: phase=App, adjacentValid=false, App cursor=(0,0).
        self.appPhase=YES; self.phasePages=0; self.accumulator.interactionPhase++;
        self.cursor=@{@"id":@0,@"time":@0}; [self.cursors removeAllObjects];
        [self scheduleStep];
    } else [self finish:@"完成：仅本地可见范围，非服务器全部历史" complete:YES];
}
- (void)step {
    if(![self valid]) { [self finish:@"已取消" complete:NO]; return; }
    if(self.readCount>=20000 || self.pages>=self.binding.pageLimit) { [self finish:@"已截断：达到共享预算（总上限20,000条/100页，含App补页）" complete:NO]; return; }
    self.pages++; self.phasePages++; // Count rejected attempts in the same budget.
    NSString *failure=nil; uint32_t left=0;
    NSArray *page=self.appPhase?WUReadAppPage(self.binding,self.cursor,&failure):WUReadPage(self.binding,self.cursor,&left,&failure);
    self.readCount+=page.count;
    if(![self valid]) { [self finish:@"已取消" complete:NO]; return; }
    if (!page) { [self finish:failure?:@"读取失败" complete:NO]; return; }
    NSDictionary *decoded=nil;
    @try { decoded=self.appPhase?self.binding.decodeAppPage(page,self.cursor):self.binding.decodePage(page,left,self.cursor); } @catch (__unused NSException *e) { decoded=nil; }
    if (![self valid]) { [self finish:@"已取消" complete:NO]; return; }
    if (![decoded isKindOfClass:NSDictionary.class] || ![decoded[@"records"] isKindOfClass:NSArray.class] || ![decoded[@"done"] isKindOfClass:NSNumber.class] || [decoded[@"records"] count]!=page.count || ![self.accumulator addRecords:decoded[@"records"]]) { [self finish:@"读取停止：页解码不完整或记录无效" complete:NO]; return; }
    BOOL done=[decoded[@"done"] boolValue];
    if (done) { if(left!=0 || (self.appPhase && page.count)) [self finish:@"已截断：结束标志与返回页矛盾" complete:NO]; else [self phaseFinished]; return; }
    NSDictionary *next=decoded[@"next"];
    if (![next isKindOfClass:NSDictionary.class] || !WUUInt32(next[@"id"]) || !WUUInt32(next[@"time"])) { [self finish:@"已截断：无有效下一页游标" complete:NO]; return; }
    uint32_t oldTime=[self.cursor[@"time"] unsignedIntValue],oldID=[self.cursor[@"id"] unsignedIntValue],newTime=[next[@"time"] unsignedIntValue],newID=[next[@"id"] unsignedIntValue];
    // 0x158ca0c/18: (0,0) means initial page. 0x1598874..88f0
    // selects minimum positive local ID and its time, independent of array order.
    BOOL initial=self.phasePages==1 && oldID==0 && oldTime==0;
    // App 0x1597c30..c94 allows either lower ID OR lower time; ordinary
    // semantics stay unchanged. Neither proves descending creation-time order.
    BOOL advances=(initial && newID>0) || (newID>0 && (newID<oldID || (self.appPhase?newTime<oldTime:(newID==oldID && newTime<oldTime))));
    NSString *key=[NSString stringWithFormat:@"%u:%u",newTime,newID];
    if (!page.count || !advances || [self.cursors containsObject:key]) { [self finish:@"已截断：游标未前进或页面重复" complete:NO]; return; }
    // Only a proven descending-time contract permits early stop. Equality must
    // continue: further local IDs can share the start second. ID order alone is insufficient.
    if(!self.appPhase && self.binding.descendingTimeVerified && self.binding.dateRange && newTime>0 && newTime<[self.binding.dateRange[@"start"] doubleValue]) { [self phaseFinished]; return; }
    [self.cursors addObject:key]; self.cursor=[next copy];
    [self scheduleStep];
}
@end

#if !TARGET_OS_OSX
static char WUStatsOwnerKey;
@interface WUStatsController : UITableViewController
@property(nonatomic,strong) WUStatsBinding *binding;
@property(nonatomic,strong) WUStatsJob *job;
@property(nonatomic,strong) WUStatsOverviewJob *overviewJob;
@property(nonatomic) BOOL overview;
@property(nonatomic,strong) NSArray<NSDictionary *> *sections;
@property(nonatomic,copy) NSString *status;
@property(nonatomic,strong) NSTimer *contextTimer;
@property(nonatomic,copy) NSDictionary *visits;
@property(nonatomic,copy) NSDictionary *lastResult;
@property(nonatomic,copy) NSArray<NSString *> *sectionOrder;
@end
@implementation WUStatsController
- (BOOL)scanning { return (self.job && !self.job.cancelled) || (self.overviewJob && !self.overviewJob.cancelled); }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"本地消息统计"; self.status=@"尚未扫描"; self.sections=@[];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"扫描" style:UIBarButtonItemStylePlain target:self action:@selector(scan)];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=48;
    [self render:nil];
    [self reloadVisits];
}
- (void)reloadVisits {
    if(!self.binding.visitSnapshot) return;
    __weak typeof(self) weak=self;
    self.binding.visitSnapshot(^(NSDictionary *snapshot) { WUStatsController *v=weak; if(!v || !v.binding || !v.binding.stillCurrent()) return; v.visits=snapshot; [v render:v.lastResult]; });
}
- (void)chooseRange {
    if(!self.binding || [self scanning]) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"统计日期（含起止日）" message:[NSString stringWithFormat:@"格式 yyyy-MM-dd；时区 %@。按日历转换为起日00:00至末日次日00:00。未知时间不进入范围统计。",self.binding.timeZone.name] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"起日，例如 2026-01-01"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"末日，例如 2026-11-01"; }];
    __weak typeof(self) weak=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        WUStatsController *v=weak; if(!v.binding || !v.binding.stillCurrent()) return;
        NSDictionary *range=WUStatsDateRange(alert.textFields[0].text,alert.textFields[1].text,v.binding.timeZone);
        if(!range) { v.status=@"日期无效：请填写存在的日期，起日不得晚于末日"; [v render:v.lastResult]; return; }
        [v.job cancel]; [v.overviewJob cancel]; v.job=nil; v.binding.dateRange=range; v.status=@"日期已更新，请手动扫描"; [v render:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)confirmClearVisits {
    if(!self.binding.clearVisits) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"清空本账号访问日志？" message:@"只清理本插件记录，不删除微信聊天。不可恢复；之后继续记录真实出现事件。" preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weak=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        WUStatsController *v=weak; if(!v.binding || !v.binding.stillCurrent()) return;
        v.binding.clearVisits(^(BOOL ok){ WUStatsController *c=weak; if(!c.binding || !c.binding.stillCurrent()) return; c.status=ok?@"本账号访问日志已清空":@"清空失败，保留旧日志"; [c reloadVisits]; });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; __weak typeof(self) weakSelf=self;
    self.contextTimer=[NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *timer) {
        WUStatsController *vc=weakSelf; if(!vc || !vc.binding) return;
        BOOL valid=NO; @try {valid=vc.binding.stillCurrent && vc.binding.stillCurrent();} @catch (__unused NSException *e) {}
        if(!valid) { [vc.job cancel]; [vc.overviewJob cancel]; vc.job=nil; vc.binding=nil; vc.visits=nil; vc.status=@"账号或会话已变化，结果已清除"; [vc render:nil]; }
    }];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.contextTimer invalidate]; self.contextTimer=nil; [self.job cancel]; [self.overviewJob cancel]; self.job=nil; self.status=@"已停止"; [self render:nil]; }
- (void)close { [self.job cancel]; [self.overviewJob cancel]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)scan {
    if([self scanning]) { [self.job cancel]; [self.overviewJob cancel]; self.job=nil; self.status=@"已取消并清除结果"; [self render:nil]; return; }
    if(!self.binding) { self.status=@"尚未接入：主工程尚未绑定经核验的宿主账号、会话、签名与解码器"; [self render:nil]; return; }
    self.status=@"准备本地读取…";
    __weak typeof(self) weakSelf=self;
    void (^update)(NSDictionary *,NSString *)=^(NSDictionary *result,NSString *status) { WUStatsController *vc=weakSelf; if(!vc) return; vc.status=status; [vc render:result]; };
    if(self.overview) { self.overviewJob=[[WUStatsOverviewJob alloc] initWithBinding:self.binding]; [self render:nil]; [self.overviewJob start:update]; }
    else { self.job=[[WUStatsJob alloc] initWithBinding:self.binding]; [self render:nil]; [self.job start:update]; }
}
- (NSString *)layoutKey { return [@"WU.stats.sections." stringByAppendingString:WUStatsVisitID(self.binding.account,@"")]; }
- (void)configureSections {
    if(!self.binding || !self.binding.stillCurrent() || self.presentedViewController) return;
    NSDictionary *labels=@{@"sessions":@"会话总览",@"visits":@"访问榜",@"overview":@"概览",@"selfPeer":@"我与对方汇总",@"journey":@"关系历程",@"types":@"类型",@"days":@"日历",@"hours":@"小时",@"speakers":@"发言",@"replies":@"回复",@"openers":@"开场",@"closers":@"收尾",@"icebreakers":@"破冰",@"bursts":@"连发",@"words":@"热词",@"rank":@"排行范围",@"private":@"私聊排行",@"chatroom":@"群排行",@"myGroups":@"我的发言最多的群"};
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"板块选择与顺序" message:@"勾选项按序显示；点选后可隐藏或上移。不改变扫描来源和统计分母。" preferredStyle:UIAlertControllerStyleActionSheet];
    NSMutableArray *keys=[self.sectionOrder mutableCopy]; for(NSString *key in WUStatsOptionalSections()) if(![keys containsObject:key]) [keys addObject:key];
    for(NSString *key in keys) {
        BOOL selected=[self.sectionOrder containsObject:key];
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ %@",selected?@"✓":@"○",labels[key]] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self dismissViewControllerAnimated:YES completion:^{
                if(!self.binding || !self.binding.stillCurrent()) return;
                UIAlertController *edit=[UIAlertController alertControllerWithTitle:labels[key] message:nil preferredStyle:UIAlertControllerStyleAlert];
                void (^commit)(BOOL)=^(BOOL move) {
                    if(!self.binding || !self.binding.stillCurrent()) return;
                    NSMutableArray *order=[self.sectionOrder mutableCopy]; NSUInteger i=[order indexOfObject:key];
                    if(move && i!=NSNotFound && i>0) [order exchangeObjectAtIndex:i withObjectAtIndex:i-1];
                    else if(!move) { if(i==NSNotFound) [order addObject:key]; else [order removeObjectAtIndex:i]; }
                    self.sectionOrder=WUStatsSectionOrder(order); [NSUserDefaults.standardUserDefaults setObject:self.sectionOrder forKey:[self layoutKey]]; [self render:self.lastResult];
                };
                [edit addAction:[UIAlertAction actionWithTitle:selected?@"隐藏":@"显示（追加到末尾）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ commit(NO); }]];
                if(selected && [self.sectionOrder indexOfObject:key]>0) [edit addAction:[UIAlertAction actionWithTitle:@"上移一位" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ commit(YES); }]];
                [edit addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:edit animated:YES completion:nil];
            }];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"恢复全部及默认顺序" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ if(!self.binding || !self.binding.stillCurrent()) return; self.sectionOrder=WUStatsOptionalSections(); [NSUserDefaults.standardUserDefaults removeObjectForKey:[self layoutKey]]; [self render:self.lastResult]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=self.view; a.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),80,1,1); [self presentViewController:a animated:YES completion:nil];
}
- (void)render:(NSDictionary *)r {
    self.lastResult=r;
    if(!self.sectionOrder) self.sectionOrder=WUStatsSectionOrder(self.binding.account.length?[NSUserDefaults.standardUserDefaults objectForKey:[self layoutKey]]:nil);
    NSMutableArray *sections=[NSMutableArray array];
    [sections addObject:@{@"title":@"时间范围与访问日志",@"rows":@[self.binding.dateRange[@"label"]?:[NSString stringWithFormat:@"全部可见日期 · %@（点选起止）",self.binding.timeZone.name?:@"无上下文"],@"重置日期为全部",@"清空本账号访问日志",self.overview?@"扫描范围：已加载私聊/群聊消息数排行（点选切换）":@"扫描范围：当前会话（点选切换）",@"板块选择与排序"]}];
    if(self.binding.sessions.count) {
        NSMutableDictionary *counts=[NSMutableDictionary dictionary];
        for(NSDictionary *row in self.binding.sessions) { NSString *kind=row[@"kind"]; counts[kind]=@([counts[kind] unsignedIntegerValue]+([kind isEqual:@"unknown"]?[row[@"count"] unsignedIntegerValue]:1)); }
        [sections addObject:@{@"title":@"宿主已加载会话总览（非好友画像）",@"rows":@[[NSString stringWithFormat:@"私聊 %@ · 群聊 %@ · 其他 %@ · 未知条目 %@",counts[@"private"]?:@0,counts[@"chatroom"]?:@0,counts[@"other"]?:@0,counts[@"unknown"]?:@0],@"来自 MainSessionMgr 三数组的未过滤快照，已知会话去重；不保证全部历史/已删除会话。未知条目可能跨数组重复。"]}];
    }
    if(r[@"profile"]) [sections addObject:@{@"title":@"本地联系人 / 群成员画像",@"rows":WUStatsProfileLines(r[@"profile"],self.binding.timeZone)}];
    else if([r[@"profileIssue"] isKindOfClass:NSString.class]) [sections addObject:@{@"title":@"本地资料读取状态",@"rows":@[r[@"profileIssue"]]}];
    NSMutableDictionary *names=[NSMutableDictionary dictionary];
    NSArray *visitRanking=WUStatsVisitRanking(self.visits[@"events"]?:@[],self.binding.dateRange);
    for(NSDictionary *row in self.binding.sessions) if([row[@"username"] length]) names[WUStatsVisitID(WUStatsVisitID(self.binding.account,@""),row[@"username"])]=row[@"username"];
    NSMutableArray *visitRows=[NSMutableArray arrayWithObjects:@"只记录启用统计工具后的真实前台聊天出现；同一最近会话12秒去抖，不补造历史，不等于消息数/最常聊。",@"账号隔离原子日志：最多4096条/1MiB，满后停止；日期范围同消息筛选。日志无正文、无明文账号/会话。",nil];
    if([self.visits[@"error"] length]) [visitRows addObject:self.visits[@"error"]];
    if([self.visits[@"full"] boolValue]) [visitRows addObject:@"日志已满：访问榜只是已记录范围，清空后才能继续记录。"];
    for(NSDictionary *row in visitRanking) { NSString *key=row[@"id"]; [visitRows addObject:[NSString stringWithFormat:@"%@ · %@：%@ 次",names[key]?:[key substringToIndex:12],row[@"kind"],row[@"count"]]]; }
    if(!visitRanking.count) [visitRows addObject:@"此范围暂无已记录访问（不推断历史）"];
    [sections addObject:@{@"title":@"会话访问次数榜",@"rows":visitRows}];
    [sections addObject:@{@"title":@"状态与范围",@"rows":@[self.status?:@"",@"只读所选范围本地消息；消息统计不落盘、不联网、不包含 AI。需手动扫描；访问日志另按启用后真实事件记录。",@"总上限20,000条/100页；排行另限用户名顺序前50个已加载可分类会话，所有子扫描共享页数预算。未知时间不进入日期范围；同秒消息不推断互动。",@"规则统计不是社交意图：6小时新段、24小时破冰、5分钟同人连发。首尾不补猜开场。"]}];
    if([r[@"overview"] boolValue]) {
        NSMutableArray *rows=[NSMutableArray arrayWithObjects:[NSString stringWithFormat:@"已处理 %@ / %@ 个可靠会话 · %@ 页 · %@ 条扫描记录",r[@"processed"],r[@"sessions"],r[@"pages"],r[@"scanned"]],[r[@"complete"] boolValue]?@"完成已加载可分类会话；不是服务器全部历史":@"部分排行/截断：未扫会话可能更活跃，不称全账号最常聊",nil];
        [sections addObject:@{@"title":@"最常聊 · 本地消息数（所选日期）",@"rows":rows}];
        for(NSString *kind in @[@"private",@"chatroom"]) {
            NSMutableArray *rank=[NSMutableArray array];
            for(NSDictionary *row in r[@"rank"]) if([row[@"kind"] isEqual:kind]) [rank addObject:[NSString stringWithFormat:@"%@：%@ 条%@",row[@"id"],row[@"count"],[row[@"complete"] boolValue]?@"":@"（部分/下界）"]];
            [sections addObject:@{@"title":[kind isEqual:@"private"]?@"私聊消息数榜（非好友关系证明）":@"群会话消息数榜",@"rows":rank.count?rank:@[@"无样本"]}];
        }
    }
    if(r && ![r[@"overview"] boolValue]) {
        id mean=r[@"replyMeanSeconds"];
        NSString *meanText=[mean isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:@"%.1f 秒",[mean doubleValue]] : @"无样本";
        [sections addObject:@{@"title":@"概览",@"rows":@[[NSString stringWithFormat:@"%@ · %@",[r[@"group"] boolValue]?@"群聊":@"私聊",r[@"timezone"]],[NSString stringWithFormat:@"%@ 条 · %@ 页 · 去重 %@ 条",r[@"total"],r[@"pages"],r[@"duplicates"]],[NSString stringWithFormat:@"未知ID %@ · 无效时间 %@ · 未知发送者 %@",r[@"unknownID"],r[@"unknownTime"],r[@"unknownSender"]],[NSString stringWithFormat:@"活跃 %lu 天 · 最长连续 %@ 天 · 深夜 %@ 条",(unsigned long)[r[@"days"] count],r[@"longestStreak"],r[@"night"]],[NSString stringWithFormat:@"相邻异人回复 %@ 对 · 均值 %@",r[@"replyCount"],meanText],[r[@"complete"] boolValue]?@"已到接口返回的本地边界":@"部分结果 / 已截断，不能称全部历史"]}];
        NSArray *maps=@[@[@"types",@"消息主类型"],@[@"days",@"日历分布"],@[@"hours",@"小时分布"]];
        for(NSArray *entry in maps) { NSMutableArray *rows=[NSMutableArray array]; NSDictionary *d=r[entry[0]];
            for(NSString *k in [d.allKeys sortedArrayUsingSelector:@selector(compare:)]) [rows addObject:[NSString stringWithFormat:@"%@：%@",[k isEqual:@"appUnknown"]?@"App类型未知/支付证据不足":k,d[k]]];
            [sections addObject:@{@"title":entry[1],@"rows":rows.count?rows:@[@"无样本"]}]; }
        for(NSArray *entry in @[@[@"speakers",@"发言榜"],@[@"replies",@"回复对数"],@[@"openers",@"开场者"],@[@"closers",@"收尾者"],@[@"icebreakers",@"破冰"],@[@"bursts",@"连发"],@[@"words",@"本地热词（前100）"]]) {
            NSMutableArray *rows=[NSMutableArray array]; NSArray *list=r[entry[0]]; NSUInteger total=0; for(NSDictionary *item in list) total+=[item[@"count"] unsignedIntegerValue];
            for(NSDictionary *item in list) { if([entry[0] isEqual:@"words"] && rows.count==100) break;
                NSString *suffix=[entry[0] isEqual:@"openers"] && total ? [NSString stringWithFormat:@"（%.1f%%）",100.0*[item[@"count"] unsignedIntegerValue]/total] : @"";
                [rows addObject:[NSString stringWithFormat:@"%@：%@%@",item[@"id"],item[@"count"],suffix]]; }
            [sections addObject:@{@"title":entry[1],@"rows":rows.count?rows:@[@"无样本"]}];
        }
    }
    if(r[@"details"]) {
        NSDictionary *d=r[@"details"], *summary=d[@"summary"];
        NSMutableArray *rows=[NSMutableArray arrayWithObject:[NSString stringWithFormat:@"分母：去重且满足所选日期的全部 %@ 条（含系统消息）；未知发送者单列，不算对方。",d[@"denominator"]]];
        NSArray *keys=[r[@"group"] boolValue]?@[@"self",@"others",@"unknown"]:@[@"self",@"peer",@"unknown"];
        NSDictionary *names=@{@"self":@"我",@"peer":@"对方",@"others":@"其他群成员",@"unknown":@"未知/非会话双方"};
        for(NSString *key in keys) {
            NSDictionary *b=summary[key]; NSString *share=[b[@"shareOfTotal"] isKindOfClass:NSNumber.class]?[NSString stringWithFormat:@"%.1f%%",100*[b[@"shareOfTotal"] doubleValue]]:@"无样本";
            NSMutableArray *types=[NSMutableArray array]; for(NSString *type in [b[@"types"] allKeys]) [types addObject:[NSString stringWithFormat:@"%@ %@",type,b[@"types"][type]]]; [types sortUsingSelector:@selector(compare:)];
            [rows addObject:[NSString stringWithFormat:@"%@：%@ 条 · %@ · 活跃 %@ 天\n%@",names[key],b[@"count"],share,b[@"activeDays"],[types componentsJoinedByString:@" / "]]];
        }
        [sections addObject:@{@"title":@"我与对方汇总",@"rows":rows}];
        NSDateFormatter *f=[NSDateFormatter new]; f.timeZone=self.binding.timeZone; f.dateFormat=@"yyyy-MM-dd HH:mm:ss";
        NSMutableArray *journey=[NSMutableArray arrayWithObject:@"只展示本次本地可见记录的历程；最早记录不是加好友/入群日，空白日期不推断关系。日期筛选/截断会改变起止。"];
        for(NSString *key in @[@"first",@"last"]) if([d[key] isKindOfClass:NSNumber.class]) [journey addObject:[NSString stringWithFormat:@"%@：%@",[key isEqual:@"first"]?@"最早可见消息":@"最近可见消息",[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:[d[key] doubleValue]]]]];
        for(NSString *type in [[d[@"firstByType"] allKeys] sortedArrayUsingSelector:@selector(compare:)]) [journey addObject:[NSString stringWithFormat:@"首次可见 %@：%@",type,[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:[d[@"firstByType"][type] doubleValue]]]]];
        for(NSDictionary *day in d[@"timeline"]) [journey addObject:[NSString stringWithFormat:@"%@ · %@ 条（我 %@ / %@ %@ / 未知 %@）",day[@"day"],day[@"count"],day[@"self"],[r[@"group"] boolValue]?@"群成员":@"对方",day[[r[@"group"] boolValue]?@"others":@"peer"],day[@"unknown"]]];
        if(![d[@"timeline"] count]) [journey addObject:@"无有效时间样本"];
        [sections addObject:@{@"title":@"关系历程（已见消息）",@"rows":journey}];
    }
    if([r[@"overview"] boolValue]) {
        NSMutableArray *rows=[NSMutableArray arrayWithObject:@"仅上述已扫描群，按我发出的消息数（不含系统/拍一拍）降序；同数按群ID排序。部分扫描值为下界，不称全账号第一。"];
        for(NSDictionary *row in r[@"myGroups"]) [rows addObject:[NSString stringWithFormat:@"%@：我 %@ 条%@",row[@"id"],row[@"count"],[row[@"complete"] boolValue]?@"":@"（部分/下界）"]];
        if(![r[@"myGroups"] count]) [rows addObject:@"无群聊样本"];
        [sections addObject:@{@"title":@"我的发言最多的群",@"rows":rows}];
    }
    [sections addObject:@{@"title":@"尚未实现 / 不伪造",@"rows":@[@"未加载/未知分类/非私聊群聊会话不进入消息数榜；访问榜不冒充最常聊。日期扫描复用ID游标，缺时间单调性证据，当前不会仅凭某页时间越界提前停止。",@"完整好友名册画像尚未验证；现已尝试本地用户名名册与已加载私聊候选，按好友标志分批读取并标记不完整。当前联系人/群成员资料、共同群下界和本地关系日期已单独显示。缺失资料仍未知，不刷新或猜测。",@"支付交易ID未获可靠协议，仍不做交易级合并；localID仅是来源内消息游标，不是交易ID。已接App补页并与普通消息共享100页/20,000条预算，跨源只按已确认serverID去重。红包/转账只读nativePayInfo结构化证据，appUnknown单列未知，不猜正文/XML；加好友/入群宿主事件历程仍未接入。",@"热词使用系统本地词边界，过滤短词、数字、少量停用词；跳过 URL/XML 正文。不保留正文样本，不作 AI 分析。"]}];
    NSDictionary *sectionKeys=@{@"宿主已加载会话总览（非好友画像）":@"sessions",@"会话访问次数榜":@"visits",@"概览":@"overview",@"我与对方汇总":@"selfPeer",@"关系历程（已见消息）":@"journey",@"消息主类型":@"types",@"日历分布":@"days",@"小时分布":@"hours",@"发言榜":@"speakers",@"回复对数":@"replies",@"开场者":@"openers",@"收尾者":@"closers",@"破冰":@"icebreakers",@"连发":@"bursts",@"本地热词（前100）":@"words",@"最常聊 · 本地消息数（所选日期）":@"rank",@"私聊消息数榜（非好友关系证明）":@"private",@"群会话消息数榜":@"chatroom",@"我的发言最多的群":@"myGroups"};
    NSMutableArray *ordered=[NSMutableArray array];
    for(NSDictionary *s in sections) if(!sectionKeys[s[@"title"]]) [ordered addObject:s];
    for(NSString *key in self.sectionOrder) for(NSDictionary *s in sections) if([sectionKeys[s[@"title"]] isEqual:key]) [ordered addObject:s];
    self.sections=ordered;
    self.navigationItem.rightBarButtonItem.title=[self scanning] ? @"取消" : @"扫描";
    [self.tableView reloadData];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if(path.section!=0 || !self.binding || !self.binding.stillCurrent()) return;
    if(path.row==0) [self chooseRange];
    else if(path.row==1) { [self.job cancel]; [self.overviewJob cancel]; self.job=nil; self.binding.dateRange=nil; self.status=@"已重置日期，请手动扫描"; [self render:nil]; }
    else if(path.row==2) [self confirmClearVisits];
    else if(path.row==4) [self configureSections];
    else { [self.job cancel]; [self.overviewJob cancel]; self.overview=!self.overview; self.status=@"范围已切换，请手动扫描"; [self render:nil]; }
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section][@"title"]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"stat"];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"stat"];
    cell.textLabel.numberOfLines=0; cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; cell.textLabel.adjustsFontForContentSizeCategory=YES;
    cell.textLabel.text=self.sections[path.section][@"rows"][path.row]; cell.selectionStyle=path.section==0?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone; cell.accessoryType=path.section==0?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone; return cell;
}
@end
void WUStatsBindOwner(UIViewController *owner,WUStatsBinding *binding) {
    NSCAssert(NSThread.isMainThread,@"main thread required"); objc_setAssociatedObject(owner,&WUStatsOwnerKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void WUShowStats(UIViewController *owner) {
    if(!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{WUShowStats(owner);}); return; }
    if(!owner || owner.presentedViewController) return;
    WUStatsController *vc=[[WUStatsController alloc] initWithStyle:UITableViewStyleInsetGrouped]; vc.binding=objc_getAssociatedObject(owner,&WUStatsOwnerKey);
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:vc]; nav.modalPresentationStyle=UIModalPresentationPageSheet;
    [owner presentViewController:nav animated:YES completion:nil];
}
#endif
