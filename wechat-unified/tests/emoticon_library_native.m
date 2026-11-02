#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import "EmoticonLibraryLogic.h"
#import "EmoticonLogic.h"
#import "EmoticonSubmission.h"
#include <unistd.h>
#include <string.h>
#include "emoticon_matches.inc"
static int checks, sends, factoryCalls, factoryMode;
static void (^duringFactory)(void), (^duringCopy)(void);
static BOOL badCopiedSignature;
static unsigned timeWrites;
#if defined(WU_EMOTICON_BAD_FACTORY)
typedef long long WUFactoryErrorParameter;
#else
typedef id __autoreleasing *WUFactoryErrorParameter;
#endif
#define CHECK(x) do { ++checks; if(!(x)) { fprintf(stderr,"FAILED %d: %s\n",__LINE__,#x); abort(); } } while(0)
@interface CMessageWrap : NSObject
@property(nonatomic) unsigned int m_uiMessageType, m_uiCreateTime, m_uiMesLocalID;
@property(nonatomic) unsigned long long m_n64MesSvrID;
@property(nonatomic,copy) NSString *m_nsFromUsr, *m_nsToUsr, *m_nsRealChatUsr, *m_nsEmoticonMD5;
@property(nonatomic,copy) NSData *bytes;
@property(nonatomic) unsigned signatureMode, storedTime;
- (instancetype)initWithMsgType:(unsigned int)type nsFromUsr:(NSString *)account;
- (void)copyToMsg:(CMessageWrap *)other;
@end
@implementation CMessageWrap
- (unsigned)m_uiCreateTime { return self.storedTime; }
- (void)setM_uiCreateTime:(unsigned)value { timeWrites++; self.storedTime=value; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    if(self.signatureMode==1 && selector==@selector(m_uiMessageType)) return [NSMethodSignature signatureWithObjCTypes:"Q@:"];
    if(self.signatureMode==2 && selector==@selector(setM_uiCreateTime:)) return [NSMethodSignature signatureWithObjCTypes:"v@:d"];
    return [super methodSignatureForSelector:selector];
}
- (instancetype)initWithMsgType:(unsigned int)type nsFromUsr:(NSString *)account { if((self=[super init])) { self.m_uiMessageType=type; self.m_nsFromUsr=account; } return self; }
- (void)copyToMsg:(CMessageWrap *)other {
    other.m_uiMessageType=self.m_uiMessageType; other.m_nsFromUsr=self.m_nsFromUsr; other.m_nsToUsr=self.m_nsToUsr; other.m_nsRealChatUsr=self.m_nsRealChatUsr; other.m_uiMesLocalID=self.m_uiMesLocalID; other.m_n64MesSvrID=self.m_n64MesSvrID; other.m_nsEmoticonMD5=self.m_nsEmoticonMD5; other.bytes=self.bytes;
    if(badCopiedSignature) other.signatureMode=2;
    if(duringCopy) duringCopy();
}
@end
@interface CEmoticonMgr : NSObject
+ (id)emoticonMsgForImageData:(NSData *)data errorMsg:(WUFactoryErrorParameter)error;
@end
@implementation CEmoticonMgr
+ (id)emoticonMsgForImageData:(NSData *)data errorMsg:(WUFactoryErrorParameter)error {
    factoryCalls++; if(duringFactory) duringFactory();
    if(factoryMode==1) return nil;
    if(factoryMode==2) @throw [NSException exceptionWithName:@"test" reason:nil userInfo:nil];
    CMessageWrap *m=[[CMessageWrap alloc] initWithMsgType:factoryMode==4?3:47 nsFromUsr:@"old"];
    m.m_nsToUsr=@"prior"; m.m_nsRealChatUsr=@"other"; m.m_uiMesLocalID=7; m.m_n64MesSvrID=9; m.bytes=data;
    m.m_nsEmoticonMD5=factoryMode==3?@"00000000000000000000000000000000":WUEmoticonDigest(data); return m;
}
@end
@interface MockManager : NSObject
@property(nonatomic,strong) CMessageWrap *last;
@property(nonatomic) BOOL throws;
- (void)AddEmoticonMsg:(NSString *)target MsgWrap:(CMessageWrap *)message;
@end
@implementation MockManager
- (void)AddEmoticonMsg:(NSString *)target MsgWrap:(CMessageWrap *)message {
    sends++; self.last=message; CHECK([target isEqual:message.m_nsToUsr]);
    if(self.throws) @throw [NSException exceptionWithName:@"uncertain" reason:nil userInfo:nil];
}
@end
@interface BadManager : NSObject
- (BOOL)AddEmoticonMsg:(NSString *)target MsgWrap:(id)message;
@end
@implementation BadManager
- (BOOL)AddEmoticonMsg:(NSString *)target MsgWrap:(id)message { abort(); }
@end
static NSData *Image(NSString *uti, NSUInteger count) {
    unsigned char pixel[]={255,0,0,255,0,255,0,255,0,0,255,255,255,255,255,255};
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB(); CGContextRef context=CGBitmapContextCreate(pixel,2,2,8,8,color,kCGImageAlphaPremultipliedLast);
    NSMutableData *data=[NSMutableData data]; CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,(__bridge CFStringRef)uti,count,NULL);
    for(NSUInteger i=0;i<count;i++) { if(i) { CGContextSetRGBFillColor(context,0,0,1,1); CGContextFillRect(context,CGRectMake(0,0,2,2)); } CGImageRef image=CGBitmapContextCreateImage(context); CGImageDestinationAddImage(destination,image,(__bridge CFDictionaryRef)@{(id)kCGImagePropertyGIFDictionary:@{(id)kCGImagePropertyGIFDelayTime:@0.1}}); CGImageRelease(image); }
    CHECK(CGImageDestinationFinalize(destination)); CFRelease(destination); CGContextRelease(context); CGColorSpaceRelease(color); return data;
}
#if !defined(WU_EMOTICON_BAD_FACTORY)
static void Submission(NSData *gif) {
    __block BOOL current=YES; BOOL (^valid)(void)=^BOOL{ return current; }; MockManager *manager=[MockManager new];
    NSString *result=WUSubmitEmoticonData(gif,manager,@"account-a",@"friend",valid); CHECK([result containsString:@"已请求"]); CHECK(sends==1 && factoryCalls==1);
    CHECK([manager.last.bytes isEqual:gif] && manager.last.m_uiMessageType==47); CHECK([manager.last.m_nsFromUsr isEqual:@"account-a"] && [manager.last.m_nsToUsr isEqual:@"friend"]); CHECK(manager.last.m_uiMesLocalID==0 && manager.last.m_n64MesSvrID==0 && !manager.last.m_nsRealChatUsr);
    current=NO; WUSubmitEmoticonData(gif,manager,@"account-a",@"friend",valid); CHECK(sends==1 && factoryCalls==1); current=YES;
    duringFactory=^{ current=NO; }; WUSubmitEmoticonData(gif,manager,@"account-a",@"friend",valid); CHECK(sends==1); duringFactory=nil; current=YES;
    duringCopy=^{ current=NO; }; WUSubmitEmoticonData(gif,manager,@"account-a",@"friend",valid); CHECK(sends==1); duringCopy=nil; current=YES;
    for(factoryMode=1;factoryMode<=4;factoryMode++) { WUSubmitEmoticonData(gif,manager,@"account-a",@"friend",valid); CHECK(sends==1); } factoryMode=0;
    WUSubmitEmoticonData([gif subdataWithRange:NSMakeRange(0,gif.length-1)],manager,@"account-a",@"friend",valid); CHECK(sends==1);
    WUSubmitEmoticonData(gif,[BadManager new],@"account-a",@"friend",valid); CHECK(sends==1);
    CMessageWrap *source=[CEmoticonMgr emoticonMsgForImageData:gif errorMsg:NULL];
    WUSubmitEmoticonCopy(source,manager,@"account-a",@"friend",valid); CHECK(sends==2 && source!=manager.last); CHECK(source.m_uiMesLocalID==7 && source.m_n64MesSvrID==9 && [source.m_nsToUsr isEqual:@"prior"]);
    unsigned beforeWrites=timeWrites;
    source.signatureMode=1; CHECK(!WUEmoticonSourceReady(source,manager));
    CHECK([WUSubmitEmoticonCopy(source,manager,@"account-a",@"friend",valid) containsString:@"未提交"] && sends==2);
    source.signatureMode=0; badCopiedSignature=YES;
    CHECK([WUSubmitEmoticonCopy(source,manager,@"account-a",@"friend",valid) containsString:@"未提交"] && sends==2 && timeWrites==beforeWrites);
    badCopiedSignature=NO;
    manager.throws=YES; result=WUSubmitEmoticonData(gif,manager,@"account-a",@"friend",valid); CHECK(sends==3 && [result containsString:@"未知"]);
}
#endif
int main(void) { @autoreleasepool {
#if defined(WU_EMOTICON_BAD_FACTORY)
    MockManager *manager=[MockManager new]; NSData *gif=Image(@"com.compuserve.gif",2);
    CHECK(!WUEmoticonDataAvailable(manager));
    CHECK([WUSubmitEmoticonData(gif,manager,@"account-a",@"friend",^BOOL{return YES;}) containsString:@"未提交"]);
    CHECK(!sends && !factoryCalls); puts("PASS: genuinely different factory ABI rejected without invocation");
#else
    NSData *gif=Image(@"com.compuserve.gif",2), *png=Image(@"public.png",1); CHECK([WUEmoticonType(gif) isEqual:@"com.compuserve.gif"]);
    NSURL *root=[[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByResolvingSymlinksInPath] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSURL *file=[root URLByAppendingPathComponent:@"synthetic-cache.data"]; CHECK([gif writeToURL:file options:0 error:NULL]);
    WUEmoticonLibraryStore *store=[[WUEmoticonLibraryStore alloc] initWithRoot:root account:@"a"], *other=[[WUEmoticonLibraryStore alloc] initWithRoot:root account:@"b"];
    CHECK(store && other); BOOL (^valid)(void)=^BOOL{ return YES; }; NSError *error=nil;
    CHECK([store load:&error] && !error); BOOL created=[store createGroup:@"第一组" current:valid error:&error]; if(!created) fprintf(stderr,"createGroup error: %s\n",error.description.UTF8String ?: "none"); CHECK(created); CHECK([store createGroup:@"第二组" current:valid error:&error]);
    NSDictionary *state=[store load:&error]; NSString *group=state[@"groups"][0][@"id"], *second=state[@"groups"][1][@"id"];
    NSDictionary *emptySelectionState=[store load:NULL];
    // Cancellation/selection loss at read, import, serialization and both atomic gates.
    for(int stop=1;stop<=5;stop++) {
        __block int gate=0;
        CHECK(![store importSelectedPath:file.path md5:WUEmoticonDigest(gif) GIFOnly:YES name:@"cancelled" group:group current:^BOOL{ return ++gate<stop; } error:&error]);
        CHECK(gate==stop && [[store load:NULL] isEqual:emptySelectionState]);
    }
    CHECK(![store importSelectedPath:file.path md5:@"00000000000000000000000000000000" GIFOnly:YES name:@"wrong digest" group:group current:valid error:&error]);
    CHECK([png writeToURL:file options:0 error:NULL]);
    CHECK(![store importSelectedPath:file.path md5:WUEmoticonDigest(png) GIFOnly:YES name:@"not GIF" group:group current:valid error:&error]);
    NSData *broken=[gif subdataWithRange:NSMakeRange(0,gif.length-1)]; CHECK([broken writeToURL:file options:0 error:NULL]);
    CHECK(![store importSelectedPath:file.path md5:WUEmoticonDigest(broken) GIFOnly:YES name:@"broken GIF" group:group current:valid error:&error]);
    CHECK([[store load:NULL] isEqual:emptySelectionState]);
    CHECK([gif writeToURL:file options:0 error:NULL]);
    CHECK([store importSelectedPath:file.path md5:WUEmoticonDigest(gif) GIFOnly:YES name:@"动画原件" group:group current:valid error:&error]);
    CHECK([WUEmoticonRead(file.path) isEqual:gif] && sends==0 && factoryCalls==0);
    CHECK(![store importSelectedPath:file.path md5:WUEmoticonDigest(gif) GIFOnly:YES name:@"重复确认" group:group current:valid error:&error]);
    CHECK(![store importFile:file name:@"重复文件" group:group current:valid error:&error]);
    NSDictionary *selectedRow=[store load:NULL][@"rows"][0];
    CHECK([selectedRow[@"data"] isEqual:gif] && [selectedRow[@"uti"] isEqual:@"com.compuserve.gif"]);
    WUEmoticonLibraryStore *selectedReopen=[[WUEmoticonLibraryStore alloc] initWithRoot:root account:@"a"];
    CHECK([[selectedReopen resource:selectedRow[@"id"] error:NULL][@"data"] isEqual:gif]);
    CHECK([[other load:NULL][@"rows"] count]==0);
    CHECK([store remove:selectedRow[@"id"] group:NO current:valid error:&error]);
    CHECK([store importFile:file name:@"动画原件" group:group current:valid error:&error]); CHECK([WUEmoticonRead(file.path) isEqual:gif]);
    state=[store load:&error]; NSDictionary *row=state[@"rows"][0]; NSString *identifier=row[@"id"];
    CHECK([row[@"data"] isEqual:gif]); CGImageSourceRef image=CGImageSourceCreateWithData((__bridge CFDataRef)row[@"data"],NULL); CHECK(CGImageSourceGetCount(image)==2); CFRelease(image);
    CHECK([other load:&error][@"rows"] && [[other load:&error][@"rows"] count]==0);
    CHECK(![store importData:gif name:@"duplicate" group:@"" current:valid error:&error]);
    CHECK([store importData:png name:@"静图" group:@"" current:valid error:&error]);
    CHECK([store rename:identifier group:NO name:@"新名称" current:valid error:&error]);
    CHECK([store rename:group group:YES name:@"改组名" current:valid error:&error]);
    CHECK([store move:group group:YES to:1 current:valid error:&error]); CHECK([store move:identifier group:NO to:1 current:valid error:&error]);
    state=[store load:&error]; CHECK([state[@"rows"][1][@"id"] isEqual:identifier] && [state[@"groups"][1][@"id"] isEqual:group]);
    CHECK(WUEmoticonLibraryRows(state,group).count==1 && WUEmoticonLibraryRows(state,@"").count==1);
    CHECK([store assign:identifier group:second current:valid error:&error]);
    CHECK([store remove:second group:YES current:valid error:&error]); state=[store load:&error]; CHECK([state[@"rows"] count]==2 && WUEmoticonLibraryRows(state,@"").count==2);
    CHECK([[store resource:identifier error:&error][@"data"] isEqual:gif]);
    NSDictionary *before=[store load:&error];
    CHECK(![store rename:identifier group:NO name:@"stale" current:^BOOL{ return NO; } error:&error]); CHECK([[store load:&error] isEqual:before]);
    __block int calls=0; CHECK(![store rename:identifier group:NO name:@"stale after copy" current:^BOOL{ return ++calls<3; } error:&error]); CHECK([[store load:&error] isEqual:before]);
    CHECK(![store assign:identifier group:@"missing" current:valid error:&error]); CHECK(![store move:identifier group:NO to:400 current:valid error:&error]); CHECK(![store rename:identifier group:NO name:@"  " current:valid error:&error]);
    CHECK(![store importData:[gif subdataWithRange:NSMakeRange(0,gif.length-1)] name:@"broken" group:@"" current:valid error:&error]);
    CHECK([[store load:&error] isEqual:before]);
    WUEmoticonLibraryStore *reopen=[[WUEmoticonLibraryStore alloc] initWithRoot:root account:@"a"]; CHECK([[reopen load:&error] isEqual:before]);
    CHECK([reopen remove:identifier group:NO current:valid error:&error]); CHECK([[reopen load:&error][@"rows"] count]==1); CHECK([WUEmoticonRead(file.path) isEqual:gif]);
    NSURL *index=[[root URLByAppendingPathComponent:@"61" isDirectory:YES] URLByAppendingPathComponent:@"index.plist"];
    NSData *good=[NSData dataWithContentsOfURL:index]; CHECK([[@"not a plist" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:index options:0 error:NULL]);
    CHECK(![reopen load:&error]); error=nil; CHECK(![reopen resource:identifier error:&error]); CHECK([error.localizedDescription containsString:@"损坏或账号不符"]); CHECK(![reopen createGroup:@"no overwrite" current:valid error:&error]); CHECK([[[NSString alloc] initWithData:[NSData dataWithContentsOfURL:index] encoding:NSUTF8StringEncoding] isEqual:@"not a plist"]);
    CHECK([good writeToURL:index options:0 error:NULL]); CHECK([NSFileManager.defaultManager removeItemAtURL:index error:NULL]); CHECK(symlink(file.path.fileSystemRepresentation,index.path.fileSystemRepresentation)==0);
    CHECK(![reopen load:&error]); CHECK(![reopen createGroup:@"no follow" current:valid error:&error]); CHECK([WUEmoticonRead(file.path) isEqual:gif]);
    Submission(gif);
    CHECK([NSFileManager.defaultManager removeItemAtURL:root error:NULL]);
    printf("PASS production emoticon library/store/submission: %d assertions; synthetic media, mock host, no Photos or real account\n",checks);
#endif
} return 0; }
