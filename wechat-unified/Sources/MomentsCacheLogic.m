#import "MomentsCacheLogic.h"
#import "RepositoryLogic.h"
#import "DraftMediaLogic.h"
#import "LocalVideoContainer.h"
#include <unistd.h>
#include <math.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>
static BOOL Fail(NSError **e) { if(e) *e=[NSError errorWithDomain:@"WUMomentsCache" code:1 userInfo:@{NSLocalizedDescriptionKey:@"缓存无效、超限或索引损坏；原数据保留，禁止清理"}]; return NO; }
static BOOL Text(id v, NSUInteger max) { return [v isKindOfClass:NSString.class] && [v length]<=max; }
NSDictionary *WUMCacheNormalize(id tid, id username, id text) {
    // Preserve the full decimal identifier: never round a server ID through double.
    if([tid isKindOfClass:NSNumber.class]) {
        const char *t=[tid objCType]; if(!strchr("qQiIlLsScC",t[0]) || [tid compare:@0]!=NSOrderedDescending) return nil;
        tid=[tid stringValue];
    }
    if(!Text(tid,64) || ![tid length] || !Text(username,256) || ![username length] || !Text(text,10000)) return nil;
    if([tid rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location!=NSNotFound || [[tid stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0"]] length]==0) return nil;
    while([tid length]>1 && [tid hasPrefix:@"0"]) tid=[tid substringFromIndex:1];
    return @{@"tid":[tid copy],@"username":[username copy],@"text":[text copy]};
}
static BOOL WUCommentRecordValid(id r) {
    if(![r isKindOfClass:NSDictionary.class] || [r count]!=(r[@"visibility"]?6:5) || (r[@"visibility"] && ![@[@"visibleSnapshot",@"historical"] containsObject:r[@"visibility"]]) || !Text(r[@"id"],80) || ![r[@"id"] length] || !Text(r[@"author"],256) || ![r[@"author"] length] || !Text(r[@"text"],1000) || !Text(r[@"replyTo"],256)) return NO;
    id t=r[@"time"]; return [t isKindOfClass:NSNumber.class] && isfinite([t doubleValue]) && [t doubleValue]>=0 && [t doubleValue]<=253402300799.0 && floor([t doubleValue])==[t doubleValue];
}
NSArray *WUMCacheMergeComments(NSArray *old, NSArray *observed, NSError **e) {
    if(![old isKindOfClass:NSArray.class] || ![observed isKindOfClass:NSArray.class] || old.count>50 || observed.count>50) { Fail(e); return nil; }
    NSMutableDictionary *rows=[NSMutableDictionary dictionary];
    for(NSArray *page in @[old,observed]) {
        NSMutableDictionary *seen=[NSMutableDictionary dictionary];
        for(id r in page) {
            if(!WUCommentRecordValid(r)) { Fail(e); return nil; }
            NSArray *key=@[r[@"author"],r[@"id"]];
            if(seen[key] && ![seen[key] isEqual:r]) { Fail(e); return nil; }
            NSDictionary *copy=[[NSDictionary alloc] initWithDictionary:r copyItems:YES]; seen[key]=copy; rows[key]=copy;
        }
    }
    if(rows.count>50) { Fail(e); return nil; }
    NSArray *result=[rows.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
        double at=[a[@"time"] doubleValue],bt=[b[@"time"] doubleValue];
        if(at!=bt) { if(at==0) return NSOrderedDescending; if(bt==0) return NSOrderedAscending; return at<bt?NSOrderedAscending:NSOrderedDescending; }
        NSComparisonResult c=[a[@"author"] compare:b[@"author"] options:NSLiteralSearch]; return c==NSOrderedSame?[a[@"id"] compare:b[@"id"] options:NSLiteralSearch]:c;
    }];
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:0 error:e];
    if(!json || json.length>6000) { Fail(e); return nil; }
    return result; // Missing observations never delete old comments or claim server deletion.
}
static BOOL WUCommentStableID(NSString *s) {
    NSString *max=nil;
    if([s hasPrefix:@"c32:"]) max=@"2147483647";
    else if([s hasPrefix:@"c64:"]) max=@"18446744073709551615";
    if(!max) return NO; s=[s substringFromIndex:4];
    if(!s.length || [s hasPrefix:@"0"] || s.length>max.length) return NO;
    for(NSUInteger i=0;i<s.length;i++) if([s characterAtIndex:i]<'0' || [s characterAtIndex:i]>'9') return NO;
    return s.length<max.length || [s compare:max options:NSLiteralSearch]!=NSOrderedDescending;
}
NSString *WUMCacheCommentStateText(NSDictionary *comment) {
    NSString *state=[comment[@"visibility"] isEqual:@"visibleSnapshot"]?@"最近一次详情快照可见（非实时）":@"历史快照（本次未确认可见）";
    return [state stringByAppendingString:@"；真实删除未确认；创建/删除时间未知"];
}
static BOOL Row(id r) {
    if(![r isKindOfClass:NSDictionary.class] || [r count]!=(r[@"comments"]?9:8) || (r[@"comments"] && !WUMCacheMergeComments(@[],r[@"comments"],NULL)) || !Text(r[@"id"],36) || ![[NSUUID alloc] initWithUUIDString:r[@"id"]] || ![r[@"favorite"] isKindOfClass:NSNumber.class] || ![r[@"status"] isEqual:@"seen"]) return NO;
    NSDictionary *n=WUMCacheNormalize(r[@"tid"],r[@"username"],r[@"text"]);
    if(!n || ![n[@"tid"] isEqual:r[@"tid"]]) return NO;
    for(NSString *k in @[@"first",@"last"]) if(![r[k] isKindOfClass:NSNumber.class] || !isfinite([r[k] doubleValue]) || [r[k] doubleValue]<=0) return NO;
    return [r[@"last"] doubleValue]>=[r[@"first"] doubleValue];
}
static BOOL Safe(NSURL *d, NSString *a, NSError **e) {
    if(!d.isFileURL || !Text(a,256) || !a.length || ![d.URLByStandardizingPath.path isEqual:d.URLByResolvingSymlinksInPath.path]) return Fail(e);
    NSData *data=[a dataUsingEncoding:NSUTF8StringEncoding]; if(data.length>100) return Fail(e);
    NSMutableString *key=[NSMutableString string]; const unsigned char *b=data.bytes; for(NSUInteger i=0;i<data.length;i++) [key appendFormat:@"%02x",b[i]];
    NSURL *p=[d URLByAppendingPathComponent:[key stringByAppendingString:@".plist"]]; struct stat st;
    if(lstat(p.path.fileSystemRepresentation,&st)!=0) return errno==ENOENT?YES:Fail(e);
    return S_ISREG(st.st_mode)?YES:Fail(e);
}
static NSArray *Load(NSURL *d, NSString *a, NSError **e) {
    if(!Safe(d,a,e)) return nil;
    NSArray *items=WURepositoryLoad(d,a,e); if(!items) return nil;
    NSMutableArray *out=[NSMutableArray array]; NSMutableSet *keys=[NSMutableSet set];
    for(NSDictionary *item in items) {
        NSArray *parts=item[@"parts"]; if(parts.count!=1 || ![parts[0][@"kind"] isEqual:@"text"]) { Fail(e); return nil; }
        NSData *data=[parts[0][@"text"] dataUsingEncoding:NSUTF8StringEncoding]; id r=[NSJSONSerialization JSONObjectWithData:data options:0 error:e];
        if(!Row(r) || ![r[@"id"] isEqual:item[@"id"]]) { Fail(e); return nil; }
        NSArray *key=@[r[@"username"],r[@"tid"]]; if([keys containsObject:key]) { Fail(e); return nil; } [keys addObject:key]; [out addObject:r];
    } return out;
}
static BOOL Save(NSURL *d, NSString *a, NSArray *rows, NSError **e) {
    if(!Safe(d,a,e)) return NO;
    NSMutableArray *items=[NSMutableArray array];
    for(NSDictionary *r in rows) {
        if(!Row(r)) return Fail(e);
        NSData *json=[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingSortedKeys error:e]; if(!json) return NO;
        NSString *s=[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        [items addObject:@{@"id":r[@"id"],@"name":@"曾见朋友圈",@"parts":@[@{@"kind":@"text",@"text":s}]}];
    } return WURepositorySave(d,a,items,e);
}
BOOL WUMCacheSaveComments(NSURL *d, NSString *a, NSString *user, NSString *tid, NSArray *observed, NSTimeInterval now, BOOL (^valid)(void), NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        if(!valid || !valid() || !isfinite(now) || now<=0) return Fail(e);
        NSArray *old=Load(d,a,e); if(!old) return NO;
        NSMutableArray *rows=[old mutableCopy];
        NSUInteger i=[rows indexOfObjectPassingTest:^BOOL(NSDictionary *r, NSUInteger idx, BOOL *stop){ return [r[@"username"] isEqual:user] && [r[@"tid"] isEqual:tid]; }];
        if(i==NSNotFound) return Fail(e); // Comments cannot create an unseen parent moment.
        NSDictionary *r=rows[i];
        // Validate first; unknown/absent rows become historical, never deleted.
        if(!WUMCacheMergeComments(@[],observed,e)) return NO;
        NSMutableArray *history=[NSMutableArray array], *visible=[NSMutableArray array];
        for(NSDictionary *c in r[@"comments"]?:@[]) { NSMutableDictionary *n=[c mutableCopy]; n[@"visibility"]=@"historical"; [history addObject:n]; }
        for(NSDictionary *c in observed) {
            NSMutableDictionary *n=[c mutableCopy]; n[@"visibility"]=WUCommentStableID(c[@"id"])?@"visibleSnapshot":@"historical";
            [visible addObject:n];
        }
        NSArray *merged=WUMCacheMergeComments(history,visible,e); if(!merged) return NO;
        if([merged isEqual:r[@"comments"]]) return valid();
        NSMutableDictionary *next=[r mutableCopy]; next[@"comments"]=merged; next[@"last"]=@(MAX(now,[r[@"last"] doubleValue])); rows[i]=next;
        if(!valid()) return Fail(e); return Save(d,a,rows,e);
    }
}
// Success refreshes only a verified displayed snapshot. Callback ID namespaces
// are not proved by the sample, so no deleted/tombstone state is manufactured.
BOOL WUMCacheSaveCommentCompletion(NSURL *d, NSString *a, NSString *user, NSString *tid, int64_t ret, NSArray *observed, NSTimeInterval now, BOOL (^valid)(void), NSError **e) {
    if(ret!=0) return NO; // No load, write, timestamp update, or parent creation on failure.
    return WUMCacheSaveComments(d,a,user,tid,observed,now,valid,e);
}
NSArray *WUMCacheLoad(NSURL *d, NSString *a, NSError **e) { @synchronized(NSFileManager.defaultManager) { return Load(d,a,e); } }
static NSDictionary *Observe(NSURL *d, NSString *a, NSDictionary *item, NSString *uuid, NSTimeInterval now, BOOL (^valid)(void), NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        if(![item isKindOfClass:NSDictionary.class] || !isfinite(now) || now<=0) { Fail(e); return nil; }
        NSDictionary *n=WUMCacheNormalize(item[@"tid"],item[@"username"],item[@"text"]); if(!n) { Fail(e); return nil; }
        NSArray *old=Load(d,a,e); if(!old) return nil; NSMutableArray *rows=[old mutableCopy];
        NSUInteger i=[rows indexOfObjectPassingTest:^BOOL(NSDictionary *r, NSUInteger idx, BOOL *stop){return [r[@"tid"] isEqual:n[@"tid"]] && [r[@"username"] isEqual:n[@"username"]];}];
        if(i==NSNotFound && rows.count>=200) { Fail(e); return nil; }
        NSMutableDictionary *r=i==NSNotFound?[n mutableCopy]:[rows[i] mutableCopy];
        if(i==NSNotFound) { r[@"id"]=uuid?:NSUUID.UUID.UUIDString; r[@"favorite"]=@NO; r[@"first"]=@(now); r[@"status"]=@"seen"; }
        else if([r[@"text"] isEqual:n[@"text"]] && now-[r[@"last"] doubleValue]<3600) return r;
        r[@"text"]=n[@"text"]; r[@"last"]=@(MAX(now,[r[@"last"] doubleValue]));
        if(i==NSNotFound) [rows insertObject:r atIndex:0]; else rows[i]=r;
        if(valid && !valid()) { Fail(e); return nil; }
        return Save(d,a,rows,e)?r:nil;
    }
}
BOOL WUMCacheFavorite(NSURL *d, NSString *a, NSString *uuid, NSError **e) { return WUMCacheFavoriteChecked(d,a,uuid,nil,e); }
BOOL WUMCacheFavoriteChecked(NSURL *d, NSString *a, NSString *uuid, BOOL (^valid)(void), NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        NSArray *old=Load(d,a,e); if(!old) return NO; NSMutableArray *rows=[old mutableCopy];
        for(NSUInteger i=0;i<rows.count;i++) if([rows[i][@"id"] isEqual:uuid]) { NSMutableDictionary *r=[rows[i] mutableCopy]; r[@"favorite"]=@(![r[@"favorite"] boolValue]); rows[i]=r; if(valid && !valid()) return Fail(e); return Save(d,a,rows,e); } return Fail(e);
    }
}
BOOL WUMCacheClean(NSURL *d, NSString *a, NSUInteger days, NSTimeInterval now, NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        if(days<1 || days>3650 || !isfinite(now) || now<=0) return Fail(e);
        NSArray *old=Load(d,a,e); if(!old) return NO; NSMutableArray *rows=[NSMutableArray array];
        // Missing pages/privacy changes are not deletion evidence. Only explicit local age cleanup.
        for(NSDictionary *r in old) if([r[@"favorite"] boolValue] || now-[r[@"last"] doubleValue]<=days*86400.0) [rows addObject:r];
        return rows.count==old.count || Save(d,a,rows,e);
    }
}

NSDictionary *WUMCacheObserve(NSURL *d, NSString *a, NSDictionary *item, NSTimeInterval now, NSError **e) { return Observe(d,a,item,nil,now,nil,e); }
BOOL WUMCacheStore(NSURL *text, NSURL *media, NSString *a, NSDictionary *item, NSArray *images, NSTimeInterval now, BOOL (^valid)(void), NSError **e) {
    return WUMCacheStoreMedia(text,media,a,item,@"images",images,now,[NSSet set],valid,e);
}
BOOL WUMCacheStoreMedia(NSURL *text, NSURL *media, NSString *a, NSDictionary *item, NSString *kind, NSArray *images, NSTimeInterval now, NSSet *leasedIDs, BOOL (^valid)(void), NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        BOOL video=[kind isEqual:@"video-backup"];
        if(![leasedIDs isKindOfClass:NSSet.class] || ![images isKindOfClass:NSArray.class] || (!video && ![kind isEqual:@"images"]) || (video && images.count!=1)) return Fail(e);
        if(!valid || !valid() || !Safe(media,a,e) || images.count>9) return Fail(e);
        NSArray *rows=Load(text,a,e), *resources=WUDraftMediaLoad(media,a,e); if(!rows || !resources) return NO;
        NSString *uuid=nil; for(NSDictionary *r in rows) if([r[@"tid"] isEqual:item[@"tid"]] && [r[@"username"] isEqual:item[@"username"]]) uuid=r[@"id"];
        if(!uuid && rows.count>=200) return Fail(e);
        uuid=uuid?:NSUUID.UUID.UUIDString;
        BOOL exists=NO, upgrade=NO;
        for(NSDictionary *r in resources) if([r[@"id"] isEqual:uuid]) { exists=YES; upgrade=video && [r[@"kind"] isEqual:@"images"]; }
        if(upgrade && [leasedIDs containsObject:uuid]) {
            if(e) *e=[NSError errorWithDomain:@"WUMomentsCache" code:4 userInfo:@{NSLocalizedDescriptionKey:@"旧媒体正在浏览，保留原缓存；关闭后再次访问可补入本地视频"}]; return NO;
        }
        for(id image in images) {
            if(![image isKindOfClass:NSData.class] || ![image length] || [image length]>(video?64u:8u)*1024u*1024u) return Fail(e);
            if(video && !WULocalVideoContainer([image bytes],[image length])) return Fail(e);
        }
        if(!valid() || !Save(text,a,rows,e)) return Fail(e);
        if(images.count && (!exists || upgrade) && !WUDraftMediaPutChecked(media,a,uuid,video?@"曾见朋友圈视频":@"曾见朋友圈图片",kind,images,valid,e)) return NO;
        // Media first: a failed source/copy never overwrites the old text record.
        // A text commit failure leaves indexed owned media for an explicit later cleanup.
        return Observe(text,a,item,uuid,now,valid,e)!=nil;
    }
}
static NSURL *OwnedDirectory(NSURL *root, NSString *a, NSError **e) {
    // The draft repository deliberately has no reclamation API. This namespace alone owns these UUIDs.
    if(![root.lastPathComponent isEqual:@"Media"] || ![root.URLByDeletingLastPathComponent.lastPathComponent isEqual:@"MomentsCache"] || !Safe(root,a,e)) { Fail(e); return nil; }
    NSData *data=[a dataUsingEncoding:NSUTF8StringEncoding]; NSMutableString *key=[NSMutableString string]; const unsigned char *b=data.bytes;
    for(NSUInteger i=0;i<data.length;i++) [key appendFormat:@"%02x",b[i]];
    NSURL *d=[root URLByAppendingPathComponent:key isDirectory:YES];
    if(![d.URLByStandardizingPath.path isEqual:d.URLByResolvingSymlinksInPath.path]) { Fail(e); return nil; } return d;
}
NSDictionary *WUMCacheReclaim(NSURL *text, NSURL *media, NSString *a, NSUInteger days, NSTimeInterval now, NSSet *leasedIDs, BOOL (^valid)(void), NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        if(!valid || !valid() || days<1 || days>3650 || !isfinite(now) || now<=0) { Fail(e); return nil; }
        NSURL *d=OwnedDirectory(media,a,e); if(!d) return nil;
        NSArray *rows=Load(text,a,e), *resources=WUDraftMediaLoad(media,a,e); if(!rows || !resources) return nil;
        struct stat st; BOOL exists=lstat(d.path.fileSystemRepresentation,&st)==0;
        if(exists && !S_ISDIR(st.st_mode)) { Fail(e); return nil; }
        NSArray *files=exists?[NSFileManager.defaultManager contentsOfDirectoryAtURL:d includingPropertiesForKeys:nil options:0 error:e]:@[];
        if(!files || files.count>4096) { Fail(e); return nil; }
        NSURL *index=[d URLByAppendingPathComponent:@"index.plist"];
        // Missing media index with retained files is not an empty trustworthy index.
        NSURL *textIndex=[text URLByAppendingPathComponent:[d.lastPathComponent stringByAppendingString:@".plist"]];
        if(files.count && (lstat(index.path.fileSystemRepresentation,&st)!=0 || lstat(textIndex.path.fileSystemRepresentation,&st)!=0)) { Fail(e); return nil; }
        NSURL *journal=[d URLByAppendingPathComponent:@"reclaim.plist"];
        for(NSURL *u in files) {
            if(lstat(u.path.fileSystemRepresentation,&st)!=0 || !S_ISREG(st.st_mode) || st.st_nlink!=1) { Fail(e); return nil; }
            if(![u.lastPathComponent isEqual:@"index.plist"] && ![u.lastPathComponent isEqual:@"reclaim.plist"] && ![[NSUUID alloc] initWithUUIDString:u.lastPathComponent]) { Fail(e); return nil; }
        }
        if(lstat(journal.path.fileSystemRepresentation,&st)==0) {
            NSData *data=WUDraftMediaReadSource(journal,1024*1024);
            id j=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:e]:nil;
            if(![j isKindOfClass:NSDictionary.class] || ![j[@"account"] isEqual:a] || ![j[@"files"] isKindOfClass:NSArray.class] || [j[@"files"] count]>4096) { Fail(e); return nil; }
            for(id f in j[@"files"]) if(![f isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:f]) { Fail(e); return nil; }
        } else if(errno!=ENOENT) { Fail(e); return nil; }
        NSMutableArray *kept=[NSMutableArray array];
        for(NSDictionary *r in rows) if([r[@"favorite"] boolValue] || now-[r[@"last"] doubleValue]<=days*86400.0) [kept addObject:r];
        if(!valid() || (kept.count!=rows.count && !Save(text,a,kept,e))) { Fail(e); return nil; }
        NSMutableSet *keepIDs=[NSMutableSet setWithArray:[kept valueForKey:@"id"]]; [keepIDs unionSet:leasedIDs?:[NSSet set]];
        // Commit recoverable indexes before any unlink. Partial index failure keeps every file.
        for(NSDictionary *r in resources) if(![keepIDs containsObject:r[@"id"]]) {
            if(!valid() || !WUDraftMediaDelete(media,a,r[@"id"],e)) { Fail(e); return nil; }
        }
        resources=WUDraftMediaLoad(media,a,e); if(!resources) return nil;
        NSMutableSet *referenced=[NSMutableSet set]; for(NSDictionary *r in resources) for(NSDictionary *f in r[@"resources"]) [referenced addObject:f[@"file"]];
        NSMutableArray *candidates=[NSMutableArray array];
        for(NSURL *u in files) if([[NSUUID alloc] initWithUUIDString:u.lastPathComponent] && ![referenced containsObject:u.lastPathComponent]) [candidates addObject:u.lastPathComponent];
        if(!candidates.count) return @{@"files":@0,@"bytes":@0};
        NSData *plan=[NSPropertyListSerialization dataWithPropertyList:@{@"account":a,@"files":candidates} format:NSPropertyListBinaryFormat_v1_0 options:0 error:e];
        if(!valid() || !plan || ![plan writeToURL:journal options:NSDataWritingAtomic error:e]) return nil;
        unsigned long long bytes=0; NSUInteger count=0;
        for(NSString *file in candidates) {
            if(!valid()) { Fail(e); break; }
            NSURL *u=[d URLByAppendingPathComponent:file];
            if(![u.URLByStandardizingPath.path isEqual:u.URLByResolvingSymlinksInPath.path] || lstat(u.path.fileSystemRepresentation,&st)!=0 || !S_ISREG(st.st_mode) || st.st_nlink!=1) { Fail(e); break; }
            // Count only successful unlinks, using allocated blocks, not the requested/index size.
            if(unlink(u.path.fileSystemRepresentation)!=0) { Fail(e); break; }
            bytes+=(unsigned long long)st.st_blocks*512; count++;
        }
        // The journal is retained for retry; indexes and live leases are revalidated on every attempt.
        return @{@"files":@(count),@"bytes":@(bytes)};
    }
}
