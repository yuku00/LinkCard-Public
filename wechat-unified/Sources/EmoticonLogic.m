#import "EmoticonLogic.h"
#import <ImageIO/ImageIO.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>
#include <zlib.h>
static uint32_t BE32(const unsigned char *p) { return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3]; }
static BOOL PNGComplete(const unsigned char *b, NSUInteger n) {
    NSUInteger p=8; BOOL header=NO, pixels=NO;
    while(n-p>=12) { uint32_t len=BE32(b+p); if(len>n-p-12) return NO;
        const unsigned char *type=b+p+4;
        if(!header && (memcmp(type,"IHDR",4) || len!=13)) return NO;
        header=YES;
        if(crc32(0,type,len+4)!=BE32(b+p+8+len)) return NO;
        if(!memcmp(type,"IDAT",4)) pixels=YES;
        if(!memcmp(type,"IEND",4)) return pixels && len==0 && p+12==n;
        p+=12+len;
    } return NO;
}
static NSUInteger GIFComplete(const unsigned char *b, NSUInteger n) {
    NSUInteger p=13, frames=0; if(b[10]&128) p+=3*((NSUInteger)2<<(b[10]&7));
    while(p<n) { unsigned char tag=b[p++];
        if(tag==0x3b) return p==n?frames:0;
        if(tag==0x21) { if(p>=n) return NO; p++; }
        else if(tag==0x2c) { if(n-p<9) return NO; unsigned char packed=b[p+8]; p+=9; if(packed&128) p+=3*((NSUInteger)2<<(packed&7)); if(p>=n || b[p]<2 || b[p]>8) return NO; p++; frames++; }
        else return NO;
        BOOL end=NO; while(p<n) { NSUInteger size=b[p++]; if(!size) { end=YES; break; } if(size>n-p) return NO; p+=size; }
        if(!end) return NO;
    } return NO;
}
static const NSUInteger Limit=20*1024*1024;
NSData *WUEmoticonRead(NSString *path) {
    if(![path isKindOfClass:NSString.class] || !path.isAbsolutePath || ![path.stringByStandardizingPath isEqual:path.stringByResolvingSymlinksInPath]) return nil;
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW); if(fd<0) return nil;
    struct stat a,b;
    if(fstat(fd,&a)!=0 || !S_ISREG(a.st_mode) || a.st_size<=0 || a.st_size>(off_t)Limit) { close(fd); return nil; }
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)a.st_size]; NSUInteger pos=0;
    while(pos<data.length) { ssize_t n=read(fd,(char *)data.mutableBytes+pos,data.length-pos); if(n<0 && errno==EINTR) continue; if(n<=0) { close(fd); return nil; } pos+=(NSUInteger)n; }
    char extra; ssize_t n; do { n=read(fd,&extra,1); } while(n<0 && errno==EINTR);
    BOOL ok=n==0 && fstat(fd,&b)==0 && a.st_size==b.st_size && a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec;
    close(fd); return ok?[data copy]:nil;
}
NSString *WUEmoticonType(NSData *data) {
    if(![data isKindOfClass:NSData.class] || data.length<14 || data.length>Limit) return nil;
    const unsigned char *b=data.bytes; NSUInteger n=data.length; NSString *uti=nil;
    if((!memcmp(b,"GIF87a",6)||!memcmp(b,"GIF89a",6)) && b[n-1]==0x3b) uti=@"com.compuserve.gif";
    else if(!memcmp(b,"\x89PNG\r\n\x1a\n",8) && n>=32 && !memcmp(b+n-12,"\0\0\0\0IEND\xae\x42\x60\x82",12)) uti=@"public.png";
    else if(b[0]==0xff && b[1]==0xd8 && b[2]==0xff && b[n-2]==0xff && b[n-1]==0xd9) uti=@"public.jpeg";
    if(!uti || ([uti isEqual:@"public.png"] && !PNGComplete(b,n)) || ([uti isEqual:@"com.compuserve.gif"] && !GIFComplete(b,n))) return nil;
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
    if(!source) return nil;
    size_t count=CGImageSourceGetCount(source); BOOL ok=count>0 && count<=500 && CGImageSourceGetStatus(source)==kCGImageStatusComplete && [uti isEqual:(__bridge NSString *)CGImageSourceGetType(source)];
    if([uti isEqual:@"com.compuserve.gif"] && count!=GIFComplete(b,n)) ok=NO;
    uint64_t pixels=0;
    for(size_t i=0;ok && i<count;i++) { @autoreleasepool {
        NSDictionary *p=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,i,NULL));
        uint64_t w=[p[(id)kCGImagePropertyPixelWidth] unsignedLongLongValue], h=[p[(id)kCGImagePropertyPixelHeight] unsignedLongLongValue];
        if(!w || !h || w>16000000 || h>16000000 || w*h>16000000 || (pixels+=w*h)>64000000) { ok=NO; break; }
        CGImageRef image=CGImageSourceCreateImageAtIndex(source,i,(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCacheImmediately:@YES});
        ok=image && CGImageSourceGetStatusAtIndex(source,i)==kCGImageStatusComplete;
        if(image) CGImageRelease(image);
    } }
    CFRelease(source); return ok?uti:nil;
}
@interface WUEmoticonSave ()
@property(nonatomic,readwrite) BOOL started;
@property(nonatomic) BOOL authorized;
@property(nonatomic) BOOL finished;
@end
@implementation WUEmoticonSave
- (BOOL)startData:(NSData *)data current:(BOOL (^)(void))current permission:(WUEmoticonPermission)permission writer:(WUEmoticonWriter)writer completion:(void (^)(NSString *))completion {
    // All transitions run on the main queue; native asynchronous replies are marshalled below.
    if(!NSThread.isMainThread || self.started) return NO;
    self.started=YES; NSData *original=[data copy]; NSString *uti=WUEmoticonType(original);
    if(!uti || !current()) { self.finished=YES; completion(uti?@"cancelled":@"invalid"); return YES; }
    permission(^(BOOL allowed){ dispatch_async(dispatch_get_main_queue(),^{
        if(self.finished || self.authorized) return;
        if(!current() || !allowed) { self.finished=YES; completion(!current()?@"cancelled":@"denied"); return; }
        self.authorized=YES;
        writer(original,uti,^(BOOL success){ dispatch_async(dispatch_get_main_queue(),^{
            if(self.finished) return; self.finished=YES;
            // A committed transaction cannot be cancelled; never show old-account success.
            completion(!current()?@"cancelled":(success?@"saved":@"failed"));
        }); });
    }); }); return YES;
}
@end
