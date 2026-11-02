#import "WUStats.h"

@interface WUStatsOverviewJob ()
@property(nonatomic,strong) WUStatsBinding *binding;
@property(nonatomic,strong) WUStatsJob *child;
@property(nonatomic,copy) NSArray *sessions;
@property(nonatomic,copy) NSDictionary *range;
@property(nonatomic,copy) NSTimeZone *zone;
@property(nonatomic,strong) NSMutableArray *rows;
@property(nonatomic,copy) void (^update)(NSDictionary *,NSString *);
@property(nonatomic,readwrite) BOOL cancelled;
@property(nonatomic) BOOL started, partial;
@property(nonatomic) NSUInteger index, pages, scanned;
@end
@implementation WUStatsOverviewJob
- (void)setCandidates:(NSArray *)rows {
    NSMutableDictionary *known=[NSMutableDictionary dictionary];
    for(id row in rows) if([row isKindOfClass:NSDictionary.class] && [row[@"username"] isKindOfClass:NSString.class] && [row[@"username"] length] && [@[@"private",@"chatroom"] containsObject:row[@"kind"]]) known[row[@"username"]]=[row copy];
    NSMutableArray *sessions=[NSMutableArray array];
    for(NSString *key in [known.allKeys sortedArrayUsingSelector:@selector(compare:)]) [sessions addObject:known[key]];
    self.sessions=[sessions copy];
}
- (instancetype)initWithBinding:(WUStatsBinding *)binding {
    if((self=[super init])) {
        _binding=binding; _range=[binding.dateRange copy]; _zone=[binding.timeZone copy]; _rows=[NSMutableArray array];
        [self setCandidates:binding.sessions];
    } return self;
}
- (BOOL)current {
    @try { return !self.cancelled && self.binding.stillCurrent && self.binding.stillCurrent(); }
    @catch(__unused NSException *e) { return NO; }
}
- (void)cancel {
    NSAssert(NSThread.isMainThread,@"main thread required"); self.cancelled=YES; [self.child cancel]; self.child=nil; self.binding=nil; self.update=nil; [self.rows removeAllObjects];
}
- (void)start:(void (^)(NSDictionary *,NSString *))update {
    NSAssert(NSThread.isMainThread,@"main thread required"); if(self.started || self.cancelled) return;
    self.started=YES; self.update=[update copy];
    if(![self current]) { [self step]; return; }
    if(!self.binding.readSessions) { [self step]; return; }
    __weak typeof(self) weak=self;
    @try {
        self.binding.readSessions(^BOOL{ WUStatsOverviewJob *job=weak; return job && [job current]; },^(NSArray *rows, BOOL partial) {
            WUStatsOverviewJob *job=weak; if(!job || ![job current]) return;
            // List semantics and coverage are not proven by the public declaration.
            job.partial=YES;
            if(rows) [job setCandidates:job.binding.sessions];
            [job step];
        });
    } @catch(__unused NSException *e) { self.partial=YES; [self step]; }
}
- (void)finish {
    NSArray *rank=[self.rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){ NSComparisonResult c=[b[@"count"] compare:a[@"count"]]; return c==NSOrderedSame?[a[@"id"] compare:b[@"id"] options:NSLiteralSearch]:c; }];
    BOOL complete=!self.partial && self.index==self.sessions.count;
    NSDictionary *result=@{@"overview":@YES,@"rank":rank,@"myGroups":WUStatsMyGroupRanking(self.rows),@"complete":@(complete),@"scanned":@(self.scanned),@"pages":@(self.pages),@"sessions":@(self.sessions.count),@"processed":@(self.index),@"timezone":self.zone.name};
    void (^notify)(NSDictionary *,NSString *)=self.update; self.update=nil; self.binding=nil; self.child=nil; self.cancelled=YES;
    if(notify) notify(result,complete?@"完成：仅宿主已加载、可分类会话的本地可见范围":@"部分排行：会话列表覆盖未知、达到预算或存在未完成会话，不能代表全账号最常聊");
}
- (void)step {
    if(![self current]) { void (^notify)(NSDictionary *,NSString *)=self.update; [self cancel]; if(notify) notify(nil,@"已取消：后台、账号、会话或统计开关已变化"); return; }
    if(self.index>=self.sessions.count || self.index>=50 || self.pages>=100) { [self finish]; return; }
    NSDictionary *row=self.sessions[self.index]; WUStatsBinding *childBinding=nil;
    @try { childBinding=self.binding.bindingForSession?self.binding.bindingForSession(row[@"username"]):nil; } @catch(__unused NSException *e) {}
    if(!childBinding) { self.partial=YES; self.index++; dispatch_async(dispatch_get_main_queue(),^{ if(!self.cancelled) [self step]; }); return; }
    childBinding.dateRange=self.range; childBinding.timeZone=self.zone; childBinding.pageLimit=100-self.pages;
    self.child=[[WUStatsJob alloc] initWithBinding:childBinding]; __weak typeof(self) weak=self;
    [self.child start:^(NSDictionary *result,NSString *status){
        WUStatsOverviewJob *job=weak; if(!job || job.cancelled) return;
        if(![job current]) { void (^notify)(NSDictionary *,NSString *)=job.update; [job cancel]; if(notify) notify(nil,@"已取消，排行已清除"); return; }
        if(!result) {
            if(job.child.cancelled) { job.partial=YES; job.index++; job.child=nil; dispatch_async(dispatch_get_main_queue(),^{ if(!job.cancelled) [job step]; }); return; }
            if(job.update) job.update(nil,[NSString stringWithFormat:@"会话 %lu/%lu · %@",(unsigned long)(job.index+1),(unsigned long)MIN(job.sessions.count,50),status]); return;
        }
        job.pages+=[result[@"pages"] unsignedIntegerValue]; job.scanned+=[result[@"scanned"] unsignedIntegerValue];
        job.partial|=![result[@"complete"] boolValue];
        [job.rows addObject:@{@"id":row[@"username"],@"kind":row[@"kind"],@"count":result[@"total"],@"selfCount":result[@"details"][@"summary"][@"self"][@"authoredCount"]?:@0,@"complete":result[@"complete"]}];
        job.index++; job.child=nil;
        dispatch_async(dispatch_get_main_queue(),^{ if(!job.cancelled) [job step]; });
    }];
}
@end
