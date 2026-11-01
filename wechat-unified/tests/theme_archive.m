#import <Foundation/Foundation.h>
#import "ThemeArchive.h"
#import <zlib.h>
#include <assert.h>
static void W16(NSMutableData *d,NSUInteger p,uint16_t n) { uint8_t *b=d.mutableBytes; b[p]=n; b[p+1]=n>>8; }
static void W32(NSMutableData *d,NSUInteger p,uint32_t n) { W16(d,p,n); W16(d,p+2,n>>16); }
static NSMutableData *Zip(NSString *name,BOOL deflated) {
    NSData *path=[name dataUsingEncoding:NSUTF8StringEncoding],*plain=[@"owned test data" dataUsingEncoding:NSUTF8StringEncoding]; NSData *payload=plain;
    if(deflated) { NSMutableData *out=[NSMutableData dataWithLength:128]; z_stream z={0}; assert(deflateInit2(&z,6,Z_DEFLATED,-MAX_WBITS,8,Z_DEFAULT_STRATEGY)==Z_OK); z.next_in=(Bytef *)plain.bytes; z.avail_in=(uInt)plain.length; z.next_out=out.mutableBytes; z.avail_out=(uInt)out.length; assert(deflate(&z,Z_FINISH)==Z_STREAM_END); out.length=z.total_out; deflateEnd(&z); payload=out; }
    NSUInteger c=30+path.length+payload.length,e=c+46+path.length; NSMutableData *d=[NSMutableData dataWithLength:e+22];
    uint32_t crc=(uint32_t)crc32(0,plain.bytes,(uInt)plain.length);
    W32(d,0,0x04034b50); W16(d,4,20); W16(d,8,deflated?8:0); W32(d,14,crc); W32(d,18,(uint32_t)payload.length); W32(d,22,(uint32_t)plain.length); W16(d,26,(uint16_t)path.length);
    [d replaceBytesInRange:NSMakeRange(30,path.length) withBytes:path.bytes]; [d replaceBytesInRange:NSMakeRange(30+path.length,payload.length) withBytes:payload.bytes];
    W32(d,c,0x02014b50); W16(d,c+4,0x0314); W16(d,c+6,20); W16(d,c+10,deflated?8:0); W32(d,c+16,crc); W32(d,c+20,(uint32_t)payload.length); W32(d,c+24,(uint32_t)plain.length); W16(d,c+28,(uint16_t)path.length); W32(d,c+38,0100644u<<16);
    [d replaceBytesInRange:NSMakeRange(c+46,path.length) withBytes:path.bytes]; W32(d,e,0x06054b50); W16(d,e+8,1); W16(d,e+10,1); W32(d,e+12,(uint32_t)(e-c)); W32(d,e+16,(uint32_t)c); return d;
}
static void Bad(NSData *d) { NSError *e=nil; assert(WUReadThemeZIP(d,&e)==nil); assert(e!=nil); }
int main(void) { @autoreleasepool {
    assert([WUThemeKey(@"folder/ChatRoom_Bubble_Text_Sender@3x.PNG") isEqual:@"chatroom_bubble_text_sender"]);
    assert(WUThemeBubble(@"chatroom_bubble_text_sender@2x.png")); assert(WUThemeBubble(@"text_bubble_receiver_dark.png")); assert(!WUThemeBubble(@"cover.png"));
    for(NSNumber *mode in @[@NO,@YES]) { NSData *d=Zip(@"合法/cover.png",mode.boolValue); NSDictionary *files=WUReadThemeZIP(d,NULL); assert(files.count==1); assert([files[@"合法/cover.png"] isEqual:[@"owned test data" dataUsingEncoding:NSUTF8StringEncoding]]); }
    for(NSString *name in @[@"../a.png",@"a/../../b.png",@"/a.png",@"C:/a.png",@"a\\b.png",@"a//b.png",@"./a.png",@"a/../b.png",@"a\nb.png"]) Bad(Zip(name,NO));
    NSMutableData *d=Zip(@"a.png",NO); NSUInteger e=d.length-22,c=e-51;
    NSMutableData *m=[d mutableCopy]; W32(m,c+38,0120777u<<16); Bad(m);
    m=[d mutableCopy]; W16(m,c+8,1); Bad(m);
    m=[d mutableCopy]; W32(m,c+24,9*1024*1024); Bad(m);
    m=[d mutableCopy]; W16(m,c+10,99); Bad(m);
    m=[d mutableCopy]; W32(m,c+42,UINT32_MAX); Bad(m);
    m=[d mutableCopy]; W32(m,c+16,0); Bad(m);
    m=[d mutableCopy]; W16(m,e+10,513); Bad(m);
    m=[d mutableCopy]; W16(m,e+4,1); Bad(m);
    m=[d mutableCopy]; W32(m,e+16,UINT32_MAX); Bad(m);
    m=[d mutableCopy]; ((uint8_t *)m.mutableBytes)[30]='b'; Bad(m);
    for(NSUInteger n=0;n<d.length;n++) Bad([d subdataWithRange:NSMakeRange(0,n)]);
    m=Zip(@"a.png",YES); ((uint8_t *)m.mutableBytes)[35]^=0xff; Bad(m);
    puts("Theme ZIP native tests passed: stored/deflate, UTF-8, paths, symlink, CRC, bounds, truncation, name/size limits");
} return 0; }
