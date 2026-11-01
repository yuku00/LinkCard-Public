// Complete production entry compiled unchanged; Foundation/ImageIO are real.
#import "WU.h"
#import <ImageIO/ImageIO.h>
#include <unistd.h>
#include <fcntl.h>
#include <zlib.h>
#include <string.h>
#include <stdatomic.h>
#include "image_entry_matches.inc"
static int checks, initCalls, imageCalls, clearCalls;
#define CHECK(x) do { checks++; if(!(x)) { fprintf(stderr,"FAILED %d: %s\n",__LINE__,#x); abort(); } } while(0)
static NSString *account=@"account-A", *session=@"chat-A";
static _Atomic(NSUInteger) generation=1;
static BOOL enabled=YES, selectedTool=YES, throwSelection, badDecode, animatedDecode;
static int initBehavior, setterBehavior;
static void (^duringSetter)(void);
NSString *const WUChanged=@"mock.image.config";
id WUValue(NSString *key) { return [key isEqual:@"enabled"]?@(enabled):nil; }
NSString *WUCurrentAccount(void) { return account; }
NSUInteger WUContextGeneration(void) { return generation; }
NSUInteger WUContextGenerationSnapshot(void) { return atomic_load(&generation); }
NSString *WUChatSession(UIViewController *owner) { return session; }
NSDictionary *WUAccountOptions(NSString *a) { return @{@"toolbar":selectedTool?@[@"imageEmoji"]:@[]}; }
#import "../Sources/WUImageEntry.m"

@implementation UIImage
+ (instancetype)imageWithData:(NSData *)data {
    if(badDecode) return nil;
    CGImageSourceRef src=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
    CGImageRef pixels=src?CGImageSourceCreateImageAtIndex(src,0,NULL):NULL;
    UIImage *image=nil;
    if(pixels) { image=[self new]; image.mockBytes=data; if(animatedDecode) image.images=@[[UIImage new]]; CGImageRelease(pixels); }
    if(src) CFRelease(src); return image;
}
@end
@interface CMessageWrap : NSObject
@property(nonatomic) unsigned int m_uiMessageType, m_uiMesLocalID, m_uiCreateTime;
@property(nonatomic) unsigned long long m_n64MesSvrID;
@property(nonatomic,copy) NSString *m_nsFromUsr, *m_nsToUsr, *m_nsRealChatUsr, *m_nsImageHDPath, *m_nsImagePath;
@end
@implementation CMessageWrap @end
@interface ImageChat : UIViewController
@property(nonatomic,copy) NSArray *selection;
- (id)getSelectedMsgs;
@end
@implementation ImageChat
- (id)getSelectedMsgs { if(throwSelection) @throw [NSException exceptionWithName:@"selection" reason:nil userInfo:nil]; return self.selection; }
@end
@interface ImageNavigation : UINavigationController
@property(nonatomic,copy) NSArray<UIViewController *> *viewControllers;
@property(nonatomic) NSUInteger pushes, changes;
@property(nonatomic) int throwPush;
@property(nonatomic,copy) void (^duringPush)(void);
@end
@implementation ImageNavigation
@synthesize viewControllers=_viewControllers;
- (void)setViewControllers:(NSArray<UIViewController *> *)stack animated:(BOOL)animated {
    self.changes++;
    for(UIViewController *v in self.viewControllers) if(![stack containsObject:v]) v.navigationController=nil;
    self.viewControllers=stack; self.topViewController=stack.lastObject;
    for(UIViewController *v in stack) v.navigationController=self;
}
- (void)pushViewController:(UIViewController *)v animated:(BOOL)animated {
    self.pushes++;
    if(self.throwPush==1) @throw [NSException exceptionWithName:@"push-before" reason:nil userInfo:nil];
    [self setViewControllers:[self.viewControllers arrayByAddingObject:v] animated:animated];
    if(self.duringPush) self.duringPush();
    if(self.throwPush==2) @throw [NSException exceptionWithName:@"push-after" reason:nil userInfo:nil];
}
@end
@interface ImageEditorBase : UIViewController
@property(nonatomic,strong) UIImage *accepted;
- (void)setM_image:(UIImage *)image;
@end
@implementation ImageEditorBase
- (instancetype)init {
    initCalls++;
    if(initBehavior==1) return nil;
    if(initBehavior==2) @throw [NSException exceptionWithName:@"init" reason:nil userInfo:nil];
    if(initBehavior==3) return (id)[NSObject new];
    return [super init];
}
- (void)setM_image:(UIImage *)image {
    if(!image) { clearCalls++; self.accepted=nil; return; }
    imageCalls++;
    if(setterBehavior==1) @throw [NSException exceptionWithName:@"image" reason:nil userInfo:nil];
    self.accepted=image;
    if(duringSetter) duringSetter();
}
@end
static unsigned long long BadInit(id self, SEL s) { abort(); }
static void BadSetter(id self, SEL s, long long value) { abort(); }
static void BadGetterClass(id object, NSString *name, NSString *selector) {
    Class c=objc_allocateClassPair(object_getClass(object),name.UTF8String,0); CHECK(c!=Nil);
    CHECK(class_addMethod(c,NSSelectorFromString(selector),(IMP)BadInit,"d@:"));
    objc_registerClassPair(c); object_setClass(object,c);
}
static void RegisterEditor(NSString *mode) {
    if([mode isEqual:@"missing"]) return;
    Class base=[mode isEqual:@"wrong-class"]?NSObject.class:([mode isEqual:@"missing-setter"]?UIViewController.class:ImageEditorBase.class);
    Class c=objc_allocateClassPair(base,"EmoticonPickViewController",0); CHECK(c!=Nil);
    if([mode isEqual:@"bad-init"]) CHECK(class_addMethod(c,@selector(init),(IMP)BadInit,"Q@:"));
    if([mode isEqual:@"bad-setter"]) CHECK(class_addMethod(c,NSSelectorFromString(@"setM_image:"),(IMP)BadSetter,"v@:q"));
    objc_registerClassPair(c);
}
static NSData *Fixture(NSString *uti, NSUInteger frames) {
    unsigned char p[]={255,0,0,255,0,255,0,255,0,0,255,255,255,255,255,255};
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(p,2,2,8,8,color,kCGImageAlphaPremultipliedLast);
    NSMutableData *data=[NSMutableData data];
    CGImageDestinationRef dst=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,(__bridge CFStringRef)uti,frames,NULL); CHECK(dst!=NULL);
    for(NSUInteger i=0;i<frames;i++) { CGImageRef image=CGBitmapContextCreateImage(ctx); CGImageDestinationAddImage(dst,image,NULL); CGImageRelease(image); }
    CHECK(CGImageDestinationFinalize(dst)); CFRelease(dst); CGContextRelease(ctx); CGColorSpaceRelease(color); return data;
}
static NSData *APNGMarker(NSData *png) {
    // Valid CRC acTL marker; rejected even if ImageIO collapses it to one image.
    unsigned char chunk[]={0,0,0,8,'a','c','T','L',0,0,0,2,0,0,0,0,0,0,0,0};
    uint32_t crc=(uint32_t)crc32(0,chunk+4,12); for(int i=0;i<4;i++) chunk[16+i]=(unsigned char)(crc>>(24-8*i));
    NSMutableData *out=[NSMutableData dataWithBytes:png.bytes length:33]; [out appendBytes:chunk length:20]; [out appendData:[png subdataWithRange:NSMakeRange(33,png.length-33)]]; return out;
}
static void Drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]]; }
static void Wait(BOOL (^done)(void)) { NSDate *end=[NSDate dateWithTimeIntervalSinceNow:5]; while(!done() && end.timeIntervalSinceNow>0) Drain(); CHECK(done()); }
static void Tick(void) { for(WUImageEntry *op in entries.allObjects) [op.timer fire]; }
static UIWindow *window;
static ImageChat *chat;
static ImageNavigation *nav;
static CMessageWrap *wrap;
static NSString *directory, *path;
static void Setup(NSData *bytes) {
    WUCancelImageEntries(); Drain();
    account=@"account-A"; session=@"chat-A"; generation++; enabled=YES; selectedTool=YES;
    throwSelection=NO; badDecode=NO; animatedDecode=NO; initBehavior=0; setterBehavior=0; duringSetter=nil;
    initCalls=0; imageCalls=0; clearCalls=0; UIApplication.sharedApplication.applicationState=UIApplicationStateActive;
    CHECK([bytes writeToFile:path atomically:YES]);
    window=[UIWindow new]; chat=[ImageChat new]; [window addSubview:chat.view];
    nav=[ImageNavigation new]; [nav setViewControllers:@[chat] animated:NO]; nav.changes=0;
    wrap=[CMessageWrap new]; wrap.m_uiMessageType=3; wrap.m_n64MesSvrID=5000000001ULL; wrap.m_uiMesLocalID=2; wrap.m_uiCreateTime=123;
    wrap.m_nsFromUsr=@"chat-A"; wrap.m_nsToUsr=@"account-A"; wrap.m_nsImagePath=path; chat.selection=@[wrap];
}
static UIAlertController *Prompt(void) {
    WUOpenSelectedImageEditor(chat);
    Wait(^BOOL { return chat.presentedViewController!=nil || entries.count==0; });
    CHECK([chat.presentedViewController isKindOfClass:UIAlertController.class]);
    UIAlertController *prompt=(id)chat.presentedViewController; CHECK(prompt.actions.count==2); return prompt;
}
static void Accept(UIAlertController *prompt) { [prompt.actions.lastObject fire]; Drain(); }
static void Rejected(void) {
    WUOpenSelectedImageEditor(chat); Wait(^BOOL{ return entries.count==0; }); CHECK(nav.pushes==0 && imageCalls==0);
}
static void Open(void) { Accept(Prompt()); CHECK(nav.pushes==1 && imageCalls==1 && WUImageEntryOwnsNavigation(chat)); }
int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *mode=argc>1?[NSString stringWithUTF8String:argv[1]]:@"normal"; RegisterEditor(mode);
    directory=[[NSHomeDirectory() stringByResolvingSymlinksInPath] stringByAppendingPathComponent:[@"wu-image-entry-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    CHECK([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]);
    path=[directory stringByAppendingPathComponent:@"selected.cache"];
    NSData *png=Fixture(@"public.png",1), *jpeg=Fixture(@"public.jpeg",1), *gif=Fixture(@"com.compuserve.gif",2), *singleGIF=Fixture(@"com.compuserve.gif",1);
    if(![mode isEqual:@"normal"]) {
        Setup(png); Accept(Prompt()); CHECK(nav.pushes==0 && initCalls==0 && imageCalls==0 && entries.count==0);
    } else {
        CHECK(StaticImage(png)); CHECK(StaticImage(jpeg)); CHECK(!StaticImage(gif)); CHECK(!StaticImage(singleGIF)); CHECK(!StaticImage(APNGMarker(png)));
        CHECK(!StaticImage(nil)); CHECK(!StaticImage([png subdataWithRange:NSMakeRange(0,png.length-1)]));
        CHECK(!StaticImage([NSMutableData dataWithLength:20*1024*1024+1]));
        for(NSData *image in @[png,jpeg]) {
            Setup(image); UIAlertController *p=Prompt();
            WUOpenSelectedImageEditor(chat); CHECK(entries.count==1);
            __weak ImageChat *source=chat; nav.duringPush=^{ CHECK(WUImageEntryOwnsNavigation(source)); };
            Accept(p); Accept(p); CHECK(nav.pushes==1 && imageCalls==1 && initCalls==1);
            ImageEditorBase *editor=(id)nav.topViewController; CHECK([editor.accepted.mockBytes isEqual:image]);
            CHECK([WUEmoticonRead(path) isEqual:image]);
            // Native back/cancel has already removed its page. Plugin must not mutate it.
            [nav setViewControllers:@[chat] animated:NO]; NSUInteger changes=nav.changes; Tick();
            CHECK(entries.count==0 && nav.changes==changes && clearCalls==0 && editor.accepted!=nil);
            CHECK([WUEmoticonRead(path) isEqual:image]);
        }
        // Source selection is frozen before confirmation, not a lifetime lease on host multi-select UI.
        Setup(png); nav.duringPush=^{ chat.selection=@[]; }; Open(); Tick();
        CHECK(entries.count==1 && ((ImageEditorBase *)nav.topViewController).accepted!=nil);
        generation++; Tick(); CHECK(entries.count==0 && nav.topViewController==chat);
        Setup(png); duringSetter=^{ chat.selection=@[]; }; Accept(Prompt());
        CHECK(nav.pushes==0 && entries.count==0);
        Setup(png); UIAlertController *p=Prompt(); [p.actions.firstObject fire]; [p.actions.lastObject fire];
        CHECK(entries.count==0 && nav.pushes==0 && imageCalls==0 && chat.presentedViewController==nil);
        for(NSData *bad in @[gif,singleGIF,APNGMarker(png),[png subdataWithRange:NSMakeRange(0,16)],NSData.data]) { Setup(bad); Rejected(); CHECK([[NSData dataWithContentsOfFile:path] isEqual:bad]); }
        Setup(png); wrap.m_nsImageHDPath=[directory stringByAppendingPathComponent:@"missing-HD"]; Open(); CHECK([((ImageEditorBase *)nav.topViewController).accepted.mockBytes isEqual:png]);
        Setup(png); wrap.m_nsImagePath=nil; Rejected();
        Setup(png); wrap.m_nsImagePath=@"relative"; Rejected();
        Setup(png); wrap.m_nsImagePath=@"/etc/passwd"; Rejected();
        Setup(png); wrap.m_nsImagePath=directory; Rejected();
        NSString *link=[directory stringByAppendingPathComponent:@"symlink"]; CHECK(symlink(path.fileSystemRepresentation,link.fileSystemRepresentation)==0);
        Setup(png); wrap.m_nsImagePath=link; Rejected();
        Setup(png); wrap.m_nsImagePath=[directory stringByAppendingPathComponent:@"absent"]; Rejected();
        NSString *badHD=[directory stringByAppendingPathComponent:@"bad-HD"]; CHECK([gif writeToFile:badHD atomically:YES]);
        Setup(png); wrap.m_nsImageHDPath=badHD; Rejected(); // Never flatten GIF via PNG fallback.
        int fd=open(badHD.fileSystemRepresentation,O_WRONLY); CHECK(fd>=0); CHECK(ftruncate(fd,20*1024*1024+1)==0); close(fd);
        Setup(png); wrap.m_nsImageHDPath=badHD; Rejected(); // Never bypass oversize via fallback.
        Setup(png); chat.selection=@[]; Rejected();
        Setup(png); chat.selection=@[wrap,wrap]; Rejected();
        Setup(png); chat.selection=@[[NSObject new]]; Rejected();
        Setup(png); wrap.m_uiMessageType=47; Rejected();
        Setup(png); wrap.m_n64MesSvrID=0; wrap.m_uiMesLocalID=0; Rejected();
        Setup(png); wrap.m_nsFromUsr=@"other-chat"; Rejected();
        Setup(png); throwSelection=YES; Rejected();
        Setup(png); BadGetterClass(chat,@"BadImageSelection",@"getSelectedMsgs"); Rejected();
        Setup(png); BadGetterClass(wrap,@"BadImagePath",@"m_nsImagePath"); Rejected();
        Setup(png); BadGetterClass(wrap,@"BadImageType",@"m_uiMessageType"); wrap.m_uiMessageType=47; Rejected();
        Setup(png); wrap.m_nsImagePath=(id)@42; Rejected();
        Setup(png); selectedTool=NO; Rejected();
        Setup(png); enabled=NO; Rejected();
        Setup(png); session=@"room@chatroom"; wrap.m_nsFromUsr=session; Open();
        Setup(png); wrap.m_nsFromUsr=account; wrap.m_nsToUsr=session; Open();
        for(int invalidation=0;invalidation<6;invalidation++) {
            Setup(png); p=Prompt();
            switch(invalidation) {
                case 0: wrap.m_n64MesSvrID++; break;
                case 1: chat.selection=@[[CMessageWrap new]]; break;
                case 2: wrap.m_nsImagePath=badHD; break;
                case 3: account=@"account-B"; break;
                case 4: session=@"chat-B"; break;
                default: generation++; break;
            }
            Accept(p); CHECK(entries.count==0 && nav.pushes==0 && imageCalls==0);
        }
        Setup(png); WUOpenSelectedImageEditor(chat); account=@"account-B"; Tick(); Drain(); CHECK(entries.count==0 && nav.pushes==0 && chat.presentedViewController==nil);
        for(int behavior=1;behavior<=3;behavior++) { Setup(png); initBehavior=behavior; Accept(Prompt()); CHECK(initCalls==1 && imageCalls==0 && nav.pushes==0 && entries.count==0); }
        Setup(png); setterBehavior=1; Accept(Prompt()); CHECK(initCalls==1 && imageCalls==1 && nav.pushes==0 && entries.count==0);
        Setup(png); duringSetter=^{ account=@"account-B"; generation++; }; Accept(Prompt()); CHECK(imageCalls==1 && nav.pushes==0 && entries.count==0);
        Setup(png); badDecode=YES; Rejected();
        Setup(png); animatedDecode=YES; Rejected();
        for(int behavior=1;behavior<=2;behavior++) { Setup(png); nav.throwPush=behavior; Accept(Prompt()); CHECK(nav.pushes==1 && entries.count==0 && nav.topViewController==chat && nav.viewControllers.count==1); }
        for(int invalidation=0;invalidation<6;invalidation++) {
            Setup(png); Open(); ImageEditorBase *editor=(id)nav.topViewController; WUImageEntry *operation=entries.anyObject;
            UIViewController *other=[UIViewController new];
            if(invalidation==0) {
                UIApplication.sharedApplication.applicationState=UIApplicationStateInactive;
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
            } else if(invalidation==1) { account=@"account-B"; Tick(); }
            else if(invalidation==2) { generation++; Tick(); }
            else if(invalidation==3) { wrap.m_n64MesSvrID++; Tick(); }
            else if(invalidation==4) { [nav pushViewController:other animated:NO]; Tick(); CHECK(entries.count==1); generation++; Tick(); }
            else { [nav setViewControllers:@[other] animated:NO]; Tick(); }
            CHECK(entries.count==0 && ![nav.viewControllers containsObject:editor]);
            CHECK(!operation.image && !operation.editor && !operation.wrap && !operation.timer && !operation.paths);
            CHECK(nav.topViewController==(invalidation>=4?other:chat));
            CHECK([WUEmoticonRead(path) isEqual:png]);
            NSUInteger changes=nav.changes; WUCancelImageEntries(); CHECK(nav.changes==changes);
        }
        Setup(png); p=Prompt(); [p dismissViewControllerAnimated:NO completion:nil];
        UIViewController *unrelated=[UIViewController new]; [chat presentViewController:unrelated animated:NO completion:nil];
        Accept(p); CHECK(entries.count==0 && chat.presentedViewController==unrelated && unrelated.dismisses==0 && nav.pushes==0);
        Setup(png); p=Prompt(); p.deferDismissCompletion=YES; Accept(p);
        CHECK(nav.pushes==0); WUCancelImageEntries();
        extern void WUTestFlushDismissals(void); WUTestFlushDismissals(); CHECK(nav.pushes==0 && entries.count==0);
        Setup(png); p=Prompt(); [NSNotificationCenter.defaultCenter postNotificationName:WUChanged object:nil]; Accept(p); CHECK(nav.pushes==0 && entries.count==0);
        Setup(png); Open(); generation++; Wait(^BOOL{ return entries.count==0; }); CHECK(nav.topViewController==chat); // Real timer, not only manual tick.
    }
    WUCancelImageEntries(); Drain(); CHECK([NSFileManager.defaultManager removeItemAtPath:directory error:NULL]);
    printf("image-entry %s: %d assertions; synthetic local data only; no host/backend writes\n",mode.UTF8String,checks);
} return 0; }
