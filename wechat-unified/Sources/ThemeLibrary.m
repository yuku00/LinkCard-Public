#import "ThemeLibrary.h"
#import "ThemeCatalog.h"
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdio.h>
static id Failed(NSError **e,NSString *s) { if(e&&!*e) *e=[NSError errorWithDomain:@"WeChatUnified.ThemeFiles" code:1 userInfo:@{NSLocalizedDescriptionKey:s}]; return nil; }
NSDictionary *WUThemePackMetadata(NSString *p) {
    for(NSString *name in @[@".wu-pack.json",@"manifest.json"]) {
        NSString *path=[p stringByAppendingPathComponent:name]; struct stat st;
        if(lstat(path.fileSystemRepresentation,&st)||!S_ISREG(st.st_mode)||st.st_size>16384) continue;
        NSData *d=[NSData dataWithContentsOfFile:path]; id v=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
        if([v isKindOfClass:NSDictionary.class]&&[v[@"name"] isKindOfClass:NSString.class]) {
            BOOL valid=YES; for(NSString *key in @[@"size",@"imported",@"modified",@"resources",@"png"]) if(v[key]&&![v[key] isKindOfClass:NSNumber.class]) valid=NO;
            if(valid) return v;
        }
    } return nil;
}
NSDictionary *WUThemeReadPackFiles(NSString *root,NSError **error) {
    if(!root.length) return Failed(error,@"资源包不存在"); struct stat st;
    if(lstat(root.fileSystemRepresentation,&st)||!S_ISDIR(st.st_mode)) return Failed(error,@"资源包不是普通目录");
    NSMutableDictionary *out=[NSMutableDictionary dictionary]; NSUInteger total=0;
    NSDirectoryEnumerator *enumerator=[NSFileManager.defaultManager enumeratorAtPath:root];
    BOOL legacy=![NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@".wu-pack.json"]];
    for(NSString *relative in enumerator) {
        if([relative.lastPathComponent hasPrefix:@"."]) { [enumerator skipDescendants]; continue; }
        if(legacy&&[relative isEqual:@"manifest.json"]) continue;
        NSString *path=[root stringByAppendingPathComponent:relative];
        if(!WUThemeSafePath(relative)||lstat(path.fileSystemRepresentation,&st)) return Failed(error,@"目录包含非法路径");
        if(S_ISDIR(st.st_mode)) continue;
        if(!S_ISREG(st.st_mode)||st.st_size<0||st.st_size>8*1024*1024||(total+=(NSUInteger)st.st_size)>64*1024*1024) return Failed(error,@"拒绝链接、特殊文件或超限资源");
        int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW); if(fd<0) return Failed(error,@"读取失败");
        struct stat current; BOOL ok=!fstat(fd,&current)&&S_ISREG(current.st_mode)&&current.st_ino==st.st_ino&&current.st_size==st.st_size;
        NSMutableData *d=[NSMutableData dataWithLength:ok?(NSUInteger)st.st_size:0]; NSUInteger offset=0;
        while(ok&&offset<d.length) { ssize_t n=read(fd,(char *)d.mutableBytes+offset,d.length-offset); if(n<=0) { ok=NO; break; } offset+=n; } close(fd);
        if(!ok) return Failed(error,@"资源读取期间发生变化"); out[relative]=d;
        if(out.count>510) return Failed(error,@"资源数超过510");
    } return out;
}
BOOL WUThemeCommitPack(NSString *root,NSString *identifier,NSDictionary *files,NSDictionary *metadata,NSError **error) {
    if(![[NSUUID alloc] initWithUUIDString:identifier]||!WUThemeMergeFiles(@{},files,NO,error)) return NO;
    struct stat st; if(!root.length||lstat(root.fileSystemRepresentation,&st)||!S_ISDIR(st.st_mode)) { Failed(error,@"仓库目录不可用"); return NO; }
    NSString *stage=[root stringByAppendingPathComponent:[@".pending-" stringByAppendingString:NSUUID.UUID.UUIDString]],*dest=[root stringByAppendingPathComponent:identifier];
    if(mkdir(stage.fileSystemRepresentation,0700)) { Failed(error,@"无法创建导入事务"); return NO; }
    BOOL ok=YES;
    for(NSString *p in files) {
        NSString *target=[stage stringByAppendingPathComponent:p];
        ok=[NSFileManager.defaultManager createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]&&[files[p] writeToFile:target options:NSDataWritingAtomic error:error]; if(!ok) break;
    }
    NSData *meta=ok?[NSJSONSerialization dataWithJSONObject:metadata options:0 error:error]:nil;
    ok=ok&&meta.length<=16384&&[meta writeToFile:[stage stringByAppendingPathComponent:@".wu-pack.json"] options:NSDataWritingAtomic error:error];
    if(ok) {
        if(!lstat(dest.fileSystemRepresentation,&st)) {
            // Atomic directory exchange keeps the selected UUID stable; a failed swap leaves old files intact.
            ok=S_ISDIR(st.st_mode)&&renamex_np(stage.fileSystemRepresentation,dest.fileSystemRepresentation,RENAME_SWAP)==0;
        } else ok=rename(stage.fileSystemRepresentation,dest.fileSystemRepresentation)==0;
    }
    [NSFileManager.defaultManager removeItemAtPath:stage error:NULL]; if(!ok) Failed(error,@"导入提交失败，原资源包保留"); return ok;
}
