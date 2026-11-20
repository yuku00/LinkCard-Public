#import <Foundation/Foundation.h>
#include <assert.h>
#include "../Sources/VoiceArchive.inc"
static void p16(NSMutableData *d,uint16_t x){uint8_t b[]={x&255,x>>8};[d appendBytes:b length:2];}
static void p32(NSMutableData *d,uint32_t x){p16(d,x&65535);p16(d,x>>16);}
static NSData *zip(NSArray *names,NSArray *contents) {
    NSMutableData *body=[NSMutableData data],*central=[NSMutableData data];
    for(NSUInteger i=0;i<names.count;i++) {
        NSData *name=names[i],*data=contents[i]; uint32_t offset=(uint32_t)body.length, crc=(uint32_t)crc32(0,data.bytes,(uInt)data.length);
        p32(body,0x04034b50); p16(body,20); p16(body,0); p16(body,0); p16(body,0); p16(body,0); p32(body,crc); p32(body,(uint32_t)data.length); p32(body,(uint32_t)data.length); p16(body,(uint16_t)name.length); p16(body,0); [body appendData:name]; [body appendData:data];
        p32(central,0x02014b50);p16(central,20);p16(central,20);p16(central,0);p16(central,0);p16(central,0);p16(central,0);p32(central,crc);p32(central,(uint32_t)data.length);p32(central,(uint32_t)data.length);p16(central,(uint16_t)name.length);p16(central,0);p16(central,0);p16(central,0);p16(central,0);p32(central,0);p32(central,offset);[central appendData:name];
    }
    uint32_t offset=(uint32_t)body.length; [body appendData:central]; p32(body,0x06054b50);p16(body,0);p16(body,0);p16(body,(uint16_t)names.count);p16(body,(uint16_t)names.count);p32(body,(uint32_t)central.length);p32(body,offset);p16(body,0);return body;
}
static NSData *text(NSString *s){return [s dataUsingEncoding:NSUTF8StringEncoding];}
int main(void){@autoreleasepool {
    NSData *empty=[NSData data],*a=text(@"abc"),*b=text(@"def"); NSError *error=nil;
    NSDictionary *files=WUReadVoiceZIP(zip(@[text(@"./"),text(@"./__MACOSX/"),text(@"./音频/"),text(@"./音频/a.wav"),text(@"./音频/a.wav")],@[empty,empty,empty,a,a]),&error);
    assert(files.count==1 && [files[@"音频/a.wav"] isEqual:a]);
    assert(!WUReadVoiceZIP(zip(@[text(@"./a"),text(@"a")],@[a,b]),NULL));
    for(NSString *path in @[@"../evil.wav",@"./../evil.wav",@"/evil.wav",@"x/../../evil.wav",@"x\\evil.wav",@"C:evil.wav"]) assert(!WUReadVoiceZIP(zip(@[text(path)],@[a]),NULL));
    assert(!WUReadVoiceZIP(zip(@[text(@"a"),text(@"a/b.wav")],@[a,b]),NULL));
    const uint8_t gb[]={0xd3,0xef,0xd2,0xf4,'.','w','a','v'}; NSData *gbname=[NSData dataWithBytes:gb length:sizeof(gb)];
    assert(WUReadVoiceZIP(zip(@[gbname],@[a]),NULL).count==1);
    NSMutableData *corrupt=[zip(@[text(@"a.wav")],@[a]) mutableCopy]; ((uint8_t *)corrupt.mutableBytes)[35]^=1; assert(!WUReadVoiceZIP(corrupt,NULL));
    __block NSUInteger calls=0;
    NSDictionary *nested=WUReadVoiceZIPWithProgress(zip(@[text(@"a/b/one.wav"),text(@"a/c/two.wav")],@[a,b]),NULL,^BOOL(NSUInteger done,NSUInteger total) { assert(done==calls && total==2); calls++; return YES; });
    assert(calls==2 && [nested[@"a/b/one.wav"] isEqual:a] && [nested[@"a/c/two.wav"] isEqual:b]);
    calls=0; assert(!WUReadVoiceZIPWithProgress(zip(@[text(@"one.wav"),text(@"two.wav")],@[a,b]),NULL,^BOOL(NSUInteger done,NSUInteger total) { calls++; return done==0; })); assert(calls==2);
    puts("voice ZIP synthetic path, duplicate, encoding, and CRC tests passed");
}return 0;}
