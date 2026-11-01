#import "TestHost.h"
#include <string.h>
#include <stdlib.h>
static NSMutableDictionary<NSString *, NSString *> *hooks;
#include "core_hooks.inc"
NSDictionary *testOptions;
BOOL testMaster=YES, testWriteOK=YES, testThrowCopy, testBadMD5, testSwitchOnEnvelope;
NSString *testAccount=@"account-A";
NSUInteger testGeneration=1;
NSString *const WUChanged=@"test.config";
static NSMutableArray *timers;
void WUTestAfter(dispatch_time_t time,dispatch_queue_t queue,dispatch_block_t block) { if(!timers) timers=[NSMutableArray array]; [timers addObject:[block copy]]; }
void TestRunTimers(void) { NSArray *copy=[timers copy]; [timers removeAllObjects]; for(dispatch_block_t b in copy) b(); }
void TestDrainAsync(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }
BOOL WUEnabled(NSString *key) { return testMaster; }
id WUValue(NSString *key) { return [key isEqual:@"native"]?testOptions:([key isEqual:@"enabled"]?@(testMaster):nil); }
BOOL WUSave(NSString *key,id value) {
    if(!testWriteOK) return NO;
    if([key isEqual:@"native"] && WUNativeValidOptions(value)) testOptions=[value copy];
    else if([key isEqual:@"enabled"]) testMaster=[value boolValue]; else return NO;
    [NSNotificationCenter.defaultCenter postNotificationName:WUChanged object:nil]; return YES;
}
void TestConfig(NSDictionary *o) { testOptions=[o copy]; [NSNotificationCenter.defaultCenter postNotificationName:WUChanged object:nil]; }
void TestInit(void) { hooks=[NSMutableDictionary dictionary]; testOptions=@{}; }
NSString *WUCurrentAccount(void) { return testAccount; }
NSUInteger WUContextGeneration(void) { return testGeneration; }
NSUInteger WUContextGenerationSnapshot(void) { return testGeneration; }
NSString *WUChatSession(UIViewController *v) { return [v isKindOfClass:BaseMsgContentViewController.class]?[(BaseMsgContentViewController *)v session]:nil; }
@implementation BaseMsgContentViewController
- (void)mmTableView:(id)t touchesBegan:(id)touches withEvent:(id)e {
    self.touches++; [self hideInputToolView]; [self.tool hideToolView:YES]; [self.tool resignFirstResponder];
    if(self.throwTouch) @throw [NSException exceptionWithName:@"touch" reason:nil userInfo:nil];
}
- (void)hideInputToolView { self.hides++; }
@end
@implementation MMInputToolView
- (void)hideToolView:(BOOL)b { self.hides++; }
- (BOOL)resignFirstResponder { self.resigns++; self.editor.firstResponder=NO; return YES; }
@end
@implementation VoiceMessageCellView @end
@implementation CMessageWrap
@synthesize m_nsFromUsr=_m_nsFromUsr;
- (void)setM_nsFromUsr:(NSString *)s {
    _m_nsFromUsr=[s copy];
    if(testSwitchOnEnvelope && [s isEqual:@"account-A"]) { testSwitchOnEnvelope=NO; testAccount=@"switched-during-prepare"; testGeneration++; }
}
- (instancetype)initWithMsgType:(TestNumber)t nsFromUsr:(NSString *)a { if((self=[super init])) { _m_uiMessageType=t; _m_nsFromUsr=[a copy]; } return self; }
- (void)copyToMsg:(CMessageWrap *)w {
    if(testThrowCopy) @throw [NSException exceptionWithName:@"copy" reason:nil userInfo:nil];
    for(NSString *k in @[@"m_uiMessageType",@"m_uiGameType",@"m_uiGameContent",@"m_uiCreateTime",@"m_uiMesLocalID",@"m_n64MesSvrID",@"m_nsFromUsr",@"m_nsToUsr",@"m_nsRealChatUsr",@"m_nsEmoticonMD5"])
        [w setValue:[self valueForKey:k] forKey:k];
}
@end
@implementation Model @end
@implementation CommonMessageCellView
- (id)getHeadImageView { return self.head; }
- (void)onHeadImageDoubleClick:(id)sender { self.pats++; self.receivedSender=sender; if(self.throwPat) @throw [NSException exceptionWithName:@"pat" reason:nil userInfo:nil]; }
@end
@interface GameController : NSObject
+ (NSString *)getMD5ByGameContent:(unsigned long long)n;
@end
@implementation GameController
+ (NSString *)getMD5ByGameContent:(unsigned long long)n { return testBadMD5?@"invalid":[NSString stringWithFormat:@"%032llx",n]; }
@end
@implementation CMessageMgr
- (void)AddEmoticonMsg:(NSString *)d MsgWrap:(CMessageWrap *)w {
    self.sends++; self.sent=w; self.destination=d;
    if(self.reenter) { self.reenter=NO; [self AddEmoticonMsg:d MsgWrap:w]; }
    if(self.throws) @throw [NSException exceptionWithName:@"send" reason:nil userInfo:nil];
}
@end
@implementation TestScene
- (instancetype)init { if((self=[super init])) {
    WUNativeCancelActions(); testMaster=YES; testAccount=@"account-A"; testGeneration++;
    UIApplication.sharedApplication.applicationState=UIApplicationStateActive;
    _window=[UIWindow new]; _window.keyWindow=YES; _chat=[BaseMsgContentViewController new]; _chat.session=@"chat-A";
    _window.rootViewController=_chat; [_window addSubview:_chat.view];
    UIWindowScene *scene=[UIWindowScene new]; scene.activationState=UISceneActivationStateForegroundActive; scene.windows=@[_window]; UIApplication.sharedApplication.connectedScenes=[NSSet setWithObject:scene];
    _cell=[CommonMessageCellView new]; [_chat.view addSubview:_cell]; _cell.head=[UIImageView new]; [_cell addSubview:_cell.head];
    _cell.viewModel=[Model new]; CMessageWrap *w=[[CMessageWrap alloc] initWithMsgType:47 nsFromUsr:@"chat-A"];
    w.m_nsToUsr=@"account-A"; w.m_nsRealChatUsr=@""; w.m_uiMesLocalID=4; w.m_n64MesSvrID=5000000001LL; w.m_uiCreateTime=100; w.m_uiGameType=1; w.m_uiGameContent=3; w.m_nsEmoticonMD5=@"original"; _cell.viewModel.messageWrap=w;
    _manager=[CMessageMgr new]; _table=[UITableView new]; [_chat.view addSubview:_table];
    _voice=[VoiceMessageCellView new]; [_table addSubview:_voice]; _voice.m_bgImageView=[UIView new]; [_voice addSubview:_voice.m_bgImageView]; _table.hitResult=_voice.m_bgImageView;
    _tool=[MMInputToolView new]; [_chat.view addSubview:_tool]; _tool.editor=[UITextView new]; [_tool addSubview:_tool.editor]; _tool.editor.firstResponder=YES; _chat.tool=_tool;
} return self; }
@end
