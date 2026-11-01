#import "WUNativeAction.h"
#include <assert.h>
extern NSDictionary *testOptions;
extern BOOL testMaster, testWriteOK, testThrowCopy, testBadMD5, testSwitchOnEnvelope;
extern NSString *testAccount;
extern NSUInteger testGeneration;
void TestInit(void);
void TestConfig(NSDictionary *options);
void TestDrainAsync(void);
void TestRunTimers(void);
void WUTestFlushDismissals(void);
@interface BaseMsgContentViewController : UIViewController
@property(nonatomic,copy) NSString *session;
@property(nonatomic,strong) id tool;
@property(nonatomic) NSUInteger touches, hides;
@property(nonatomic) BOOL throwTouch;
- (void)mmTableView:(id)table touchesBegan:(id)touches withEvent:(id)event;
- (void)hideInputToolView;
@end
#if defined(WU_TEST_64)
typedef unsigned long long TestNumber;
typedef unsigned long long TestID;
#else
typedef unsigned TestNumber;
typedef long long TestID;
#endif
@interface CMessageWrap : NSObject
@property(nonatomic) TestNumber m_uiMessageType, m_uiGameType, m_uiGameContent, m_uiMesLocalID;
#if defined(WU_TEST_BAD_ABI)
@property(nonatomic) double m_uiCreateTime;
#else
@property(nonatomic) TestNumber m_uiCreateTime;
#endif
@property(nonatomic) TestID m_n64MesSvrID;
@property(nonatomic,copy) NSString *m_nsFromUsr, *m_nsToUsr, *m_nsRealChatUsr, *m_nsEmoticonMD5;
- (instancetype)initWithMsgType:(TestNumber)type nsFromUsr:(NSString *)from;
- (void)copyToMsg:(CMessageWrap *)other;
@end
@interface Model : NSObject
@property(nonatomic,strong) CMessageWrap *messageWrap;
@end
@interface CommonMessageCellView : UIView
@property(nonatomic,strong) Model *viewModel;
@property(nonatomic,strong) UIView *head;
@property(nonatomic) NSUInteger pats;
@property(nonatomic,strong) id receivedSender;
@property(nonatomic) BOOL throwPat;
- (id)getHeadImageView;
#if defined(WU_TEST_BAD_ABI)
- (BOOL)onHeadImageDoubleClick:(id)sender;
#else
- (void)onHeadImageDoubleClick:(id)sender;
#endif
@end
@interface MMInputToolView : UIView
@property(nonatomic,strong) UITextView *editor;
@property(nonatomic) NSUInteger hides,resigns;
- (void)hideToolView:(BOOL)animated;
@end
@interface VoiceMessageCellView : UIView
@property(nonatomic,strong) UIView *m_bgImageView;
@end
@interface CMessageMgr : NSObject
@property(nonatomic) NSUInteger sends;
@property(nonatomic,strong) CMessageWrap *sent;
@property(nonatomic,copy) NSString *destination;
@property(nonatomic) BOOL throws, reenter;
- (void)AddEmoticonMsg:(NSString *)destination MsgWrap:(CMessageWrap *)message;
@end
@interface TestScene : NSObject
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) BaseMsgContentViewController *chat;
@property(nonatomic,strong) CommonMessageCellView *cell;
@property(nonatomic,strong) CMessageMgr *manager;
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,strong) VoiceMessageCellView *voice;
@property(nonatomic,strong) MMInputToolView *tool;
@end
