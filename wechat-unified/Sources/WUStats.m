#import "WUStats.h"
#import <objc/runtime.h>
#import <limits.h>
#import <math.h>
#import <string.h>

@implementation WUStatsBinding
- (instancetype)init { if ((self = [super init])) { _account=@""; _session=@""; _verifiedEncoding=@""; _initialCursor=@{}; } return self; }
@end

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
    static NSSet *s; static dispatch_once_t once; dispatch_once(&once, ^{s=[NSSet setWithArray:@[@"text",@"image",@"voice",@"video",@"emoji",@"link",@"file",@"location",@"system",@"pat",@"redpacket",@"transfer",@"other"]];}); return s;
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
@property(nonatomic,strong) NSMutableArray<NSMutableDictionary *> *records;
@property(nonatomic,strong) NSMutableDictionary *serverIndex;
@property(nonatomic,strong) NSMutableDictionary *localIndex;
@property(nonatomic,strong) NSCalendar *calendar;
@property(nonatomic) BOOL group;
@property(nonatomic) NSUInteger duplicates;
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
            if ([r[@"type"] isEqual:@"other"] || (payment && ![@[@"redpacket",@"transfer"] containsObject:r[@"type"]])) r[@"type"]=type;
            if (sid.length && ![r[@"sid"] length]) r[@"sid"]=sid;
        } else {
            index=@(self.records.count);
            [self.records addObject:[@{@"sid":sid,@"lid":lid,@"source":source,@"sender":WUString(input[@"sender"]),@"time":input[@"time"]?:@0,@"type":type,@"text":WUString(input[@"text"]),@"ordinal":index,@"reliable":@(sid.length || lk.length)} mutableCopy]];
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
    for (NSDictionary *r in self.records) { if ([r[@"time"] longLongValue]<=0) { [segment sortUsingComparator:compare]; [ordered addObjectsFromArray:segment]; [segment removeAllObjects]; [ordered addObject:r]; } else [segment addObject:r]; }
    [segment sortUsingComparator:compare]; [ordered addObjectsFromArray:segment];
    NSDictionary *previous=nil;
    for (NSUInteger i=0;i<ordered.count;i++) {
        NSDictionary *r=ordered[i]; int64_t t=[r[@"time"] longLongValue]; NSString *sender=r[@"sender"];
        // Every member of an equal-time cluster is ambiguous, including its edges.
        BOOL tied=(i>0 && [ordered[i-1][@"time"] longLongValue]==t)||(i+1<ordered.count && [ordered[i+1][@"time"] longLongValue]==t);
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
@property(nonatomic) NSUInteger readCount;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL finishing;
@end
@implementation WUStatsJob
- (instancetype)initWithBinding:(WUStatsBinding *)b {
    if ((self=[super init])) {
        // Freeze identity, callbacks and manager. Do not retain mutable external context.
        _binding=[WUStatsBinding new]; _binding.account=[b.account copy]; _binding.session=[b.session copy]; _binding.group=b.group; _binding.messageManager=b.messageManager;
        _binding.verifiedEncoding=[b.verifiedEncoding copy]; _binding.stillCurrent=[b.stillCurrent copy]; _binding.decodePage=[b.decodePage copy]; _binding.initialCursor=[b.initialCursor copy];
        _cursor=_binding.initialCursor; _cursors=[NSMutableSet set];
        _accumulator=[[WUStatsAccumulator alloc] initWithTimeZone:NSTimeZone.localTimeZone group:b.group];
    } return self;
}
- (void)cancel { NSAssert(NSThread.isMainThread,@"main thread required"); self.cancelled=YES; self.generation++; self.accumulator=nil; self.update=nil; self.binding=nil; [self.cursors removeAllObjects]; }
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
    NSUInteger duplicates=self.accumulator.duplicates, pages=self.pages, scanned=self.readCount, generation=self.generation;
    self.accumulator=nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            WUStatsAccumulator *snapshot=[[WUStatsAccumulator alloc] initWithTimeZone:zone group:group];
            snapshot.records=[records mutableCopy]; snapshot.duplicates=duplicates;
            NSMutableDictionary *result=[[snapshot result] mutableCopy];
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
    [self step];
}
- (void)step {
    if(![self valid]) { [self finish:@"已取消" complete:NO]; return; }
    NSString *failure=nil; uint32_t left=0; NSArray *page=WUReadPage(self.binding,self.cursor,&left,&failure);
    if(![self valid]) { [self finish:@"已取消" complete:NO]; return; }
    if (!page) { [self finish:failure?:@"读取失败" complete:NO]; return; }
    NSDictionary *decoded=nil;
    @try { decoded=self.binding.decodePage(page,left,self.cursor); } @catch (__unused NSException *e) { decoded=nil; }
    if (![self valid]) { [self finish:@"已取消" complete:NO]; return; }
    if (![decoded isKindOfClass:NSDictionary.class] || ![decoded[@"records"] isKindOfClass:NSArray.class] || ![decoded[@"done"] isKindOfClass:NSNumber.class] || [decoded[@"records"] count]!=page.count || ![self.accumulator addRecords:decoded[@"records"]]) { [self finish:@"读取停止：页解码不完整或记录无效" complete:NO]; return; }
    self.pages++; self.readCount+=page.count;
    BOOL done=[decoded[@"done"] boolValue];
    if (done) { if(left!=0) [self finish:@"已截断：结束标志与剩余计数矛盾" complete:NO]; else [self finish:@"完成：仅本地可见范围，非服务器全部历史" complete:YES]; return; }
    NSDictionary *next=decoded[@"next"];
    if (![next isKindOfClass:NSDictionary.class] || !WUUInt32(next[@"id"]) || !WUUInt32(next[@"time"])) { [self finish:@"已截断：无有效下一页游标" complete:NO]; return; }
    uint32_t oldTime=[self.cursor[@"time"] unsignedIntValue],oldID=[self.cursor[@"id"] unsignedIntValue],newTime=[next[@"time"] unsignedIntValue],newID=[next[@"id"] unsignedIntValue];
    // 0x158ca0c/18: (0,0) means initial page. 0x1598874..88f0
    // selects minimum positive local ID and its time, independent of array order.
    BOOL initial=self.pages==1 && oldID==0 && oldTime==0;
    BOOL advances=(initial && newID>0) || newID<oldID || (newID==oldID && newTime<oldTime);
    NSString *key=[NSString stringWithFormat:@"%u:%u",newTime,newID];
    if (!page.count || !advances || [self.cursors containsObject:key]) { [self finish:@"已截断：游标未前进或页面重复" complete:NO]; return; }
    [self.cursors addObject:key]; self.cursor=[next copy];
    if(self.readCount>=20000 || self.pages>=100) { [self finish:@"已截断：达到 20,000 条 / 100 页本地上限" complete:NO]; return; }
    if(self.update) self.update(nil,[NSString stringWithFormat:@"本地扫描 %lu 页 / %lu 条…",(unsigned long)self.pages,(unsigned long)self.readCount]);
    NSUInteger generation=self.generation;
    __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_main_queue(), ^{ WUStatsJob *job=weakSelf; if(job && !job.cancelled && job.generation==generation) [job step]; });
}
@end

#if !TARGET_OS_OSX
static char WUStatsOwnerKey;
@interface WUStatsController : UITableViewController
@property(nonatomic,strong) WUStatsBinding *binding;
@property(nonatomic,strong) WUStatsJob *job;
@property(nonatomic,strong) NSArray<NSDictionary *> *sections;
@property(nonatomic,copy) NSString *status;
@property(nonatomic,strong) NSTimer *contextTimer;
@end
@implementation WUStatsController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"本地消息统计"; self.status=@"尚未扫描"; self.sections=@[];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"扫描" style:UIBarButtonItemStylePlain target:self action:@selector(scan)];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=48;
    [self render:nil];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; __weak typeof(self) weakSelf=self;
    self.contextTimer=[NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *timer) {
        WUStatsController *vc=weakSelf; if(!vc || !vc.binding) return;
        BOOL valid=NO; @try {valid=vc.binding.stillCurrent && vc.binding.stillCurrent();} @catch (__unused NSException *e) {}
        if(!valid) { [vc.job cancel]; vc.job=nil; vc.binding=nil; vc.status=@"账号或会话已变化，结果已清除"; [vc render:nil]; }
    }];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.contextTimer invalidate]; self.contextTimer=nil; [self.job cancel]; self.job=nil; self.status=@"已停止"; [self render:nil]; }
- (void)close { [self.job cancel]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)scan {
    if(self.job && !self.job.cancelled) { [self.job cancel]; self.job=nil; self.status=@"已取消并清除结果"; [self render:nil]; return; }
    if(!self.binding) { self.status=@"尚未接入：主工程尚未绑定经核验的宿主账号、会话、签名与解码器"; [self render:nil]; return; }
    self.job=[[WUStatsJob alloc] initWithBinding:self.binding]; self.status=@"准备本地读取…"; [self render:nil];
    __weak typeof(self) weakSelf=self;
    [self.job start:^(NSDictionary *result,NSString *status) { WUStatsController *vc=weakSelf; if(!vc) return; vc.status=status; [vc render:result]; }];
}
- (void)render:(NSDictionary *)r {
    NSMutableArray *sections=[NSMutableArray array];
    [sections addObject:@{@"title":@"状态与范围",@"rows":@[self.status?:@"",@"只读当前会话本地消息；不联网、不落盘、不包含 AI。需手动扫描。",@"上限 20,000 条 / 100 页。无可靠 ID 不合并；未知时间、发送者与同秒消息不推断互动。",@"规则统计不是社交意图：6小时新段、24小时破冰、5分钟同人连发。首尾不补猜开场。"]}];
    if(r) {
        id mean=r[@"replyMeanSeconds"];
        NSString *meanText=[mean isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:@"%.1f 秒",[mean doubleValue]] : @"无样本";
        [sections addObject:@{@"title":@"概览",@"rows":@[[NSString stringWithFormat:@"%@ · %@",[r[@"group"] boolValue]?@"群聊":@"私聊",r[@"timezone"]],[NSString stringWithFormat:@"%@ 条 · %@ 页 · 去重 %@ 条",r[@"total"],r[@"pages"],r[@"duplicates"]],[NSString stringWithFormat:@"未知ID %@ · 无效时间 %@ · 未知发送者 %@",r[@"unknownID"],r[@"unknownTime"],r[@"unknownSender"]],[NSString stringWithFormat:@"活跃 %lu 天 · 最长连续 %@ 天 · 深夜 %@ 条",(unsigned long)[r[@"days"] count],r[@"longestStreak"],r[@"night"]],[NSString stringWithFormat:@"相邻异人回复 %@ 对 · 均值 %@",r[@"replyCount"],meanText],[r[@"complete"] boolValue]?@"已到接口返回的本地边界":@"部分结果 / 已截断，不能称全部历史"]}];
        NSArray *maps=@[@[@"types",@"消息主类型"],@[@"days",@"日历分布"],@[@"hours",@"小时分布"]];
        for(NSArray *entry in maps) { NSMutableArray *rows=[NSMutableArray array]; NSDictionary *d=r[entry[0]];
            for(NSString *k in [d.allKeys sortedArrayUsingSelector:@selector(compare:)]) [rows addObject:[NSString stringWithFormat:@"%@：%@",k,d[k]]];
            [sections addObject:@{@"title":entry[1],@"rows":rows.count?rows:@[@"无样本"]}]; }
        for(NSArray *entry in @[@[@"speakers",@"发言榜"],@[@"replies",@"回复对数"],@[@"openers",@"开场者"],@[@"closers",@"收尾者"],@[@"icebreakers",@"破冰"],@[@"bursts",@"连发"],@[@"words",@"本地热词（前100）"]]) {
            NSMutableArray *rows=[NSMutableArray array]; NSArray *list=r[entry[0]]; NSUInteger total=0; for(NSDictionary *item in list) total+=[item[@"count"] unsignedIntegerValue];
            for(NSDictionary *item in list) { if([entry[0] isEqual:@"words"] && rows.count==100) break;
                NSString *suffix=[entry[0] isEqual:@"openers"] && total ? [NSString stringWithFormat:@"（%.1f%%）",100.0*[item[@"count"] unsignedIntegerValue]/total] : @"";
                [rows addObject:[NSString stringWithFormat:@"%@：%@%@",item[@"id"],item[@"count"],suffix]]; }
            [sections addObject:@{@"title":entry[1],@"rows":rows.count?rows:@[@"无样本"]}];
        }
    }
    [sections addObject:@{@"title":@"尚未实现 / 不伪造",@"rows":@[@"全账号最常聊好友、群浏览访问榜：未接会话枚举/访问事件；消息数不冒充访问量。",@"画像、共同群、年龄/性别/地域/入群日期：没有可靠接口，保持未知。",@"支付交易去重、App 专用补页、完整历程：尚未接入。红包/转账仅接受经核验解码器的互斥分类，不猜 XML。",@"热词使用系统本地词边界，过滤短词、数字、少量停用词；跳过 URL/XML 正文。不保留正文样本，不作 AI 分析。"]}];
    self.sections=sections;
    self.navigationItem.rightBarButtonItem.title=self.job && !self.job.cancelled ? @"取消" : @"扫描";
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section][@"title"]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"stat"];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"stat"];
    cell.textLabel.numberOfLines=0; cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; cell.textLabel.adjustsFontForContentSizeCategory=YES;
    cell.textLabel.text=self.sections[path.section][@"rows"][path.row]; cell.selectionStyle=UITableViewCellSelectionStyleNone; return cell;
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
