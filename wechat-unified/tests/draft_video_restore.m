#import <Foundation/Foundation.h>
#import "DraftsLogic.h"
#import "DraftMediaLogic.h"
#include <string.h>
static NSUInteger checks,factories,editors,thumbCalls,sends;
static BOOL rejectFactory;
#define CHECK(...) do { checks++; if(!(__VA_ARGS__)) { NSLog(@"FAIL line %d",__LINE__); abort(); } } while(0)
static void U32(uint8_t *p,uint32_t n) { p[0]=n>>24;p[1]=n>>16;p[2]=n>>8;p[3]=n; }
static NSData *Box(const char *type,NSData *body) { NSMutableData *d=[NSMutableData dataWithLength:8]; U32(d.mutableBytes,(uint32_t)body.length+8); memcpy((char *)d.mutableBytes+4,type,4); [d appendData:body]; return d; }
static NSData *Video(void) {
    uint8_t dr[20]={0}; U32(dr+4,1); U32(dr+8,12); memcpy(dr+12,"url ",4); U32(dr+16,1);
    NSData *b=Box("dref",[NSData dataWithBytes:dr length:20]); for(NSString *t in @[@"dinf",@"minf",@"mdia",@"trak",@"moov"]) b=Box(t.UTF8String,b);
    const char brand[8]={'i','s','o','m',0,0,0,0}; NSMutableData *d=[Box("ftyp",[NSData dataWithBytes:brand length:8]) mutableCopy]; [d appendData:b]; [d appendData:Box("mdat",[NSData dataWithBytes:"x" length:1])]; return d;
}
@interface VideoFactory : NSObject
@property(nonatomic,strong) NSURL *url;
+ (id)draftWithVideoURL:(NSURL *)url;
+ (id)draftWithVideoURL:(NSURL *)url thumbImage:(id)image;
@end
@implementation VideoFactory
+ (id)draftWithVideoURL:(NSURL *)url { factories++; if(rejectFactory) return nil; VideoFactory *v=[self new]; v.url=url; return v; }
+ (id)draftWithVideoURL:(NSURL *)url thumbImage:(id)image { thumbCalls++; return [self draftWithVideoURL:url]; }
@end
@interface VideoEditor : NSObject
@property(nonatomic,strong) id sightDraft;
- (instancetype)initWithSightDraft:(id)draft;
@end
@implementation VideoEditor
- (instancetype)initWithSightDraft:(id)draft { if((self=[super init])) { editors++; _sightDraft=draft; } return self; }
- (void)send { sends++; }
@end
@interface WrongFactory : NSObject
+ (NSUInteger)draftWithVideoURL:(NSURL *)url;
@end
@implementation WrongFactory
+ (NSUInteger)draftWithVideoURL:(NSURL *)url { abort(); }
@end
int main(void) { @autoreleasepool {
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES].URLByResolvingSymlinksInPath;
    NSData *video=Video(); NSString *uuid=NSUUID.UUID.UUIDString; BOOL (^yes)(void)=^BOOL{ return YES; };
    CHECK(WUDraftMediaPutChecked(root,@"a",uuid,@"synthetic text",@"video-backup",@[video],yes,NULL));
    NSDictionary *row=WUDraftMediaLoad(root,@"a",NULL)[0]; NSURL *master=WUDraftMediaURLs(root,@"a",row,NULL)[0];
    NSURL *copy=WUDraftMediaVideoEditingCopy(root,@"a",row,yes,NULL); CHECK(copy && ![copy isEqual:master]); CHECK([copy.pathExtension isEqual:@"mp4"]);
    CHECK([WUDraftMediaReadSource(copy,64*1024*1024) isEqual:video]); CHECK(!WUDraftMediaVideoEditingCopy(root,@"b",row,yes,NULL));
    CHECK(!WUDraftMediaVideoEditingCopy(root,@"a",row,^BOOL{ return NO; },NULL));
    CHECK(WUDraftsVideoEditorAvailable(VideoEditor.class,VideoFactory.class)); CHECK(!WUDraftsVideoEditorAvailable(VideoEditor.class,WrongFactory.class));
    id expected=nil; VideoEditor *editor=WUDraftsCreateVideoEditor(VideoEditor.class,VideoFactory.class,copy,yes,&expected);
    CHECK(editor && editor.sightDraft==expected); CHECK([[(VideoFactory *)expected url] isEqual:copy]); CHECK(factories==1 && editors==1 && sends==0 && thumbCalls==0);
    CHECK(!WUDraftsCreateVideoEditor(VideoEditor.class,WrongFactory.class,copy,yes,&expected)); CHECK(expected==nil);
    rejectFactory=YES; CHECK(!WUDraftsCreateVideoEditor(VideoEditor.class,VideoFactory.class,copy,yes,&expected)); CHECK(thumbCalls==0 && factories==2 && editors==1); rejectFactory=NO;
    __block NSUInteger currentCalls=0; CHECK(!WUDraftsCreateVideoEditor(VideoEditor.class,VideoFactory.class,copy,^BOOL{ return ++currentCalls<2; },&expected)); CHECK(editors==1 && expected==nil);
    // A host editing lifecycle may delete its disposable copy, never the indexed backup.
    CHECK([NSFileManager.defaultManager removeItemAtURL:copy error:NULL]); CHECK([WUDraftMediaReadSource(master,64*1024*1024) isEqual:video]);
    NSURL *again=WUDraftMediaVideoEditingCopy(root,@"a",row,yes,NULL); CHECK(again && ![again isEqual:copy] && ![again isEqual:master]);
    CHECK(WUDraftMediaPutChecked(root,@"a",uuid,@"edited body",@"video-backup",@[again],yes,NULL)); CHECK([WUDraftMediaLoad(root,@"a",NULL)[0][@"text"] isEqual:@"edited body"]);
    CHECK([WUDraftMediaReadSource(master,64*1024*1024) isEqual:video]); CHECK(sends==0);
    NSURL *index=[root URLByAppendingPathComponent:@"61/index.plist"]; CHECK([[@"bad index" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:index atomically:YES]);
    CHECK(!WUDraftMediaVideoEditingCopy(root,@"a",row,yes,NULL)); CHECK([NSFileManager.defaultManager fileExistsAtPath:master.path]);
    CHECK([NSFileManager.defaultManager removeItemAtURL:root error:NULL]);
    printf("Video draft copy -> actual factory/init mock -> resave: %lu checks passed\n",(unsigned long)checks);
} return 0; }
