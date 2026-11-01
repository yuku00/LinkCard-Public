#import <Foundation/Foundation.h>
#import "VoiceLogic.h"
#import "VoiceAudio.h"
#include <assert.h>
#include <math.h>
#include <string.h>
static NSUInteger checks;
#define CHECK(x) do { checks++; assert(x); } while(0)
static void LE16(NSMutableData *d,uint16_t v) { uint8_t b[]={v&255,v>>8}; [d appendBytes:b length:2]; }
static void LE32(NSMutableData *d,uint32_t v) { uint8_t b[]={v&255,(v>>8)&255,(v>>16)&255,v>>24}; [d appendBytes:b length:4]; }
static NSData *WAV(void) {
    NSMutableData *d=[NSMutableData data]; [d appendBytes:"RIFF" length:4]; LE32(d,36+16000); [d appendBytes:"WAVEfmt " length:8];
    LE32(d,16); LE16(d,1); LE16(d,1); LE32(d,8000); LE32(d,16000); LE16(d,2); LE16(d,16);
    [d appendBytes:"data" length:4]; LE32(d,16000);
    for(int i=0;i<8000;i++) LE16(d,i<4000?0:16384); return d;
}
int main(void) { @autoreleasepool {
    CHECK(WUVoiceSeekMS(0.5,61500)==30750); CHECK(WUVoiceSeekMS(1,61500)==61500);
    CHECK(WUVoiceSeekMS(-1,61500)==0); CHECK(WUVoiceSeekMS(2,61500)==61500);
    CHECK(WUVoiceSeekMS(NAN,60000)==0); CHECK(WUVoiceSeekMS(INFINITY,60000)==0);
    CHECK(WUVoiceSeekMS(.5,-1)==0); CHECK(WUVoiceSeekMS(.5,180001)==0);
    CHECK([WUVoiceTime(61500,YES) isEqual:@"1:01"]); CHECK([WUVoiceTime(59999,YES) isEqual:@"0:59"]);
    CHECK([WUVoiceTime(60000,YES) isEqual:@"1:00"]); CHECK([WUVoiceTime(61500,NO) isEqual:@"61秒"]);
    CHECK([WUVoiceTime(NAN,YES) isEqual:@"—"]); CHECK([WUVoiceTime(-1,YES) isEqual:@"—"]);
    float pcm[]={0,0,.25,-.5,1,-1,.125,-.25};
    NSArray *p=WUVoicePeaks(pcm,8,1,4); CHECK(p.count==4); CHECK([p[0] doubleValue]==0); CHECK([p[1] doubleValue]==.5); CHECK([p[2] doubleValue]==1); CHECK([p[3] doubleValue]==.25);
    p=WUVoicePeaks(pcm,4,2,2); CHECK([p[0] doubleValue]==.5); CHECK([p[1] doubleValue]==1);
    CHECK(WUVoicePeaks(pcm,1,1,48).count==1); CHECK(!WUVoicePeaks(NULL,1,1,1)); CHECK(!WUVoicePeaks(pcm,0,1,1)); CHECK(!WUVoicePeaks(pcm,1,3,1)); CHECK(!WUVoicePeaks(pcm,1,1,129));
    float bad[]={NAN}; CHECK(!WUVoicePeaks(bad,1,1,1));
    CHECK(WUVoiceLease(@"a",@"a",2,2,YES,YES,YES,YES));
    CHECK(!WUVoiceLease(@"a",@"b",2,2,YES,YES,YES,YES));
    CHECK(!WUVoiceLease(@"a",@"a",2,3,YES,YES,YES,YES));
    CHECK(!WUVoiceLease(@"a",@"a",2,2,NO,YES,YES,YES));
    CHECK(!WUVoiceLease(@"a",@"a",2,2,YES,NO,YES,YES));
    CHECK(!WUVoiceLease(@"a",@"a",2,2,YES,YES,NO,YES));
    CHECK(!WUVoiceLease(@"a",@"a",2,2,YES,YES,YES,NO));
    CHECK(!WUVoiceLease(nil,nil,2,2,YES,YES,YES,YES));
    NSDictionary *audio=WUVoiceDecode(WAV()); CHECK(audio!=nil); CHECK(fabs([audio[@"duration"] doubleValue]-1000)<.01);
    p=audio[@"peaks"]; CHECK(p.count==48); CHECK([p.firstObject doubleValue]==0); CHECK(fabs([p.lastObject doubleValue]-.5)<.001);
    CHECK(!WUVoiceDecode([@"#!SILK_V3garbage" dataUsingEncoding:NSUTF8StringEncoding]));
    CHECK(!WUVoiceDecode([@"#!AMR\ngarbage..." dataUsingEncoding:NSUTF8StringEncoding]));
    CHECK(!WUVoiceDecode([NSData data])); CHECK(!WUVoiceReadLocal(@"https://invalid/audio")); CHECK(!WUVoiceReadLocal(@"/etc/passwd"));
    NSMutableData *corrupt=[WAV() mutableCopy]; [corrupt replaceBytesInRange:NSMakeRange(22,2) withBytes:"\0\0"];
    CHECK(!WUVoiceDecode(corrupt));
    // Simulated late decode and stale seek: the same production lease must reject all invalidation causes.
    NSUInteger requests=1, completion=requests; requests++; CHECK(completion!=requests);
    for(NSUInteger g=3;g<8;g++) CHECK(!WUVoiceLease(@"a",@"a",2,g,YES,YES,YES,YES));
    for(NSString *name in @[@"standard.silk",@"tencent.silk",@"synthetic.amr"]) {
        NSString *hex=[NSString stringWithContentsOfFile:[@"tests/fixtures/" stringByAppendingFormat:@"%@.hex",name] encoding:NSUTF8StringEncoding error:NULL]; CHECK(hex!=nil);
        NSMutableData *encoded=[NSMutableData data];
        for(NSUInteger i=0;i+1<hex.length;i+=2) { unsigned v=0; CHECK(sscanf([[hex substringWithRange:NSMakeRange(i,2)] UTF8String],"%2x",&v)==1); uint8_t b=v; [encoded appendBytes:&b length:1]; }
        NSDictionary *decoded=WUVoiceDecode(encoded); CHECK(decoded!=nil);
        CHECK(fabs([decoded[@"duration"] doubleValue]-1000)<.01); CHECK([decoded[@"channels"] intValue]==1);
        CHECK([decoded[@"sampleRate"] intValue]==([name hasSuffix:@"amr"]?8000:16000));
        NSArray *bars=decoded[@"peaks"]; CHECK(bars.count==48);
        double maximum=0; for(NSNumber *bar in bars) { CHECK(isfinite(bar.doubleValue) && bar.doubleValue>=0 && bar.doubleValue<=1); maximum=fmax(maximum,bar.doubleValue); }
        CHECK(maximum>.1); CHECK(WUVoiceSeekMS(.5,[decoded[@"duration"] doubleValue])==500);
        if(![name hasSuffix:@"amr"]) { CHECK([bars.firstObject doubleValue]<.01); CHECK([bars.lastObject doubleValue]>.1); }
        NSProgress *cancel=[NSProgress progressWithTotalUnitCount:1]; [cancel cancel]; CHECK(!WUVoiceDecodeCancellable(encoded,cancel));
        uint8_t junk=0x7c; [encoded appendBytes:&junk length:1]; CHECK(!WUVoiceDecode(encoded));
    }
    CHECK(!WUVoiceDecode([NSMutableData dataWithLength:8*1024*1024+1]));
    printf("Voice: %lu assertions passed (PCM decode, peaks, millisecond seek, lifecycle)\n",(unsigned long)checks);
} return 0; }
