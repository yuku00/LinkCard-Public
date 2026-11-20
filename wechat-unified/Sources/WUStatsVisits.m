#import "WUStats.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <math.h>
#import <errno.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdio.h>

NSArray<NSDictionary *> *WUStatsVisitRanking(NSArray<NSDictionary *> *events, NSDictionary *range) {
    NSMutableDictionary *counts=[NSMutableDictionary dictionary], *kinds=[NSMutableDictionary dictionary];
    for(NSDictionary *event in events) if(WUStatsTimeInRange(event[@"time"],range)) {
        NSString *key=event[@"session"]; if(!key.length) continue;
        counts[key]=@([counts[key] unsignedIntegerValue]+1);
        NSString *kind=event[@"kind"]?:@"unknown";
        if(!kinds[key]) kinds[key]=kind;
        else if(![kinds[key] isEqual:kind]) kinds[key]=@"unknown";
    }
    NSArray *keys=[counts.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){ NSComparisonResult result=[counts[b] compare:counts[a]]; return result==NSOrderedSame?[a compare:b options:NSLiteralSearch]:result; }];
    NSMutableArray *rows=[NSMutableArray array]; for(NSString *key in keys) [rows addObject:@{@"id":key,@"count":counts[key],@"kind":kinds[key]}]; return [rows copy];
}

NSString *WUStatsVisitID(NSString *account, NSString *session) {
    if(!account.length) return @"";
    NSString *input=[NSString stringWithFormat:@"WUVisit1:%lu:%@:%@",(unsigned long)account.length,account,session?:@""];
    NSData *data=[input dataUsingEncoding:NSUTF8StringEncoding]; unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest); NSMutableString *s=[NSMutableString string];
    for(NSUInteger i=0;i<sizeof(digest);i++) [s appendFormat:@"%02x",digest[i]]; return s;
}
static BOOL Hash(id s) { return [s isKindOfClass:NSString.class] && [s length]==64 && [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet].location==NSNotFound; }
static BOOL Kind(id s) { return [@[@"private",@"chatroom",@"other",@"unknown"] containsObject:s]; }
@interface WUStatsVisitStore ()
@property(nonatomic,copy) NSString *accountHash;
@property(nonatomic,strong) NSURL *directory;
@property(nonatomic,strong) NSURL *file;
@property(nonatomic,copy) NSString *error;
@end
@implementation WUStatsVisitStore
- (instancetype)initWithDirectory:(NSURL *)directory account:(NSString *)account {
    if((self=[super init])) { _directory=directory; _accountHash=WUStatsVisitID(account,@""); _file=[directory URLByAppendingPathComponent:[_accountHash stringByAppendingString:@".plist"]]; }
    return self;
}
- (BOOL)safeDirectory {
    if(!self.accountHash.length || !self.directory.isFileURL) return NO;
    struct stat st; if(lstat(self.directory.fileSystemRepresentation,&st)!=0) {
        if(![NSFileManager.defaultManager createDirectoryAtURL:self.directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return NO;
        if(lstat(self.directory.fileSystemRepresentation,&st)!=0) return NO;
    }
    return S_ISDIR(st.st_mode) && !S_ISLNK(st.st_mode);
}
- (NSArray *)load {
    if(![self safeDirectory]) { self.error=@"日志目录不可用"; return nil; }
    struct stat st; if(lstat(self.file.fileSystemRepresentation,&st)!=0) {
        if(errno==ENOENT) return @[]; self.error=@"日志读取失败"; return nil;
    }
    if(!S_ISREG(st.st_mode) || st.st_nlink!=1 || st.st_size>1048576 || st.st_size<1) { self.error=@"日志损坏或非安全文件，拒绝覆盖"; return nil; }
    int fd=open(self.file.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
    struct stat opened;
    if(fd<0 || fstat(fd,&opened)!=0 || !S_ISREG(opened.st_mode) || opened.st_nlink!=1 || opened.st_size<1 || opened.st_size>1048576) { if(fd>=0) close(fd); self.error=@"日志安全读取失败"; return nil; }
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)opened.st_size]; NSUInteger offset=0;
    while(offset<data.length) { ssize_t n=read(fd,(char *)data.mutableBytes+offset,data.length-offset); if(n<=0) break; offset+=(NSUInteger)n; }
    char extra; ssize_t trailing=read(fd,&extra,1); close(fd);
    if(offset!=data.length || trailing!=0) { self.error=@"日志长度变化，拒绝读取"; return nil; }
    id root=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil]:nil;
    if(![root isKindOfClass:NSDictionary.class] || ![root[@"version"] isEqual:@1] || ![root[@"account"] isEqual:self.accountHash] || ![root[@"events"] isKindOfClass:NSArray.class] || [root[@"events"] count]>4096) { self.error=@"日志校验失败，保留原文件"; return nil; }
    NSTimeInterval previous=0;
    for(id event in root[@"events"]) {
        if(![event isKindOfClass:NSDictionary.class] || [event count]!=3 || !Hash(event[@"session"]) || !Kind(event[@"kind"]) || ![event[@"time"] isKindOfClass:NSNumber.class]) { self.error=@"日志条目无效"; return nil; }
        double t=[event[@"time"] doubleValue]; if(!isfinite(t) || t<=0 || t<previous) { self.error=@"日志时间无效"; return nil; } previous=t;
    }
    return root[@"events"];
}
- (BOOL)save:(NSArray *)events current:(BOOL (^)(void))current {
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:@{@"version":@1,@"account":self.accountHash,@"events":events} format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if(!data || data.length>1048576 || !current || !current()) { self.error=@"已取消或日志超限"; return NO; }
    NSURL *temporary=[self.directory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.tmp",NSUUID.UUID.UUIDString]];
    BOOL ok=self.writeData?self.writeData(data,temporary):[data writeToURL:temporary options:NSDataWritingWithoutOverwriting error:nil];
    // Account/background cancellation is checked after IO and immediately before commit.
    if(ok) ok=current() && rename(temporary.fileSystemRepresentation,self.file.fileSystemRepresentation)==0;
    if(!ok) { unlink(temporary.fileSystemRepresentation); self.error=@"日志原子写入失败或已取消，保留旧记录"; }
    else self.error=nil;
    return ok;
}
- (BOOL)recordSession:(NSString *)session kind:(NSString *)kind time:(NSTimeInterval)time active:(BOOL)active enabled:(BOOL)enabled current:(BOOL (^)(void))current {
    if(!active || !enabled || !current || !current() || !session.length || session.length>256 || !Kind(kind) || !isfinite(time) || time<=0) return NO;
    NSArray *events=[self load]; if(!events) return NO;
    if(events.count>=4096) { self.error=@"达到4096条上限，停止记录；可手动清空"; return NO; }
    NSString *key=WUStatsVisitID(self.accountHash,session);
    NSDictionary *last=events.lastObject; double elapsed=time-[last[@"time"] doubleValue];
    if(last && (elapsed<0 || ([last[@"session"] isEqual:key] && elapsed<12))) return NO;
    NSMutableArray *next=[events mutableCopy]; [next addObject:@{@"session":key,@"kind":kind,@"time":@(time)}];
    return [self save:next current:current];
}
- (NSDictionary *)snapshot {
    NSArray *events=[self load];
    return @{@"events":events?:@[],@"error":self.error?:@"",@"valid":@(events!=nil),@"limit":@4096,@"full":@(events.count>=4096)};
}
- (BOOL)clearIfCurrent:(BOOL (^)(void))current {
    if(!current || !current() || ![self load]) return NO;
    return [self save:@[] current:current];
}
@end
