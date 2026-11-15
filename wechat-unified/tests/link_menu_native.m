#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "WU.h"
#import "MessageEntries.h"
#import "RepeatOptions.h"
#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include "menu_matches.inc"
static BOOL enabled=YES, opened=NO, saved=NO;
id WUValue(NSString *k) { return nil; }
BOOL WUValidMD5(NSString *v) { return [v isKindOfClass:NSString.class] && v.length==32; }
static void WUSaveEmoticonForWrap(UIViewController *owner,id wrap,BOOL (^current)(void),BOOL verifyDigest) { saved=verifyDigest && current(); }
@interface EmoticonUtil : NSObject
+ (id)pathOfEmoticonForMd5:(id)md5 needUpdateTime:(BOOL)a ignoreWxAM:(BOOL)b;
@end
@implementation EmoticonUtil
+ (id)pathOfEmoticonForMd5:(id)md5 needUpdateTime:(BOOL)a ignoreWxAM:(BOOL)b { return @"/tmp/example"; }
@end
static NSUInteger generation=1, calls=0;
static NSString *account=@"me", *session=@"peer";
static UIViewController *testOwner;
BOOL WUEnabled(NSString *k) { return enabled; }
static NSString *Account(void) { return account; }
static NSString *Session(id owner) { return session; }
static UIViewController *Chat(id cell) { return testOwner; }
BOOL WUMessageEntriesOwnsController(UIViewController *c) { return NO; }
static BOOL Has(id o,NSString *name,const char *result,NSArray *args) { return o && WUMatches(class_getInstanceMethod(object_getClass(o),NSSelectorFromString(name)),result,args); }
static id Obj(id o,NSString *name) { return Has(o,name,"@",@[])?((id(*)(id,SEL))objc_msgSend)(o,NSSelectorFromString(name)):nil; }
static NSString *Str(id o,NSString *name) { id x=Obj(o,name); return [x isKindOfClass:NSString.class]?[x copy]:nil; }
@interface MockMessage : NSObject
@property(nonatomic,copy) NSString *m_nsFromUsr,*m_nsToUsr,*m_nsRealChatUsr,*m_nsContent,*m_nsEmoticonMD5;
@property(nonatomic) unsigned m_n64MesSvrID,m_uiMesLocalID,m_uiCreateTime,m_uiMessageType;
@end
@implementation MockMessage @end
@interface MockModel : NSObject
@property(nonatomic,strong) MockMessage *messageWrap;
@end
@implementation MockModel @end
@interface BaseMessageCellView : UIView
@property(nonatomic,strong) MockModel *viewModel;
- (id)filteredMenuItems:(id)items;
@end
@implementation BaseMessageCellView
- (id)filteredMenuItems:(id)items { calls++; return items; }
@end
@interface MMMenuItem : NSObject
@property(nonatomic) SEL action;
#if WU_TEST_BAD_MENU_ABI
- (id)initWithTitle:(id)title svgName:(id)svg action:(id)action;
#else
- (id)initWithTitle:(id)title svgName:(id)svg action:(SEL)action;
#endif
@end
@implementation MMMenuItem
#if WU_TEST_BAD_MENU_ABI
- (id)initWithTitle:(id)title svgName:(id)svg action:(id)action { return [super init]; }
#else
- (id)initWithTitle:(id)title svgName:(id)svg action:(SEL)action { if((self=[super init])) _action=action; return self; }
#endif
@end
static NSDictionary *Info(MockMessage *m) { return @{@"from":m.m_nsFromUsr?:@"",@"to":m.m_nsToUsr?:@"",@"real":m.m_nsRealChatUsr?:@"",@"id":@(m.m_n64MesSvrID),@"local":@(m.m_uiMesLocalID),@"time":@(m.m_uiCreateTime),@"type":@(m.m_uiMessageType)}; }
static BOOL InSession(NSDictionary *m,NSString *a,NSString *s) { return [m[@"from"] isEqual:s] && [m[@"to"] isEqual:a]; }
NSArray *WULinkCandidates(NSArray *messages) { return [messages[0][@"content"] containsString:@"https://"]?@[@1]:@[]; }
void WUOpenSelectedLinks(UIViewController *owner,NSArray *messages,BOOL (^current)(void)) { opened=current() && [messages[0][@"content"] containsString:@"https://"]; }
BOOL WUHook(NSString *name,NSString *selector,BOOL meta,const char *result,NSArray *args,IMP replacement,IMP *original) {
    Class cls=NSClassFromString(name); SEL sel=NSSelectorFromString(selector); Method m=class_getInstanceMethod(cls,sel);
    if(!WUMatches(m,result,args)) return NO;
    *original=method_getImplementation(m); method_setImplementation(m,replacement); return YES;
}
#include "WULinkMenu.inc"
static void Activate(UIViewController *owner,MMMenuItem *item,BaseMessageCellView *cell) { ((void(*)(id,SEL,id))objc_msgSend)(owner,item.action,cell); }
int main(void) { @autoreleasepool {
    UIWindow *window=[UIWindow new]; testOwner=[UIViewController new]; BaseMessageCellView *cell=[BaseMessageCellView new]; [window addSubview:cell];
    MockMessage *msg=[MockMessage new]; msg.m_nsFromUsr=@"peer"; msg.m_nsToUsr=@"me"; msg.m_nsRealChatUsr=@""; msg.m_nsContent=@"https://example.com"; msg.m_uiMessageType=1; msg.m_uiMesLocalID=7;
    cell.viewModel=[MockModel new]; cell.viewModel.messageWrap=msg;
    WUInstallLinkMenu();
#if WU_TEST_BAD_MENU_ABI
    assert(!wuLinkMenuOriginal); NSArray *original=@[@"host"]; assert([cell filteredMenuItems:original]==original && calls==1); puts("menu ABI fallback passed"); return 0;
#endif
    assert(wuLinkMenuOriginal);
    NSArray *host=@[@"host"]; NSArray *menu=[cell filteredMenuItems:host]; assert(calls==1 && menu.count==2 && menu[0]==host[0]);
    MMMenuItem *first=menu[1]; Activate(testOwner,first,cell); assert(opened);
    opened=NO; menu=[cell filteredMenuItems:host]; MMMenuItem *obsolete=menu[1]; menu=[cell filteredMenuItems:menu]; assert(menu.count==2 && menu[0]==host[0]); Activate(testOwner,obsolete,cell); assert(!opened); Activate(testOwner,menu[1],cell); assert(opened);
    opened=NO; menu=[cell filteredMenuItems:host]; MMMenuItem *cancelled=menu[1]; menu=[cell filteredMenuItems:host]; Activate(testOwner,cancelled,cell); assert(!opened); Activate(testOwner,menu[1],cell); assert(opened);
    opened=NO; menu=[cell filteredMenuItems:host]; cell.viewModel=[MockModel new]; cell.viewModel.messageWrap=msg; Activate(testOwner,menu[1],cell); assert(!opened);
    menu=[cell filteredMenuItems:host]; generation++; Activate(testOwner,menu[1],cell); assert(!opened);
    menu=[cell filteredMenuItems:host]; account=@"other"; Activate(testOwner,menu[1],cell); assert(!opened); account=@"me";
    enabled=NO; assert([cell filteredMenuItems:host]==host); enabled=YES;
    msg.m_nsContent=@"no links"; assert([cell filteredMenuItems:host]==host);
    msg.m_uiMessageType=47; msg.m_nsEmoticonMD5=@"0123456789abcdef0123456789abcdef";
    menu=[cell filteredMenuItems:host]; assert(menu.count==2 && menu[0]==host[0]);
    MMMenuItem *old=menu[1]; menu=[cell filteredMenuItems:menu]; assert(menu.count==2); Activate(testOwner,old,cell); assert(!saved); Activate(testOwner,menu[1],cell); assert(saved);
    saved=NO; menu=[cell filteredMenuItems:host]; msg.m_nsEmoticonMD5=@"1123456789abcdef0123456789abcdef"; Activate(testOwner,menu[1],cell); assert(!saved);
    menu=[cell filteredMenuItems:host]; generation++; Activate(testOwner,menu[1],cell); assert(!saved);
    menu=[cell filteredMenuItems:host]; account=@"other"; Activate(testOwner,menu[1],cell); assert(!saved); account=@"me";
    menu=[cell filteredMenuItems:host]; cell.viewModel=[MockModel new]; cell.viewModel.messageWrap=msg; Activate(testOwner,menu[1],cell); assert(!saved);
    msg.m_nsEmoticonMD5=@"bad"; assert([cell filteredMenuItems:host]==host);
    puts("menu production mock passed");
} return 0; }
