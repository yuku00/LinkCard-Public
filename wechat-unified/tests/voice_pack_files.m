#import <Foundation/Foundation.h>
#import "VoicePackLogic.h"
#import "VoiceSendLogic.h"
#import "DraftMediaLogic.h"
#include <unistd.h>
static NSUInteger checks;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { NSLog(@"FAIL line %d",__LINE__); abort(); } } while(0)
static NSData *Fixture(void) {
    NSString *s=[NSString stringWithContentsOfFile:@"tests/fixtures/synthetic.amr.hex" encoding:NSUTF8StringEncoding error:NULL];
    NSString *h=[[s componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""]; NSMutableData *d=[NSMutableData data];
    for(NSUInteger i=0;i<h.length;i+=2) { unsigned n=0; CHECK([[NSScanner scannerWithString:[h substringWithRange:NSMakeRange(i,2)]] scanHexInt:&n]); unsigned char b=n; [d appendBytes:&b length:1]; } return d;
}
@interface FileWrap : NSObject
@property(nonatomic) unsigned int m_uiMessageType,m_uiVoiceFormat,m_uiVoiceTime,m_uiVoiceEndFlag,m_uiCreateTime;
@property(nonatomic,copy) NSData *m_dtVoice;
@property(nonatomic,copy) NSString *m_nsContent,*m_nsFromUsr,*m_nsToUsr;
- (instancetype)initWithMsgType:(unsigned int)n nsFromUsr:(NSString *)a;
@end
@implementation FileWrap
- (instancetype)initWithMsgType:(unsigned int)n nsFromUsr:(NSString *)a { if((self=[super init])) { _m_uiMessageType=n; _m_nsFromUsr=[a copy]; } return self; }
@end
@interface FileHost : NSObject
@property(nonatomic) NSUInteger inserts,sends;
@end
@implementation FileHost
- (void)AddLocalMsg:(id)target MsgWrap:(id)wrap { self.inserts++; }
- (void)ResendVoiceMsg:(id)target MsgWrap:(id)wrap { self.sends++; }
@end
int main(void) { @autoreleasepool {
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES].URLByResolvingSymlinksInPath;
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSURL *raw=[root URLByAppendingPathComponent:@"synthetic.amr"], *package=[root URLByAppendingPathComponent:@"export.wuvoice"];
    NSData *amr=Fixture(); CHECK([amr writeToURL:raw atomically:YES]); BOOL (^yes)(void)=^BOOL{ return YES; };
    WUVoicePackStore *store=[[WUVoicePackStore alloc] initWithRoot:[root URLByAppendingPathComponent:@"packs"] account:@"a"];
    CHECK([store importFile:raw name:@"raw" current:yes error:NULL]); NSDictionary *row=[store load:NULL][0];
    CHECK([row[@"format"] isEqual:@(-1)] && [row[@"pairing"] isEqual:@0]); CHECK(!WUVoicePackMatches(row,@"8.0.70/1"));
    CHECK([row[@"ms"] isEqual:@1000]); CHECK([[store acquire:row[@"id"] error:NULL][@"data"] isEqual:amr]); [store releaseResource:row[@"id"]];
    NSData *exported=[store exportResource:row[@"id"] error:NULL]; CHECK(exported!=nil);
    NSMutableDictionary *envelope=[[NSPropertyListSerialization propertyListWithData:exported options:NSPropertyListMutableContainers format:NULL error:NULL] mutableCopy];
    envelope[@"origin"]=@{@"format":@4,@"version":@"8.0.70/1",@"source":@"selected-type34"};
    NSData *forged=[NSPropertyListSerialization dataWithPropertyList:envelope format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL]; CHECK([forged writeToURL:package atomically:YES]);
    CHECK([store importFile:package name:@"roundtrip" current:yes error:NULL]); NSDictionary *imported=[store load:NULL][0];
    CHECK([imported[@"data"] isEqual:amr]); CHECK(!WUVoicePackMatches(imported,@"8.0.70/1")); CHECK([imported[@"format"] isEqual:@(-1)]);
    FileWrap *selected=[[FileWrap alloc] initWithMsgType:34 nsFromUsr:@"a"]; selected.m_dtVoice=amr; selected.m_uiVoiceFormat=4;
    CHECK(![store pair:imported[@"id"] selectedData:[amr subdataWithRange:NSMakeRange(0,12)] format:@4 version:@"8.0.70/1" current:yes error:NULL]);
    CHECK(![store pair:imported[@"id"] selectedData:WUVoiceSelectedData(selected) format:@3 version:@"8.0.70/1" current:yes error:NULL]);
    CHECK([store pair:imported[@"id"] selectedData:WUVoiceSelectedData(selected) format:@(selected.m_uiVoiceFormat) version:@"8.0.70/1" current:yes error:NULL]);
    NSDictionary *held=[store acquire:imported[@"id"] error:NULL]; CHECK(WUVoicePackMatches(held,@"8.0.70/1")); CHECK(!WUVoicePackMatches(held,@"8.0.71/1"));
    CHECK(![store pair:imported[@"id"] selectedData:amr format:@4 version:@"8.0.70/1" current:yes error:NULL]);
    FileHost *host=[FileHost new]; WUVoiceForwardOperation *op=[[WUVoiceForwardOperation alloc] initWithData:held[@"data"] account:@"a" target:@"synthetic-recipient"];
    CHECK([[op submitWithManager:host audioSender:host messageClass:FileWrap.class current:yes] hasPrefix:@"已请求"]);
    [op submitWithManager:host audioSender:host messageClass:FileWrap.class current:yes]; CHECK(host.inserts==1 && host.sends==1); [store releaseResource:imported[@"id"]];
    NSUInteger count=[[store load:NULL] count]; CHECK(![store importFile:raw name:@"cancel" current:^BOOL{ return NO; } error:NULL]); CHECK([[store load:NULL] count]==count);
    WUVoicePackStore *other=[[WUVoicePackStore alloc] initWithRoot:[root URLByAppendingPathComponent:@"packs"] account:@"b"]; CHECK([[other load:NULL] count]==0);
    NSURL *link=[root URLByAppendingPathComponent:@"linked.amr"]; CHECK(symlink(raw.path.fileSystemRepresentation,link.path.fileSystemRepresentation)==0); CHECK(![store importFile:link name:@"link" current:yes error:NULL]);
    CHECK([[NSData dataWithContentsOfURL:raw] isEqual:amr]);
    NSURL *index=[root URLByAppendingPathComponent:@"packs/61/index.plist"]; CHECK([[@"bad" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:index atomically:YES]);
    CHECK(![store importFile:raw name:@"bad index" current:yes error:NULL]); CHECK(![store exportResource:imported[@"id"] error:NULL]);
    CHECK([NSFileManager.defaultManager removeItemAtURL:root error:NULL]);
    printf("Voice file import/export/trusted-pairing mock path: %lu checks passed\n",(unsigned long)checks);
} return 0; }
