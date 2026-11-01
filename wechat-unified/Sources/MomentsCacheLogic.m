#import "MomentsCacheLogic.h"
#import "RepositoryLogic.h"
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
    return @{@"tid":tid,@"username":[username copy],@"text":[text copy]};
}
static BOOL Row(id r) {
    if(![r isKindOfClass:NSDictionary.class] || [r count]!=8 || !Text(r[@"id"],36) || ![[NSUUID alloc] initWithUUIDString:r[@"id"]] || ![r[@"favorite"] isKindOfClass:NSNumber.class] || ![r[@"status"] isEqual:@"seen"]) return NO;
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
NSArray *WUMCacheLoad(NSURL *d, NSString *a, NSError **e) { @synchronized(NSFileManager.defaultManager) { return Load(d,a,e); } }
NSDictionary *WUMCacheObserve(NSURL *d, NSString *a, NSDictionary *item, NSTimeInterval now, NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        if(![item isKindOfClass:NSDictionary.class] || !isfinite(now) || now<=0) { Fail(e); return nil; }
        NSDictionary *n=WUMCacheNormalize(item[@"tid"],item[@"username"],item[@"text"]); if(!n) { Fail(e); return nil; }
        NSArray *old=Load(d,a,e); if(!old) return nil; NSMutableArray *rows=[old mutableCopy];
        NSUInteger i=[rows indexOfObjectPassingTest:^BOOL(NSDictionary *r, NSUInteger idx, BOOL *stop){return [r[@"tid"] isEqual:n[@"tid"]] && [r[@"username"] isEqual:n[@"username"]];}];
        if(i==NSNotFound && rows.count>=200) { Fail(e); return nil; }
        NSMutableDictionary *r=i==NSNotFound?[n mutableCopy]:[rows[i] mutableCopy];
        if(i==NSNotFound) { r[@"id"]=NSUUID.UUID.UUIDString; r[@"favorite"]=@NO; r[@"first"]=@(now); r[@"status"]=@"seen"; }
        else if([r[@"text"] isEqual:n[@"text"]] && now-[r[@"last"] doubleValue]<3600) return r;
        r[@"text"]=n[@"text"]; r[@"last"]=@(MAX(now,[r[@"last"] doubleValue]));
        if(i==NSNotFound) [rows insertObject:r atIndex:0]; else rows[i]=r;
        return Save(d,a,rows,e)?r:nil;
    }
}
BOOL WUMCacheFavorite(NSURL *d, NSString *a, NSString *uuid, NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        NSArray *old=Load(d,a,e); if(!old) return NO; NSMutableArray *rows=[old mutableCopy];
        for(NSUInteger i=0;i<rows.count;i++) if([rows[i][@"id"] isEqual:uuid]) { NSMutableDictionary *r=[rows[i] mutableCopy]; r[@"favorite"]=@(![r[@"favorite"] boolValue]); rows[i]=r; return Save(d,a,rows,e); } return Fail(e);
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
