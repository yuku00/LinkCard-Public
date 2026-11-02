#import "VoicePackLogic.h"
#import "VoiceSendLogic.h"
#import "DraftMediaLogic.h"
#import "VoiceAudio.h"
#include <sys/stat.h>
#include <errno.h>
#include <unistd.h>
#include <string.h>
static BOOL Fail(NSError **e, NSString *s) { if(e) *e=[NSError errorWithDomain:@"WUVoicePack" code:1 userInfo:@{NSLocalizedDescriptionKey:s}]; return NO; }
static BOOL Text(id x, NSUInteger n) { return [x isKindOfClass:NSString.class] && [x length]>0 && [x length]<=n; }
static BOOL Pairing(id r) {
    BOOL selected=[r[@"source"] isEqual:@"selected-type34"] && [r[@"format"] isEqual:@4] && [r[@"pairing"] isEqual:@1] && Text(r[@"version"],160);
    BOOL imported=[r[@"source"] isEqual:@"imported-audio"] && [r[@"format"] isEqual:@(-1)] && [r[@"pairing"] isEqual:@0] && [r[@"version"] isEqual:@""];
    BOOL generated=[r[@"source"] isEqual:@"external-encoded-silk-v1"] && [r[@"format"] isEqual:@4] && [r[@"pairing"] isEqual:@0] && Text(r[@"version"],160);
    return selected || imported || generated;
}
BOOL WUVoicePackMatches(NSDictionary *r, NSString *version) {
    if(![r isKindOfClass:NSDictionary.class] || !Text(version,160) || ![r[@"version"] isEqual:version] || ![r[@"format"] isEqual:@4]) return NO;
    if([r[@"source"] isEqual:@"selected-type34"] && [r[@"pairing"] isEqual:@1]) return YES;
    NSData *data=r[@"data"]; const unsigned char *p=[data isKindOfClass:NSData.class]?data.bytes:NULL;
    return [r[@"source"] isEqual:@"external-encoded-silk-v1"] && [r[@"pairing"] isEqual:@0] && data.length>10 && p && !memcmp(p,"\x02#!SILK_V3",10) && [r[@"ms"] unsignedIntValue]>0 && WUVoiceMeasuredMS(data)==[r[@"ms"] unsignedIntValue];
}
static NSMutableDictionary *Leases(void) { static NSMutableDictionary *v; static dispatch_once_t once; dispatch_once(&once,^{ v=[NSMutableDictionary dictionary]; }); return v; }
@interface WUVoicePackStore ()
@property(nonatomic,strong) NSURL *directory;
@property(nonatomic,copy) NSString *account;
@end
@implementation WUVoicePackStore
- (instancetype)initWithRoot:(NSURL *)root account:(NSString *)account {
    if(!(self=[super init])) return nil;
    if(!Text(account,256)) return nil;
    NSData *a=[account dataUsingEncoding:NSUTF8StringEncoding];
    if(!root.isFileURL || !Text(account,256) || a.length>100 || ![root.path isEqual:root.URLByStandardizingPath.URLByResolvingSymlinksInPath.path]) return nil;
    NSMutableString *key=[NSMutableString string]; const unsigned char *b=a.bytes;
    for(NSUInteger i=0;i<a.length;i++) [key appendFormat:@"%02x",b[i]];
    _directory=[root URLByAppendingPathComponent:key isDirectory:YES]; _account=[account copy]; return self;
}
- (BOOL)safe {
    return [self.directory.path isEqual:self.directory.URLByStandardizingPath.URLByResolvingSymlinksInPath.path];
}
- (NSArray *)load:(NSError **)error {
    @synchronized(Leases()) {
        if(![self safe]) { Fail(error,@"目录链接不安全"); return nil; }
        NSURL *p=[self.directory URLByAppendingPathComponent:@"index.plist"]; struct stat st;
        if(lstat(p.path.fileSystemRepresentation,&st)) { if(errno==ENOENT) return @[]; Fail(error,@"索引不可读，保留原数据"); return nil; }
        if(!S_ISREG(st.st_mode) || st.st_nlink!=1 || st.st_size>32*1024*1024) { Fail(error,@"索引非自有普通文件或超限"); return nil; }
        NSData *data=WUDraftMediaReadSource(p,32*1024*1024);
        id value=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error]:nil;
        if(![value isKindOfClass:NSDictionary.class] || [value count]!=3 || ![value[@"schema"] isEqual:@1] || ![value[@"account"] isEqual:self.account] || ![value[@"rows"] isKindOfClass:NSArray.class] || [value[@"rows"] count]>32) { Fail(error,@"语音索引损坏，禁止覆盖"); return nil; }
        NSMutableSet *ids=[NSMutableSet set];
        for(id r in value[@"rows"]) {
            if(![r isKindOfClass:NSDictionary.class] || [r count]!=8 || !Text(r[@"id"],36) || ![[NSUUID alloc] initWithUUIDString:r[@"id"]] || [ids containsObject:r[@"id"]] || !Text(r[@"name"],80) || !Pairing(r) || ![r[@"data"] isKindOfClass:NSData.class] || [r[@"data"] length]<6 || [r[@"data"] length]>8*1024*1024 || ![r[@"ms"] isKindOfClass:NSNumber.class] || [r[@"ms"] unsignedIntValue]==0 || [r[@"ms"] unsignedIntValue]>60000 || [r[@"ms"] doubleValue]!=[r[@"ms"] unsignedIntValue]) { Fail(error,@"语音条目损坏，禁止覆盖"); return nil; }
            [ids addObject:r[@"id"]];
        }
        return value[@"rows"];
    }
}
- (BOOL)commit:(NSArray *)rows current:(BOOL (^)(void))current error:(NSError **)error {
    if(!current || !current() || ![self safe]) return Fail(error,@"账号或代次失效，未保存");
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:@{@"schema":@1,@"account":self.account,@"rows":rows} format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if(!data || data.length>32*1024*1024 || rows.count>32) return Fail(error,@"语音包已达32条或32MiB上限");
    if(![NSFileManager.defaultManager createDirectoryAtURL:self.directory withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:error]) return NO;
    NSURL *tmp=[self.directory URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:self.directory includingPropertiesForKeys:nil options:0 error:error];
    if(!files || files.count>=64) return Fail(error,@"自有目录达到64文件上限；未清扫未知副本");
    unsigned long long used=0;
    for(NSURL *u in files) { struct stat st; if(lstat(u.path.fileSystemRepresentation,&st) || !S_ISREG(st.st_mode) || st.st_nlink!=1 || st.st_size<0) return Fail(error,@"自有目录存在不安全文件，拒绝写入"); used+=(unsigned long long)st.st_size; }
    if(used+data.length>96ULL*1024*1024) return Fail(error,@"含未完成副本已达96MiB，拒绝继续写入");
    if(![data writeToURL:tmp options:NSDataWritingWithoutOverwriting error:error]) return NO;
    BOOL ok=[WUDraftMediaReadSource(tmp,32*1024*1024) isEqual:data] && [self safe] && current();
    if(ok) ok=rename(tmp.path.fileSystemRepresentation,[[self.directory URLByAppendingPathComponent:@"index.plist"] path].fileSystemRepresentation)==0;
    if(!ok) { unlink(tmp.path.fileSystemRepresentation); return Fail(error,@"复制校验、代次或原子索引提交失败；旧数据保留"); }
    return YES;
}
- (BOOL)saveData:(NSData *)data format:(NSNumber *)format version:(NSString *)version name:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error {
    @synchronized(Leases()) {
        if(![format isEqual:@4] || !Text(version,160) || !Text(name,80)) return Fail(error,@"缺少真实配对格式、宿主版本或名称");
        NSData *copy=[data copy]; uint32_t ms=WUVoiceMeasuredMS(copy);
        if(!ms) return Fail(error,@"坏媒体、未知格式或真实时长超过60秒");
        NSArray *old=[self load:error]; if(!old) return NO;
        NSMutableArray *rows=[old mutableCopy];
        [rows insertObject:@{@"id":NSUUID.UUID.UUIDString,@"name":name,@"source":@"selected-type34",@"format":format,@"version":version,@"pairing":@1,@"ms":@(ms),@"data":copy} atIndex:0];
        return [self commit:rows current:current error:error];
    }
}
- (BOOL)importFile:(NSURL *)url name:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error {
    return [self importFile:url name:name version:nil current:current error:error];
}
- (BOOL)importFile:(NSURL *)url name:(NSString *)name version:(NSString *)version current:(BOOL (^)(void))current error:(NSError **)error {
    @synchronized(Leases()) {
        if(!current || !current()) return Fail(error,@"导入上下文失效");
        NSData *file=WUDraftMediaReadSource(url,10*1024*1024), *audio=file;
        if(!file) return Fail(error,@"所选文件不可读、变化或超过10MiB");
        // Plist is data only, never NSKeyedUnarchiver/host objects or referenced paths.
        if([url.pathExtension.lowercaseString isEqual:@"wuvoice"]) {
            id envelope=[NSPropertyListSerialization propertyListWithData:file options:NSPropertyListImmutable format:NULL error:error];
            if(![envelope isKindOfClass:NSDictionary.class] || [envelope count]!=5 || ![envelope[@"kind"] isEqual:@"wuvoice"] || ![envelope[@"schema"] isEqual:@1] || !Text(envelope[@"name"],80) || ![envelope[@"data"] isKindOfClass:NSData.class] || ![envelope[@"origin"] isKindOfClass:NSDictionary.class]) return Fail(error,@"语音交换包无效");
            audio=envelope[@"data"]; if(!name.length) name=envelope[@"name"];
            // origin only documents the export; it cannot become trusted pairing.
        }
        if(!Text(name,80)) return Fail(error,@"名称须为1至80字符");
        // Only bytes generated here can receive the encoder provenance; imported metadata never can.
        BOOL generated=NO;
        if(Text(version,160)) {
            NSData *encoded=WUVoiceTranscodeSilk(audio,current);
            if(!encoded) return Fail(error,@"音频损坏、格式不受支持、转码失败或超过60秒");
            audio=encoded; generated=YES;
        }
        uint32_t ms=WUVoiceMeasuredMS(audio);
        if(!ms && !generated && ![url.pathExtension.lowercaseString isEqual:@"wuvoice"]) {
            audio=WUVoiceTranscodeSilk(file,current);
            ms=WUVoiceMeasuredMS(audio);
        }
        if(!ms) return Fail(error,@"音频损坏、格式不受支持、转码失败或超过60秒；未猜测宿主format");
        NSArray *old=[self load:error]; if(!old) return NO;
        NSMutableArray *rows=[old mutableCopy];
        [rows insertObject:@{@"id":NSUUID.UUID.UUIDString,@"name":name,@"source":generated?@"external-encoded-silk-v1":@"imported-audio",@"format":generated?@4:@(-1),@"version":generated?version:@"",@"pairing":@0,@"ms":@(ms),@"data":[audio copy]} atIndex:0];
        return [self commit:rows current:current error:error];
    }
}
- (NSData *)exportResource:(NSString *)identifier error:(NSError **)error {
    NSDictionary *held=[self acquire:identifier error:error]; if(!held) return nil;
    @try {
        NSDictionary *origin=@{@"source":held[@"source"],@"format":held[@"format"],@"version":held[@"version"]};
        return [NSPropertyListSerialization dataWithPropertyList:@{@"kind":@"wuvoice",@"schema":@1,@"name":held[@"name"],@"data":held[@"data"],@"origin":origin} format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    } @finally { [self releaseResource:identifier]; }
}
- (BOOL)pair:(NSString *)identifier selectedData:(NSData *)data format:(NSNumber *)format version:(NSString *)version current:(BOOL (^)(void))current error:(NSError **)error {
    @synchronized(Leases()) {
        if(![format isEqual:@4] || !Text(version,160) || ![data isKindOfClass:NSData.class]) return Fail(error,@"缺少真实所选34类的配对信息");
        NSArray *old=[self load:error]; if(!old) return NO;
        NSUInteger i=[old indexOfObjectPassingTest:^BOOL(NSDictionary *r, NSUInteger idx, BOOL *stop){ return [r[@"id"] isEqual:identifier]; }];
        if(i==NSNotFound || [Leases()[[self leaseKey:identifier]] unsignedIntegerValue]) return Fail(error,@"资源不存在或正在使用");
        NSDictionary *row=old[i];
        if(![row[@"data"] isEqual:data] || WUVoiceMeasuredMS(data)!=[row[@"ms"] unsignedIntValue]) return Fail(error,@"导入载荷与宿主所选语音不逐字节相同，不能推断格式配对");
        NSMutableArray *rows=[old mutableCopy]; NSMutableDictionary *paired=[row mutableCopy];
        paired[@"source"]=@"selected-type34"; paired[@"format"]=[format copy]; paired[@"version"]=[version copy]; paired[@"pairing"]=@1; rows[i]=paired;
        return [self commit:rows current:current error:error];
    }
}
- (NSString *)leaseKey:(NSString *)identifier { return [self.directory.path stringByAppendingPathComponent:identifier]; }
- (BOOL)change:(NSString *)identifier name:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error {
    @synchronized(Leases()) {
        NSArray *old=[self load:error]; if(!old) return NO;
        NSUInteger i=[old indexOfObjectPassingTest:^BOOL(NSDictionary *r, NSUInteger idx, BOOL *stop){ return [r[@"id"] isEqual:identifier]; }];
        if(i==NSNotFound) return Fail(error,@"条目不存在");
        if([Leases()[[self leaseKey:identifier]] unsignedIntegerValue]) return Fail(error,@"试听或发送正在占用，请先停止");
        NSMutableArray *rows=[old mutableCopy];
        if(name) { if(!Text(name,80)) return Fail(error,@"名称须为1至80字符"); NSMutableDictionary *r=[rows[i] mutableCopy]; r[@"name"]=name; rows[i]=r; }
        else [rows removeObjectAtIndex:i];
        return [self commit:rows current:current error:error];
    }
}
- (BOOL)rename:(NSString *)identifier name:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error { return name?[self change:identifier name:name current:current error:error]:Fail(error,@"名称为空"); }
- (BOOL)remove:(NSString *)identifier current:(BOOL (^)(void))current error:(NSError **)error { return [self change:identifier name:nil current:current error:error]; }
- (NSDictionary *)acquire:(NSString *)identifier error:(NSError **)error {
    @synchronized(Leases()) {
        for(NSDictionary *r in [self load:error]) if([r[@"id"] isEqual:identifier]) {
            if(WUVoiceMeasuredMS(r[@"data"])!=[r[@"ms"] unsignedIntValue]) { Fail(error,@"离线重新校验失败"); return nil; }
            NSString *key=[self leaseKey:identifier]; Leases()[key]=@([Leases()[key] unsignedIntegerValue]+1); return r;
        }
        Fail(error,@"语音不存在或不可读"); return nil;
    }
}
- (void)releaseResource:(NSString *)identifier {
    @synchronized(Leases()) { NSString *key=[self leaseKey:identifier]; NSUInteger n=[Leases()[key] unsignedIntegerValue]; if(n>1) Leases()[key]=@(n-1); else [Leases() removeObjectForKey:key]; }
}
@end
