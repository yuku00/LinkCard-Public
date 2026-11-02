#import <Foundation/Foundation.h>
#import "VoicePackLogic.h"
#import "VoiceSendLogic.h"
#import "VoiceAudio.h"
#include <sys/stat.h>
#include <unistd.h>
static NSUInteger checks;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { NSLog(@"FAIL line %d",__LINE__); abort(); } } while(0)
static NSData *Fixture(void) {
    NSString *text=[NSString stringWithContentsOfFile:@"tests/fixtures/synthetic.amr.hex" encoding:NSUTF8StringEncoding error:NULL];
    NSString *hex=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
    NSMutableData *data=[NSMutableData data];
    for(NSUInteger i=0;i<hex.length;i+=2) { unsigned n=0; CHECK([[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i,2)]] scanHexInt:&n]); unsigned char b=n; [data appendBytes:&b length:1]; }
    return data;
}
@interface PackWrap : NSObject
@property(nonatomic) unsigned int m_uiMessageType, m_uiVoiceFormat, m_uiVoiceTime, m_uiVoiceEndFlag, m_uiCreateTime;
@property(nonatomic,copy) NSData *m_dtVoice;
@property(nonatomic,copy) NSString *m_nsContent, *m_nsFromUsr, *m_nsToUsr;
- (instancetype)initWithMsgType:(unsigned int)n nsFromUsr:(NSString *)a;
@end
@implementation PackWrap
- (instancetype)initWithMsgType:(unsigned int)n nsFromUsr:(NSString *)a { if((self=[super init])) { _m_uiMessageType=n; _m_nsFromUsr=[a copy]; } return self; }
@end
@interface PackHost : NSObject
@property(nonatomic) NSUInteger inserts,sends;
@property(nonatomic,strong) PackWrap *last;
- (void)AddLocalMsg:(id)target MsgWrap:(id)wrap;
- (void)ResendVoiceMsg:(id)target MsgWrap:(id)wrap;
@end
@implementation PackHost
- (void)AddLocalMsg:(id)target MsgWrap:(id)wrap { self.inserts++; self.last=wrap; }
- (void)ResendVoiceMsg:(id)target MsgWrap:(id)wrap { self.sends++; CHECK(wrap==self.last); }
@end
int main(void) { @autoreleasepool {
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES].URLByResolvingSymlinksInPath;
    WUVoicePackStore *store=[[WUVoicePackStore alloc] initWithRoot:root account:@"a"], *other=[[WUVoicePackStore alloc] initWithRoot:root account:@"b"];
    CHECK(store && other); CHECK([[store load:NULL] count]==0);
    BOOL (^yes)(void)=^BOOL{ return YES; }; NSData *amr=Fixture();
    CHECK(![store saveData:amr format:@0 version:@"8.0.70/1" name:@"a" current:yes error:NULL]);
    CHECK(![store saveData:amr format:nil version:@"8.0.70/1" name:@"a" current:yes error:NULL]);
    CHECK(![store saveData:amr format:@4 version:@"" name:@"a" current:yes error:NULL]);
    CHECK(![store saveData:amr format:@4 version:@"8.0.70/1" name:@"" current:yes error:NULL]);
    CHECK(![store saveData:[NSData data] format:@4 version:@"8.0.70/1" name:@"a" current:yes error:NULL]);
    CHECK(![store saveData:[amr subdataWithRange:NSMakeRange(0,12)] format:@4 version:@"8.0.70/1" name:@"a" current:yes error:NULL]);
    NSMutableData *longVoice=[NSMutableData dataWithBytes:"#!AMR\n" length:6]; for(int i=0;i<61;i++) [longVoice appendData:[amr subdataWithRange:NSMakeRange(6,amr.length-6)]];
    CHECK(![store saveData:longVoice format:@4 version:@"8.0.70/1" name:@"a" current:yes error:NULL]);
    PackWrap *source=[[PackWrap alloc] initWithMsgType:34 nsFromUsr:@"origin"]; source.m_uiVoiceFormat=4; source.m_dtVoice=amr;
    NSData *selected=WUVoiceSelectedData(source); CHECK([selected isEqual:amr]);
    CHECK([store saveData:selected format:@(source.m_uiVoiceFormat) version:@"8.0.70/1" name:@"一条语音" current:yes error:NULL]);
    NSArray *rows=[store load:NULL]; CHECK(rows.count==1); NSDictionary *row=rows.firstObject; NSString *identifier=row[@"id"];
    CHECK([row[@"data"] isEqual:amr] && [row[@"format"] isEqual:@4] && [row[@"ms"] isEqual:@1000]);
    CHECK([row[@"source"] isEqual:@"selected-type34"]); CHECK([[other load:NULL] count]==0);
    CHECK(WUVoicePackMatches(row,@"8.0.70/1")); CHECK(!WUVoicePackMatches(row,@"8.0.71/1")); CHECK(!WUVoicePackMatches(row,@"8.0.70/2"));
    NSMutableDictionary *bad=[row mutableCopy]; bad[@"source"]=@"import"; CHECK(!WUVoicePackMatches(bad,@"8.0.70/1")); bad=[row mutableCopy]; [bad removeObjectForKey:@"format"]; CHECK(!WUVoicePackMatches(bad,@"8.0.70/1"));
    WUVoicePackStore *reopened=[[WUVoicePackStore alloc] initWithRoot:root account:@"a"]; CHECK([[[reopened load:NULL] firstObject][@"id"] isEqual:identifier]);
    CHECK([store rename:identifier name:@"新名称" current:yes error:NULL]); CHECK([[[store load:NULL] firstObject][@"id"] isEqual:identifier]);
    NSDictionary *held=[store acquire:identifier error:NULL]; CHECK(held!=nil); CHECK([reopened acquire:identifier error:NULL]!=nil);
    CHECK(![store remove:identifier current:yes error:NULL]); [store releaseResource:identifier]; CHECK(![store remove:identifier current:yes error:NULL]); [reopened releaseResource:identifier];
    NSURL *index=[[root URLByAppendingPathComponent:@"61"] URLByAppendingPathComponent:@"index.plist"]; NSData *before=[NSData dataWithContentsOfURL:index];
    __block NSUInteger calls=0;
    CHECK(![store rename:identifier name:@"取消的更新" current:^BOOL{ return ++calls<2; } error:NULL]); CHECK(calls==2); CHECK([[NSData dataWithContentsOfURL:index] isEqual:before]);
    CHECK(![store saveData:amr format:@4 version:@"8.0.70/1" name:@"切号" current:^BOOL{ return NO; } error:NULL]); CHECK([[NSData dataWithContentsOfURL:index] isEqual:before]);
    // Force a real atomic rename failure after copy verification without altering the old index.
    calls=0; NSString *directory=index.URLByDeletingLastPathComponent.path;
    CHECK(![store rename:identifier name:@"失败提交" current:^BOOL{ if(++calls==2) { CHECK(chmod(directory.fileSystemRepresentation,0500)==0); } return YES; } error:NULL]);
    CHECK(chmod(directory.fileSystemRepresentation,0700)==0); CHECK([[NSData dataWithContentsOfURL:index] isEqual:before]);
    held=[store acquire:identifier error:NULL]; CHECK(held!=nil); PackHost *host=[PackHost new];
    WUVoiceForwardOperation *operation=[[WUVoiceForwardOperation alloc] initWithData:held[@"data"] account:@"a" target:@"recipient"];
    CHECK([[operation submitWithManager:host audioSender:host messageClass:PackWrap.class current:yes] hasPrefix:@"已请求"]);
    [operation submitWithManager:host audioSender:host messageClass:PackWrap.class current:yes]; CHECK(host.inserts==1 && host.sends==1);
    CHECK([host.last.m_dtVoice isEqual:amr] && host.last.m_uiVoiceFormat==4 && host.last.m_uiVoiceTime==1000);
    CHECK(![store remove:identifier current:yes error:NULL]); [store releaseResource:identifier];
    CHECK(![other acquire:identifier error:NULL]); CHECK([store remove:identifier current:yes error:NULL]); CHECK([[store load:NULL] count]==0);
    CHECK([source.m_dtVoice isEqual:amr]);
    // Locally generated 1 second, 16 kHz, mono PCM WAV; no real user media.
    NSMutableData *wav=[NSMutableData dataWithLength:44+32000]; uint8_t *w=wav.mutableBytes;
    memcpy(w,"RIFF",4); uint32_t n=32036; memcpy(w+4,&n,4); memcpy(w+8,"WAVEfmt ",8); n=16; memcpy(w+16,&n,4);
    uint16_t v=1; memcpy(w+20,&v,2); memcpy(w+22,&v,2); n=16000; memcpy(w+24,&n,4); n=32000; memcpy(w+28,&n,4); v=2; memcpy(w+32,&v,2); v=16; memcpy(w+34,&v,2); memcpy(w+36,"data",4); memcpy(w+40,&n,4);
    int16_t *samples=(int16_t *)(w+44); for(int i=0;i<16000;i++) samples[i]=(int16_t)(((i%80)-40)*400);
    NSData *silk=WUVoiceTranscodeSilk(wav,yes); CHECK(silk && WUVoiceMeasuredMS(silk)==1000); CHECK(!WUVoiceTranscodeSilk(wav,^BOOL{ return NO; }));
    NSURL *wavURL=[root URLByAppendingPathComponent:@"synthetic.wav"]; CHECK([wav writeToURL:wavURL atomically:YES]);
    // afconvert runs only in this macOS test, converting our generated waveform.
    NSURL *m4aURL=[root URLByAppendingPathComponent:@"synthetic.m4a"];
    NSTask *convert=[NSTask new]; convert.executableURL=[NSURL fileURLWithPath:@"/usr/bin/afconvert"];
    convert.arguments=@[@"-f",@"m4af",@"-d",@"aac",wavURL.path,m4aURL.path];
    NSError *convertError=nil; CHECK([convert launchAndReturnError:&convertError]); [convert waitUntilExit]; CHECK(convert.terminationStatus==0);
    NSData *m4a=[NSData dataWithContentsOfURL:m4aURL]; CHECK(m4a.length>0);
    NSData *m4aSilk=WUVoiceTranscodeSilk(m4a,yes); CHECK(m4aSilk && WUVoiceMeasuredMS(m4aSilk)>0);
    CHECK([store importFile:m4aURL name:@"synthetic m4a" current:yes error:NULL]);
    NSDictionary *importedM4A=[[store load:NULL] firstObject];
    CHECK([importedM4A[@"pairing"] isEqual:@0] && [importedM4A[@"format"] isEqual:@(-1)] && !WUVoicePackMatches(importedM4A,@"8.0.70/1"));
    CHECK([store remove:importedM4A[@"id"] current:yes error:NULL]);
    CHECK([store importFile:wavURL name:@"synthetic" current:yes error:NULL]); NSDictionary *imported=[[store load:NULL] firstObject];
    CHECK([imported[@"pairing"] isEqual:@0] && [imported[@"format"] isEqual:@(-1)] && !WUVoicePackMatches(imported,@"8.0.70/1"));
    CHECK([store acquire:imported[@"id"] error:NULL]!=nil); [store releaseResource:imported[@"id"]];
    CHECK(![store pair:imported[@"id"] selectedData:amr format:@4 version:@"8.0.70/1" current:yes error:NULL]);
    CHECK([store remove:imported[@"id"] current:yes error:NULL]);
    CHECK([@"bad index" writeToURL:index atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    CHECK(![store load:NULL]); CHECK(![store saveData:amr format:@4 version:@"8.0.70/1" name:@"a" current:yes error:NULL]); CHECK(![store remove:identifier current:yes error:NULL]);
    CHECK([NSFileManager.defaultManager removeItemAtURL:root error:NULL]);
    printf("Voice pack production storage/leases/pairing/single-submit: %lu assertions passed\n",(unsigned long)checks);
} return 0; }
