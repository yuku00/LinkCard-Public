#import "DraftMediaLogic.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
static BOOL Fail(NSError **e, NSString *s) { if(e) *e=[NSError errorWithDomain:@"WUDraftMedia" code:1 userInfo:@{NSLocalizedDescriptionKey:s}]; return NO; }
static BOOL String(id x, NSUInteger n) { return [x isKindOfClass:NSString.class] && [x length]<=n; }
static BOOL UUID(id x) { return String(x,36) && [[NSUUID alloc] initWithUUIDString:x]!=nil; }
static NSString *Hash(NSData *data) { unsigned char hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,hash); NSMutableString *s=[NSMutableString string]; for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [s appendFormat:@"%02x",hash[i]]; return s; }
static NSURL *Directory(NSURL *root, NSString *account, NSError **e) {
    if(!root.isFileURL || !String(account,256) || !account.length) { Fail(e,@"账号或目录无效"); return nil; }
    NSData *a=[account dataUsingEncoding:NSUTF8StringEncoding]; if(a.length>100) { Fail(e,@"账号过长"); return nil; }
    NSMutableString *key=[NSMutableString string]; const unsigned char *b=a.bytes; for(NSUInteger i=0;i<a.length;i++) [key appendFormat:@"%02x",b[i]];
    NSURL *base=root.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    NSURL *d=[base URLByAppendingPathComponent:key isDirectory:YES];
    if(![d.path isEqual:d.URLByResolvingSymlinksInPath.path]) { Fail(e,@"账号目录为链接，拒绝操作"); return nil; }
    return d;
}
static BOOL Regular(NSURL *url, unsigned long long *size) {
    struct stat st; if(!url.isFileURL || ![url.URLByStandardizingPath.path isEqual:url.URLByResolvingSymlinksInPath.path] || lstat(url.path.fileSystemRepresentation,&st)!=0 || !S_ISREG(st.st_mode) || st.st_size<=0 || st.st_size>64*1024*1024) return NO;
    if(size) *size=(unsigned long long)st.st_size; return YES;
}
static NSData *ReadSource(NSURL *url, NSUInteger limit) {
    if(!Regular(url,NULL)) return nil;
    int fd=open(url.path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW); if(fd<0) return nil;
    struct stat before,after; if(fstat(fd,&before)!=0 || !S_ISREG(before.st_mode) || before.st_size<=0 || before.st_size>(off_t)limit) { close(fd); return nil; }
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)before.st_size]; NSUInteger offset=0;
    while(offset<data.length) { ssize_t n=read(fd,(char *)data.mutableBytes+offset,data.length-offset); if(n<0 && errno==EINTR) continue; if(n<=0) { close(fd); return nil; } offset+=(NSUInteger)n; }
    char extra; ssize_t n; do { n=read(fd,&extra,1); } while(n<0 && errno==EINTR);
    BOOL stable=n==0 && fstat(fd,&after)==0 && before.st_size==after.st_size && before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec;
    close(fd); return stable?data:nil;
}
static BOOL Valid(id rows) {
    if(![rows isKindOfClass:NSArray.class] || [rows count]>200) return NO;
    NSMutableSet *ids=[NSMutableSet set];
    for(id row in rows) {
        if(![row isKindOfClass:NSDictionary.class] || [row count]!=5 || !UUID(row[@"id"]) || [ids containsObject:row[@"id"]] || !String(row[@"text"],10000) || !String(row[@"name"],80) || ![row[@"resources"] isKindOfClass:NSArray.class]) return NO;
        [ids addObject:row[@"id"]]; BOOL image=[row[@"kind"] isEqual:@"images"], video=[row[@"kind"] isEqual:@"video-backup"];
        NSArray *resources=row[@"resources"]; if((!image&&!video) || !resources.count || resources.count>(image?9:1)) return NO;
        for(id r in resources) {
            if(![r isKindOfClass:NSDictionary.class] || [r count]!=3 || !UUID(r[@"file"]) || !String(r[@"sha256"],64) || [r[@"sha256"] length]!=64 || ![r[@"bytes"] isKindOfClass:NSNumber.class] || [r[@"bytes"] unsignedLongLongValue]==0 || [r[@"bytes"] unsignedLongLongValue]>64*1024*1024) return NO;
        }
    } return YES;
}
static NSArray *Load(NSURL *d, NSString *a, NSError **e) {
    NSURL *p=[d URLByAppendingPathComponent:@"index.plist"]; struct stat st;
    if(lstat(p.path.fileSystemRepresentation,&st)!=0) { if(errno==ENOENT) return @[]; Fail(e,@"索引不可读，禁止覆盖"); return nil; }
    if(!S_ISREG(st.st_mode) || st.st_size>1024*1024 || st.st_size<=0) { Fail(e,@"坏索引，保留全部资源"); return nil; }
    NSData *data=ReadSource(p,1024*1024); if(!data) { Fail(e,@"索引读取失败或变化，禁止覆盖"); return nil; }
    id v=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:e];
    if(![v isKindOfClass:NSDictionary.class] || [v count]!=3 || ![v[@"version"] isEqual:@1] || ![v[@"account"] isEqual:a] || !Valid(v[@"rows"])) { Fail(e,@"索引损坏或账号不符，禁止覆盖/清理"); return nil; } return v[@"rows"];
}
static BOOL Save(NSURL *d, NSString *a, NSArray *rows, NSError **e) {
    if(!Valid(rows)) return Fail(e,@"媒体索引无效或超过200条");
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:@{@"version":@1,@"account":a,@"rows":rows} format:NSPropertyListBinaryFormat_v1_0 options:0 error:e];
    if(!data || data.length>1024*1024) return Fail(e,@"媒体索引超过1MiB");
    return [data writeToURL:[d URLByAppendingPathComponent:@"index.plist"] options:NSDataWritingAtomic error:e];
}
NSArray *WUDraftMediaLoad(NSURL *root, NSString *a, NSError **e) { @synchronized(NSFileManager.defaultManager) { NSURL *d=Directory(root,a,e); return d?Load(d,a,e):nil; } }
NSArray<NSURL *> *WUDraftMediaURLs(NSURL *root, NSString *a, NSDictionary *row, NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        NSURL *d=Directory(root,a,e); if(!d || !row || !Valid(@[row])) { Fail(e,@"资源描述无效"); return nil; }
        NSMutableArray *urls=[NSMutableArray array];
        for(NSDictionary *r in row[@"resources"]) {
            NSURL *u=[d URLByAppendingPathComponent:r[@"file"]]; unsigned long long size=0;
            if(!Regular(u,&size) || size!=[r[@"bytes"] unsignedLongLongValue]) { Fail(e,@"资源缺失或越界，原索引保留"); return nil; }
            NSData *data=ReadSource(u,64*1024*1024); if(!data || data.length!=[r[@"bytes"] unsignedLongLongValue]) { Fail(e,@"资源读取失败或变化"); return nil; }
            if(![Hash(data) isEqual:r[@"sha256"]]) { Fail(e,@"资源校验失败，禁止假恢复"); return nil; } [urls addObject:u];
        } return urls;
    }
}
NSData *WUDraftMediaReadSource(NSURL *url, NSUInteger limit) { return ReadSource(url,MIN(limit,(NSUInteger)64*1024*1024)); }
BOOL WUDraftMediaPut(NSURL *root, NSString *a, NSString *uuid, NSString *text, NSString *kind, NSArray *sources, NSError **e) {
    return WUDraftMediaPutChecked(root,a,uuid,text,kind,sources,nil,e);
}
BOOL WUDraftMediaPutChecked(NSURL *root, NSString *a, NSString *uuid, NSString *text, NSString *kind, NSArray *sources, BOOL (^valid)(void), NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        BOOL images=[kind isEqual:@"images"], video=[kind isEqual:@"video-backup"];
        if(!UUID(uuid) || !String(text,10000) || (!images&&!video) || ![sources isKindOfClass:NSArray.class] || !sources.count || sources.count>(images?9:1)) return Fail(e,@"媒体参数无效");
        NSURL *d=Directory(root,a,e); if(!d) return NO; NSArray *old=Load(d,a,e); if(!old) return NO;
        NSMutableArray *rows=[old mutableCopy]; NSUInteger index=[rows indexOfObjectPassingTest:^BOOL(NSDictionary *r, NSUInteger i, BOOL *stop){ return [r[@"id"] isEqual:uuid]; }];
        if(index==NSNotFound && rows.count>=200) return Fail(e,@"媒体草稿已达200条");
        if(![NSFileManager.defaultManager createDirectoryAtURL:d withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:e]) return NO;
        NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:d includingPropertiesForKeys:nil options:0 error:e]; if(!files) return NO;
        unsigned long long used=0; if(files.count+sources.count+1>4096) return Fail(e,@"保留资源数量已满，未自动删除");
        for(NSURL *u in files) { struct stat st; if(lstat(u.path.fileSystemRepresentation,&st)!=0 || !S_ISREG(st.st_mode)) return Fail(e,@"自有目录存在非普通文件，拒绝写入"); used+=(unsigned long long)st.st_size; if(used>512ULL*1024*1024) return Fail(e,@"账号保留资源已满，未自动删除"); }
        // Checked callers need a durable empty index before copying, so interrupted first writes remain reclaimable.
        if(valid && (!valid() || !Save(d,a,old,e))) return Fail(e,@"提交已失效或初始媒体索引无法保存");
        NSMutableArray *resources=[NSMutableArray array];
        for(id source in sources) {
            { // NSError ** writeback must outlive this iteration; no nested autorelease pool.
                NSData *data=nil;
                if(images && [source isKindOfClass:NSData.class]) data=source;
                else if([source isKindOfClass:NSURL.class]) data=ReadSource(source,64*1024*1024);
                if(!data.length || data.length>64*1024*1024) return Fail(e,@"源媒体不可读、为空或超过64MiB；未提交索引");
                used+=data.length; if(used>512ULL*1024*1024) return Fail(e,@"本账号保留资源达512MiB；未自动删除，未提交索引");
                NSString *file=NSUUID.UUID.UUIDString; NSURL *dst=[d URLByAppendingPathComponent:file];
                // A fresh immutable UUID is never a host path, shared path or old editing path.
                if(![data writeToURL:dst options:NSDataWritingWithoutOverwriting error:e]) return NO;
                NSData *check=ReadSource(dst,64*1024*1024); NSString *hash=Hash(data);
                if(!check || check.length!=data.length || ![Hash(check) isEqual:hash]) return Fail(e,@"复制校验失败，未提交索引");
                [resources addObject:@{@"file":file,@"bytes":@(data.length),@"sha256":hash}];
            }
        }
        NSString *name=text.length?[text substringToIndex:MIN(text.length,80)]:(images?@"图片草稿":@"视频备份（不可恢复）");
        NSDictionary *row=@{@"id":uuid,@"name":name,@"text":text,@"kind":kind,@"resources":resources};
        if(index==NSNotFound) [rows insertObject:row atIndex:0]; else rows[index]=row;
        // Index is the commit point. Failed/new/old resources are retained under a hard quota.
        // No unlink/sweep means shared references and active host editors remain protected.
        if(valid && !valid()) return Fail(e,@"账号或代次已失效；复制资源未提交，等待安全回收");
        return Save(d,a,rows,e);
    }
}
BOOL WUDraftMediaDelete(NSURL *root, NSString *a, NSString *uuid, NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        NSURL *d=Directory(root,a,e); if(!d) return NO; NSArray *old=Load(d,a,e); if(!old) return NO;
        NSMutableArray *rows=[old mutableCopy]; NSIndexSet *matches=[rows indexesOfObjectsPassingTest:^BOOL(NSDictionary *r, NSUInteger i, BOOL *stop){return [r[@"id"] isEqual:uuid];}];
        if(!matches.count) return Fail(e,@"媒体草稿不存在"); [rows removeObjectsAtIndexes:matches]; return Save(d,a,rows,e);
    }
}
