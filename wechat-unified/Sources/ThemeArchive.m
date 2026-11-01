#import "ThemeArchive.h"
#import <zlib.h>
static uint16_t U16(const uint8_t *p) { return p[0]|((uint16_t)p[1]<<8); }
static uint32_t U32(const uint8_t *p) { return U16(p)|((uint32_t)U16(p+2)<<16); }
static NSDictionary *Fail(NSError **e, NSString *s) { if(e) *e=[NSError errorWithDomain:@"WeChatUnified.ThemeZIP" code:1 userInfo:@{NSLocalizedDescriptionKey:s}]; return nil; }
NSString *WUThemeKey(NSString *name) {
    NSString *s=name.lastPathComponent.lowercaseString;
    if([@[@"png",@"svg",@"jpg",@"jpeg",@"heic",@"webp",@"car"] containsObject:s.pathExtension]) s=s.stringByDeletingPathExtension;
    if([s hasSuffix:@"@2x"] || [s hasSuffix:@"@3x"]) s=[s substringToIndex:s.length-3];
    return s;
}
BOOL WUThemeBubble(NSString *s) { s=WUThemeKey(s); return [s hasPrefix:@"chatroom_bubble_"] || [s hasPrefix:@"text_bubble_receiver_"]; }
NSDictionary<NSString *, NSData *> *WUReadThemeZIP(NSData *data, NSError **error) {
    const uint8_t *b=data.bytes; NSUInteger n=data.length;
    if(n<22 || n>32*1024*1024) return Fail(error,@"ZIP须小于32MB且非空");
    NSUInteger end=NSNotFound, lower=n>65557?n-65557:0;
    for(NSUInteger p=n-22;;p--) { if(U32(b+p)==0x06054b50 && p+22+U16(b+p+20)==n) { end=p; break; } if(p==lower) break; }
    if(end==NSNotFound) return Fail(error,@"缺少ZIP目录");
    uint16_t count=U16(b+end+10); uint32_t size=U32(b+end+12), off=U32(b+end+16);
    if(U16(b+end+4)||U16(b+end+6)||U16(b+end+8)!=count||!count||count>512||off>end||size!=end-off) return Fail(error,@"拒绝多卷、ZIP64或超512项的包");
    NSMutableDictionary *files=[NSMutableDictionary dictionary]; NSMutableSet *seen=[NSMutableSet set]; NSMutableArray<NSValue *> *ranges=[NSMutableArray array];
    NSUInteger p=off,total=0;
    for(unsigned i=0;i<count;i++) {
        if(p>end || end-p<46 || U32(b+p)!=0x02014b50) return Fail(error,@"目录损坏");
        uint16_t flags=U16(b+p+8),method=U16(b+p+10),nl=U16(b+p+28),xl=U16(b+p+30),cl=U16(b+p+32);
        uint32_t crc=U32(b+p+16),packed=U32(b+p+20),plain=U32(b+p+24),local=U32(b+p+42),attr=U32(b+p+38);
        if((flags & ~0x0808) || (method!=0 && method!=8) || U16(b+p+34) || !nl || nl>240 || (NSUInteger)46+nl+xl+cl>end-p || plain>8*1024*1024 || packed>32*1024*1024 || total+plain>64*1024*1024 || (plain>1024*1024 && plain/(MAX(packed,1))>200)) return Fail(error,@"加密/算法/大小或压缩比不支持");
        NSString *name=[[NSString alloc] initWithBytes:b+p+46 length:nl encoding:NSUTF8StringEncoding];
        BOOL directory=[name hasSuffix:@"/"]; NSString *path=directory?[name substringToIndex:name.length-1]:name;
        if(!path.length || [path hasPrefix:@"/"] || [path containsString:@"\\"] || [path containsString:@":"] || [path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) return Fail(error,@"非法路径");
        for(NSString *part in [path componentsSeparatedByString:@"/"]) if(!part.length || [part isEqual:@"."] || [part isEqual:@".."]) return Fail(error,@"拒绝路径穿越");
        unsigned type=(attr>>16)&0170000;
        if(type && type!=(directory?0040000:0100000)) return Fail(error,@"拒绝符号链接和特殊文件");
        NSString *fold=path.precomposedStringWithCanonicalMapping.lowercaseString;
        if([seen containsObject:fold]) return Fail(error,@"重复路径"); [seen addObject:fold];
        if(local>off || off-local<30 || U32(b+local)!=0x04034b50 || U16(b+local+6)!=flags || U16(b+local+8)!=method || U16(b+local+26)!=nl) return Fail(error,@"本地头不一致");
        NSUInteger start=(NSUInteger)local+30+nl+U16(b+local+28);
        if(start>off || packed>off-start || memcmp(b+local+30,b+p+46,nl)) return Fail(error,@"数据越界或名称不一致");
        if(!(flags&8) && (U32(b+local+14)!=crc || U32(b+local+18)!=packed || U32(b+local+22)!=plain)) return Fail(error,@"长度校验不一致");
        NSRange range=NSMakeRange(local,start+packed-local);
        for(NSValue *v in ranges) if(NSIntersectionRange(range,v.rangeValue).length) return Fail(error,@"重叠数据"); [ranges addObject:[NSValue valueWithRange:range]];
        NSMutableData *out=[NSMutableData dataWithLength:MAX(plain,1)];
        if(method==0) { if(packed!=plain) return Fail(error,@"存储长度不一致"); memcpy(out.mutableBytes,b+start,plain); }
        else {
            z_stream z={0}; z.next_in=(Bytef *)(b+start); z.avail_in=packed; z.next_out=out.mutableBytes; z.avail_out=(uInt)out.length;
            if(inflateInit2(&z,-MAX_WBITS)!=Z_OK) return Fail(error,@"解码器不可用");
            int result=inflate(&z,Z_FINISH); BOOL valid=result==Z_STREAM_END && z.total_out==plain && z.total_in==packed; inflateEnd(&z);
            if(!valid) return Fail(error,@"压缩数据损坏或膨胀超限");
        }
        out.length=plain;
        if(crc32(0,out.bytes,(uInt)out.length)!=crc || (directory && plain)) return Fail(error,@"CRC失败");
        if(!directory) files[path]=out; total+=plain; p+=46+nl+xl+cl;
    }
    if(p!=end) return Fail(error,@"目录长度不一致");
    // Reject file/directory prefix collisions before any filesystem writes.
    NSMutableSet *filePaths=[NSMutableSet set]; for(NSString *path in files) [filePaths addObject:path.precomposedStringWithCanonicalMapping.lowercaseString];
    for(NSString *path in filePaths) { NSString *parent=path.stringByDeletingLastPathComponent; while(parent.length) { if([filePaths containsObject:parent]) return Fail(error,@"目录与文件冲突"); parent=parent.stringByDeletingLastPathComponent; } }
    return files;
}

static void Put16(NSMutableData *d,uint16_t x) { uint8_t b[]={x&255,x>>8}; [d appendBytes:b length:2]; }
static void Put32(NSMutableData *d,uint32_t x) { Put16(d,x&65535); Put16(d,x>>16); }
NSData *WUWriteThemeZIP(NSDictionary<NSString *,NSData *> *files,NSError **error) {
    if(!files.count||files.count>512) { Fail(error,@"空包或文件过多"); return nil; }
    NSMutableData *out=[NSMutableData data],*central=[NSMutableData data]; NSUInteger total=0;
    for(NSString *name in [[files allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSData *path=[name dataUsingEncoding:NSUTF8StringEncoding],*plain=files[name];
        if(![plain isKindOfClass:NSData.class]||!path.length||path.length>240||plain.length>8*1024*1024||(total+=plain.length)>64*1024*1024) { Fail(error,@"资源大小超过归档限制"); return nil; }
        NSData *payload=plain; uint16_t method=0;
        NSMutableData *compressed=[NSMutableData dataWithLength:compressBound((uLong)plain.length)]; z_stream z={0};
        if(deflateInit2(&z,Z_DEFAULT_COMPRESSION,Z_DEFLATED,-MAX_WBITS,8,Z_DEFAULT_STRATEGY)==Z_OK) {
            z.next_in=(Bytef *)plain.bytes; z.avail_in=(uInt)plain.length; z.next_out=compressed.mutableBytes; z.avail_out=(uInt)compressed.length;
            int status=deflate(&z,Z_FINISH); compressed.length=z.total_out; deflateEnd(&z);
            if(status==Z_STREAM_END&&compressed.length<plain.length&&!(plain.length>1024*1024&&plain.length/MAX(compressed.length,1)>200)) { payload=compressed; method=8; }
        }
        uint32_t offset=(uint32_t)out.length,crc=(uint32_t)crc32(0,plain.bytes,(uInt)plain.length);
        Put32(out,0x04034b50); Put16(out,20); Put16(out,0x800); Put16(out,method); Put16(out,0); Put16(out,0x21); Put32(out,crc); Put32(out,(uint32_t)payload.length); Put32(out,(uint32_t)plain.length); Put16(out,(uint16_t)path.length); Put16(out,0); [out appendData:path]; [out appendData:payload];
        Put32(central,0x02014b50); Put16(central,0x0314); Put16(central,20); Put16(central,0x800); Put16(central,method); Put16(central,0); Put16(central,0x21); Put32(central,crc); Put32(central,(uint32_t)payload.length); Put32(central,(uint32_t)plain.length); Put16(central,(uint16_t)path.length); Put16(central,0); Put16(central,0); Put16(central,0); Put16(central,0); Put32(central,0100600u<<16); Put32(central,offset); [central appendData:path];
        if(out.length+central.length+22>32*1024*1024) { Fail(error,@"导出ZIP超过32MB，请拆分资源包"); return nil; }
    }
    uint32_t offset=(uint32_t)out.length; [out appendData:central]; Put32(out,0x06054b50); Put16(out,0); Put16(out,0); Put16(out,(uint16_t)files.count); Put16(out,(uint16_t)files.count); Put32(out,(uint32_t)central.length); Put32(out,offset); Put16(out,0);
    // Share exactly the reader's path, case, CRC and size contract; no export-only bypass.
    if(!WUReadThemeZIP(out,error)) return nil; return out;
}
