#import "EmoticonLibraryLogic.h"
#import "EmoticonLogic.h"
#import "DraftMediaLogic.h"
#import "EmoticonLibrarySafety.h"
#import <CommonCrypto/CommonDigest.h>
static BOOL Fail(NSError **e, NSString *text) { if(e) *e=[NSError errorWithDomain:@"WUEmoticonLibrary" code:1 userInfo:@{NSLocalizedDescriptionKey:text}]; return NO; }
static BOOL Text(id v, NSUInteger max) { return [v isKindOfClass:NSString.class] && [v length] && [v length]<=max; }
static BOOL UUID(id v) { return Text(v,36) && [[NSUUID alloc] initWithUUIDString:v]!=nil; }
NSString *WUEmoticonDigest(NSData *data) {
    if(![data isKindOfClass:NSData.class] || data.length>20*1024*1024) return nil;
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(data.bytes,(CC_LONG)data.length,digest);
#pragma clang diagnostic pop
    NSMutableString *value=[NSMutableString string]; for(NSUInteger i=0;i<sizeof digest;i++) [value appendFormat:@"%02x",digest[i]]; return value;
}
static BOOL Valid(id s, NSString *account) {
    if(![s isKindOfClass:NSDictionary.class] || [s count]!=4 || ![s[@"schema"] isEqual:@1] || ![s[@"account"] isEqual:account] || ![s[@"groups"] isKindOfClass:NSArray.class] || [s[@"groups"] count]>32 || ![s[@"rows"] isKindOfClass:NSArray.class] || [s[@"rows"] count]>128) return NO;
    NSMutableSet *groups=[NSMutableSet set], *ids=[NSMutableSet set]; NSUInteger size=0;
    for(id g in s[@"groups"]) {
        if(![g isKindOfClass:NSDictionary.class] || [g count]!=2 || !UUID(g[@"id"]) || !Text(g[@"name"],40) || [groups containsObject:g[@"id"]]) return NO;
        [groups addObject:g[@"id"]];
    }
    for(id r in s[@"rows"]) {
        if(![r isKindOfClass:NSDictionary.class] || [r count]!=6 || !UUID(r[@"id"]) || [ids containsObject:r[@"id"]] || !Text(r[@"name"],80) || ![r[@"group"] isKindOfClass:NSString.class] || ([r[@"group"] length] && ![groups containsObject:r[@"group"]]) || ![r[@"data"] isKindOfClass:NSData.class] || ![r[@"data"] length] || [r[@"data"] length]>20*1024*1024 || ![@[@"com.compuserve.gif",@"public.png",@"public.jpeg"] containsObject:r[@"uti"]] || ![WUEmoticonDigest(r[@"data"]) isEqual:r[@"md5"]]) return NO;
        size+=[r[@"data"] length]; if(size>48*1024*1024) return NO; [ids addObject:r[@"id"]];
    }
    return YES;
}
NSArray<NSDictionary *> *WUEmoticonLibraryRows(NSDictionary *state, NSString *group) {
    NSMutableArray *rows=[NSMutableArray array]; for(NSDictionary *r in state[@"rows"]) if(!group || [r[@"group"] isEqual:group]) [rows addObject:r]; return rows;
}
static NSObject *Lock(void) { static NSObject *lock; static dispatch_once_t once; dispatch_once(&once,^{ lock=[NSObject new]; }); return lock; }
static bool Current(void *p) { BOOL (^block)(void)=(__bridge id)p; return block && block(); }
@interface WUEmoticonLibraryStore ()
@property(nonatomic,copy) NSString *account;
@property(nonatomic,strong) NSURL *directory;
@end
@implementation WUEmoticonLibraryStore
- (instancetype)initWithRoot:(NSURL *)root account:(NSString *)account {
    if(!(self=[super init])) return nil;
    NSData *bytes=[account isKindOfClass:NSString.class]?[account dataUsingEncoding:NSUTF8StringEncoding]:nil;
    if(!bytes.length || bytes.length>100 || !root.isFileURL || ![root.path isEqual:root.URLByStandardizingPath.URLByResolvingSymlinksInPath.path]) return nil;
    NSMutableString *key=[NSMutableString string]; const unsigned char *b=bytes.bytes;
    for(NSUInteger i=0;i<bytes.length;i++) [key appendFormat:@"%02x",b[i]];
    _account=[account copy]; _directory=[root URLByAppendingPathComponent:key isDirectory:YES]; return self;
}
- (BOOL)safe { return [self.directory.path isEqual:self.directory.URLByStandardizingPath.URLByResolvingSymlinksInPath.path]; }
- (NSDictionary *)load:(NSError **)error {
    @synchronized(Lock()) {
        if(![self safe]) { Fail(error,@"目录链接不安全，原数据保留"); return nil; }
        NSURL *index=[self.directory URLByAppendingPathComponent:@"index.plist"]; struct stat st;
        if(lstat(index.path.fileSystemRepresentation,&st)) {
            if(errno==ENOENT) return @{@"schema":@1,@"account":self.account,@"groups":@[],@"rows":@[]};
            Fail(error,@"索引不可读，不覆盖原数据"); return nil;
        }
        if(!S_ISREG(st.st_mode) || st.st_nlink!=1 || st.st_size<=0 || st.st_size>64*1024*1024) { Fail(error,@"索引非自有普通文件或超限"); return nil; }
        NSData *data=WUDraftMediaReadSource(index,64*1024*1024);
        id s=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error]:nil;
        if(!Valid(s,self.account)) { Fail(error,@"表情库损坏或账号不符，禁止覆盖"); return nil; } return s;
    }
}
- (BOOL)commit:(NSDictionary *)state current:(BOOL (^)(void))current error:(NSError **)error {
    if(!current || !current() || ![self safe] || !Valid(state,self.account)) return Fail(error,@"账号/代次失效或资源超限，未保存");
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if(!data || data.length>64*1024*1024) return Fail(error,@"索引超过64MiB，旧数据保留");
    if(![NSFileManager.defaultManager createDirectoryAtURL:self.directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:error]) return NO;
    NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:self.directory includingPropertiesForKeys:nil options:0 error:error];
    if(!files || files.count>=16 || ![self safe]) return Fail(error,@"自有目录异常或未完成副本达16个，未清扫未知文件");
    uint64_t used=0;
    for(NSURL *url in files) { struct stat st; if(lstat(url.path.fileSystemRepresentation,&st) || !S_ISREG(st.st_mode) || st.st_nlink!=1 || st.st_size<0) return Fail(error,@"目录含非自有文件，拒绝写入"); used+=(uint64_t)st.st_size; }
    if(used+data.length>160ULL*1024*1024) return Fail(error,@"含未完成副本超过160MiB");
    BOOL ok=WUEmojiAtomicCommit(self.directory.path.fileSystemRepresentation,NSUUID.UUID.UUIDString.UTF8String,data.bytes,data.length,Current,(__bridge void *)current);
    return ok?YES:Fail(error,@"复制校验、账号代次或原子提交失败；旧库保留");
}
- (BOOL)importData:(NSData *)data name:(NSString *)name group:(NSString *)group current:(BOOL (^)(void))current error:(NSError **)error {
    @synchronized(Lock()) {
        if(!current || !current() || !Text(name,80)) return Fail(error,@"上下文失效或名称无效");
        NSData *original=[data copy]; NSString *uti=WUEmoticonType(original);
        if(!uti) return Fail(error,@"仅完整原始GIF/PNG/JPEG；损坏、特殊缓存编码或超限不转换冒充原表情");
        NSDictionary *old=[self load:error]; if(!old) return NO;
        for(NSDictionary *r in old[@"rows"]) if([r[@"data"] isEqual:original]) return Fail(error,@"本账号已保存相同原始字节；可在库内移动分组");
        NSMutableDictionary *next=[old mutableCopy]; NSMutableArray *rows=[old[@"rows"] mutableCopy];
        [rows addObject:@{@"id":NSUUID.UUID.UUIDString,@"name":name,@"group":group?:@"",@"data":original,@"uti":uti,@"md5":WUEmoticonDigest(original)}]; next[@"rows"]=rows;
        return [self commit:next current:current error:error];
    }
}
- (BOOL)importFile:(NSURL *)url name:(NSString *)name group:(NSString *)group current:(BOOL (^)(void))current error:(NSError **)error {
    if(!current || !current() || !url.isFileURL) return Fail(error,@"导入上下文或文件无效");
    // File extensions are not format evidence; WxAM/thumbnail substitutions are not accepted.
    NSData *data=WUEmoticonRead(url.path); return data?[self importData:data name:name group:group current:current error:error]:Fail(error,@"原文件不可读、链接不安全或超过20MiB");
}
- (BOOL)createGroup:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error {
    @synchronized(Lock()) {
        name=[name isKindOfClass:NSString.class]?[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:nil;
        if(!Text(name,40)) return Fail(error,@"分组名称须为1至40字符");
        NSDictionary *old=[self load:error]; if(!old) return NO; NSMutableDictionary *next=[old mutableCopy]; NSMutableArray *groups=[old[@"groups"] mutableCopy];
        [groups addObject:@{@"id":NSUUID.UUID.UUIDString,@"name":name}]; next[@"groups"]=groups; return [self commit:next current:current error:error];
    }
}
- (BOOL)change:(NSString *)identifier group:(BOOL)group current:(BOOL (^)(void))current edit:(BOOL (^)(NSMutableArray *,NSUInteger,NSMutableDictionary *))edit error:(NSError **)error {
    @synchronized(Lock()) {
        if(!UUID(identifier)) return Fail(error,@"标识符无效");
        NSDictionary *old=[self load:error]; if(!old) return NO; NSString *key=group?@"groups":@"rows";
        NSMutableArray *items=[old[key] mutableCopy]; NSUInteger i=[items indexOfObjectPassingTest:^BOOL(NSDictionary *r,NSUInteger idx,BOOL *stop){ return [r[@"id"] isEqual:identifier]; }];
        if(i==NSNotFound) return Fail(error,@"条目已不存在，原数据保留");
        NSMutableDictionary *next=[old mutableCopy]; next[key]=items;
        if(!edit(items,i,next)) return Fail(error,@"名称、分组或目标排序无效");
        return [self commit:next current:current error:error];
    }
}
- (BOOL)rename:(NSString *)identifier group:(BOOL)group name:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error {
    name=[name isKindOfClass:NSString.class]?[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:nil;
    return [self change:identifier group:group current:current edit:^BOOL(NSMutableArray *items,NSUInteger i,NSMutableDictionary *next){
        if(!Text(name,group?40:80)) return NO; NSMutableDictionary *r=[items[i] mutableCopy]; r[@"name"]=name; items[i]=r; return YES;
    } error:error];
}
- (BOOL)move:(NSString *)identifier group:(BOOL)group to:(NSUInteger)index current:(BOOL (^)(void))current error:(NSError **)error {
    return [self change:identifier group:group current:current edit:^BOOL(NSMutableArray *items,NSUInteger i,NSMutableDictionary *next){
        if(index>=items.count) return NO; id r=items[i]; [items removeObjectAtIndex:i]; [items insertObject:r atIndex:index]; return YES;
    } error:error];
}
- (BOOL)assign:(NSString *)identifier group:(NSString *)group current:(BOOL (^)(void))current error:(NSError **)error {
    return [self change:identifier group:NO current:current edit:^BOOL(NSMutableArray *items,NSUInteger i,NSMutableDictionary *next){
        if(![group isKindOfClass:NSString.class]) return NO;
        NSMutableDictionary *r=[items[i] mutableCopy]; r[@"group"]=group; items[i]=r; return YES;
    } error:error];
}
- (BOOL)remove:(NSString *)identifier group:(BOOL)group current:(BOOL (^)(void))current error:(NSError **)error {
    return [self change:identifier group:group current:current edit:^BOOL(NSMutableArray *items,NSUInteger i,NSMutableDictionary *next){
        [items removeObjectAtIndex:i];
        if(group) {
            NSMutableArray *rows=[NSMutableArray array]; for(NSDictionary *r in next[@"rows"]) {
                NSMutableDictionary *row=[r mutableCopy]; if([row[@"group"] isEqual:identifier]) row[@"group"]=@""; [rows addObject:row];
            } next[@"rows"]=rows;
        } return YES;
    } error:error];
}
- (NSDictionary *)resource:(NSString *)identifier error:(NSError **)error {
    @synchronized(Lock()) {
        for(NSDictionary *r in [self load:error][@"rows"]) if([r[@"id"] isEqual:identifier]) {
            if([WUEmoticonType(r[@"data"]) isEqual:r[@"uti"]]) return r;
            Fail(error,@"资源完整解码失败；未用首帧或缩略图替代"); return nil;
        }
        Fail(error,@"资源不存在或不可读"); return nil;
    }
}
@end
