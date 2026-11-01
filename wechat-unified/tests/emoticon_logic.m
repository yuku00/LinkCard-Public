#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import "EmoticonLogic.h"
#include <unistd.h>
static int checks;
#define CHECK(x) do { checks++; if(!(x)) { fprintf(stderr,"FAILED line %d: %s\n",__LINE__,#x); abort(); } } while(0)
static NSData *Image(NSString *type, NSUInteger frames) {
    unsigned char pixel[]={255,0,0,255,0,255,0,255,0,0,255,255,255,255,255,255};
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixel,2,2,8,8,color,kCGImageAlphaPremultipliedLast);
    CGImageRef image=CGBitmapContextCreateImage(context); NSMutableData *d=[NSMutableData data];
    CGImageDestinationRef dest=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)d,(__bridge CFStringRef)type,frames,NULL);
    for(NSUInteger i=0;i<frames;i++) CGImageDestinationAddImage(dest,image,NULL);
    CHECK(CGImageDestinationFinalize(dest)); CFRelease(dest); CGImageRelease(image); CGContextRelease(context); CGColorSpaceRelease(color); return d;
}
static void Drain(void) { for(int i=0;i<8;i++) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]]; }
static void Transaction(NSData *data, BOOL allow, BOOL success, BOOL invalidateBeforePermission, BOOL invalidateBeforeResult) {
    WUEmoticonSave *op=[WUEmoticonSave new]; __block BOOL current=YES; __block int writes=0, results=0, prompts=0;
    __block NSString *result; __block void (^permissionReply)(BOOL); __block void (^writeReply)(BOOL);
    BOOL (^valid)(void)=^BOOL{ return current; };
    WUEmoticonPermission permission=^(void (^reply)(BOOL)){ prompts++; permissionReply=reply; };
    WUEmoticonWriter writer=^(NSData *bytes,NSString *uti,void (^reply)(BOOL)){ writes++; CHECK([bytes isEqual:data]); CHECK([uti isEqual:@"com.compuserve.gif"]); writeReply=reply; };
    void (^completion)(NSString *)=^(NSString *r){ results++; result=r; };
    CHECK([op startData:data current:valid permission:permission writer:writer completion:completion]);
    CHECK(![op startData:data current:valid permission:permission writer:writer completion:completion]);
    CHECK(prompts==1 && writes==0 && results==0);
    if(invalidateBeforePermission) current=NO;
    permissionReply(allow); permissionReply(allow); Drain();
    if(!allow || invalidateBeforePermission) { CHECK(writes==0 && results==1); CHECK([result isEqual:invalidateBeforePermission?@"cancelled":@"denied"]); return; }
    CHECK(writes==1 && results==0);
    if(invalidateBeforeResult) current=NO;
    writeReply(success); writeReply(!success); Drain();
    CHECK(results==1); CHECK([result isEqual:invalidateBeforeResult?@"cancelled":(success?@"saved":@"failed")]);
}
int main(void) { @autoreleasepool {
    NSData *gif=Image(@"com.compuserve.gif",2), *png=Image(@"public.png",1), *jpg=Image(@"public.jpeg",1);
    if(!WUEmoticonType(gif)) {
        CGImageSourceRef probe=CGImageSourceCreateWithData((__bridge CFDataRef)gif,NULL);
        fprintf(stderr,"Synthetic GIF bytes=%s status=%ld type=%s count=%zu\n",[gif base64EncodedStringWithOptions:0].UTF8String,(long)CGImageSourceGetStatus(probe),[(__bridge NSString *)CGImageSourceGetType(probe) UTF8String],CGImageSourceGetCount(probe));
        for(size_t i=0;i<CGImageSourceGetCount(probe);i++) { NSDictionary *p=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(probe,i,NULL)); CGImageRef image=CGImageSourceCreateImageAtIndex(probe,i,NULL); fprintf(stderr,"frame=%zu status=%ld props=%s decoded=%d\n",i,(long)CGImageSourceGetStatusAtIndex(probe,i),p.description.UTF8String,image!=NULL); if(image) CGImageRelease(image); }
        CFRelease(probe);
    }
    CHECK([WUEmoticonType(gif) isEqual:@"com.compuserve.gif"]); CHECK([WUEmoticonType(png) isEqual:@"public.png"]); CHECK([WUEmoticonType(jpg) isEqual:@"public.jpeg"]);
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)gif,NULL); CHECK(CGImageSourceGetCount(source)==2); CFRelease(source);
    CHECK(!WUEmoticonType(nil)); CHECK(!WUEmoticonType([NSData data])); CHECK(!WUEmoticonType([NSMutableData dataWithLength:20*1024*1024+1]));
    for(NSData *d in @[gif,png,jpg]) { CHECK(!WUEmoticonType([d subdataWithRange:NSMakeRange(0,d.length-1)])); NSMutableData *bad=[d mutableCopy]; ((unsigned char *)bad.mutableBytes)[0]=0; CHECK(!WUEmoticonType(bad)); }
    NSMutableData *crc=[png mutableCopy]; ((unsigned char *)crc.mutableBytes)[29]^=1; CHECK(!WUEmoticonType(crc));
    NSMutableData *broken=[gif mutableCopy]; [broken replaceBytesInRange:NSMakeRange(13,broken.length-14) withBytes:NULL length:0]; CHECK(!WUEmoticonType(broken));
    NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]; CHECK([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSString *file=[dir stringByAppendingPathComponent:@"original.data"]; CHECK([gif writeToFile:file atomically:YES]); CHECK([WUEmoticonRead(file) isEqual:gif]); CHECK(!WUEmoticonRead(dir)); CHECK(!WUEmoticonRead(@"relative")); CHECK(!WUEmoticonRead([dir stringByAppendingPathComponent:@"absent"]));
    NSString *link=[dir stringByAppendingPathComponent:@"link"]; CHECK(symlink(file.fileSystemRepresentation,link.fileSystemRepresentation)==0); CHECK(!WUEmoticonRead(link));
    Transaction(gif,NO,NO,NO,NO); Transaction(gif,YES,YES,NO,NO); Transaction(gif,YES,NO,NO,NO); Transaction(gif,YES,YES,YES,NO); Transaction(gif,YES,YES,NO,YES);
    __block int calls=0; WUEmoticonSave *bad=[WUEmoticonSave new];
    [bad startData:[NSData data] current:^BOOL{ return YES; } permission:^(void (^reply)(BOOL)){ calls+=100; } writer:^(NSData *d,NSString *u,void (^reply)(BOOL)){ calls+=100; } completion:^(NSString *r){ CHECK([r isEqual:@"invalid"]); calls++; }]; CHECK(calls==1);
    WUEmoticonSave *cancel=[WUEmoticonSave new];
    [cancel startData:gif current:^BOOL{ return NO; } permission:^(void (^reply)(BOOL)){ calls+=100; } writer:^(NSData *d,NSString *u,void (^reply)(BOOL)){ calls+=100; } completion:^(NSString *r){ CHECK([r isEqual:@"cancelled"]); calls++; }]; CHECK(calls==2);
    CHECK([NSData.data writeToFile:file atomically:YES]); CHECK(!WUEmoticonRead(file));
    CHECK([NSFileManager.defaultManager removeItemAtPath:dir error:NULL]);
    printf("Emoticon production format/transaction mock: %d assertions; no Photos writes\n",checks);
} return 0; }
