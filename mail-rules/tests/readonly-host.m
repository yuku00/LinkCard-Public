#import "readonly/Graph.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

@implementation UIView @end
@implementation UIWindow @end
@implementation UIViewController @end
@implementation UINavigationController @end
@implementation UITabBarController @end
@implementation UITableView @end
@implementation UICollectionView @end

@protocol MailParentProtocol
- (id)senderAddress;
@optional
+ (id)accountToken;
@end
@protocol MailChildProtocol <MailParentProtocol>
- (void)createMailbox:(id)value;
@end
@interface MessageListViewController : UIViewController <MailChildProtocol>
@end
@implementation MessageListViewController
- (id)senderAddress { abort(); }
- (id)subject { abort(); }
- (id)body { abort(); }
- (id)URL { abort(); }
- (id)account { abort(); }
- (id)mailbox { abort(); }
- (id)selectionModel { abort(); }
- (id)predicate { abort(); }
- (id)valueForKey:(NSString *)key { (void)key; abort(); }
- (void)createMailbox:(id)value { (void)value; abort(); }
- (void)moveMessages:(id)value { (void)value; abort(); }
- (void)setSelected:(BOOL)value { (void)value; abort(); }
- (NSString *)description { abort(); }
@end
@interface MessageListFixtureChild : MessageListViewController @end
@implementation MessageListFixtureChild @end
@interface MailboxPickerController : UIViewController @end
@implementation MailboxPickerController @end
@interface MailboxPickerFixtureChild : MailboxPickerController @end
@implementation MailboxPickerFixtureChild @end
@interface MailboxListViewController : UIViewController @end
@implementation MailboxListViewController @end
@interface SecretEvent : NSObject @end
@implementation SecretEvent
- (id)senderAddress { abort(); }
- (id)account { abort(); }
- (id)valueForKey:(NSString *)key { (void)key; abort(); }
- (NSString *)description { abort(); }
- (Class)class { abort(); }
@end
static NSUInteger originalCalls;
static __unsafe_unretained id originalOwner,originalArgument;
@interface FakeApplication : NSObject
- (void)sendEvent:(id)event;
@end
@implementation FakeApplication
- (void)sendEvent:(id)event { originalCalls++; originalOwner=self; originalArgument=event; }
@end
@interface ChildApplication : FakeApplication @end
@implementation ChildApplication @end
@interface WrongApplication : NSObject
- (BOOL)sendEvent:(id)event;
@end
@implementation WrongApplication
- (BOOL)sendEvent:(id)event { (void)event; abort(); }
@end

static void assertLifecycle(void) {
    ROSession *session=[ROSession new];
    UIWindow *window=[UIWindow new];
    MessageListFixtureChild *list=[MessageListFixtureChild new];
    UICollectionView *view=[UICollectionView new]; view.window=window; view.dataSource=list; view.delegate=list;
    list.viewIfLoaded=view; window.rootViewController=list;
    NSDictionary *graph=ROGraph(window,session);
    assert([graph[@"pageRole"] isEqual:@"message-list-candidate-not-verified-inbox"]);
    [session record:graph label:@"inactive" automatic:NO]; assert(session.stageCount==0);
    [session start];
    for(NSString *label in @[@"首页",@"实际收件箱",@"选择",@"原生筛选",@"取消后",@"自然刷新后"]) {
        NSUInteger before=session.stageCount;
        [session record:ROGraph(window,session) label:label automatic:NO];
        assert(session.stageCount==before+1);
    }
    [session record:ROGraph(window,session) label:@"duplicate" automatic:YES]; assert(session.stageCount==6);
    NSUInteger generation=session.generation; [session pause];
    [session record:graph label:@"probe-alert" automatic:NO]; assert(session.stageCount==6);
    assert(session.generation!=generation); [session resume];
    MailboxPickerFixtureChild *picker=[MailboxPickerFixtureChild new];
    UITableView *pickerView=[UITableView new]; picker.viewIfLoaded=pickerView; pickerView.window=window;
    list.presentedViewController=picker;
    NSDictionary *pickerGraph=ROGraph(window,session);
    assert([pickerGraph[@"pageRole"] isEqual:@"mailbox-picker-not-message-list"]);
    assert([pickerGraph[@"rootType"] isEqual:@"MailboxPickerFixtureChild"]);
    assert(![pickerGraph[@"types"] containsObject:@"MessageListFixtureChild"]);
    [session record:pickerGraph label:@"native-menu-cancel-only" automatic:NO];
    list.presentedViewController=nil;
    // Cycle and very large view tree remain bounded.
    NSMutableArray *children=[NSMutableArray array];
    for(int i=0;i<600;i++) [children addObject:[UIView new]];
    [children addObject:view]; view.subviews=children;
    NSDictionary *bounded=ROGraph(window,session);
    assert([bounded[@"nodes"] count]<=180 && [bounded[@"edges"] count]<=400);
    assert([bounded[@"graphTruncated"] boolValue]);
    for(int i=0;i<50;i++) [session record:bounded label:@"bounded" automatic:NO];
    assert(session.stageCount==24);
    [session stop]; [session record:graph label:@"share-sheet" automatic:NO]; assert(session.stageCount==24);
    NSDictionary *report=[session document:@"test"];
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:0 error:NULL]; assert(data && data.length<1536*1024);
    assert(!session.active);
    [session clear]; assert(session.stageCount==0 && !session.active);
    [session start]; assert(session.stageCount==0 && session.active && !session.paused);
    printf("PASS: six stage labels, explicit start/stop, pause/share exclusion, dedup, limits, picker not list\n");
}
static void assertMetadata(void) {
    NSDictionary *metadata=ROMetadata(@[@"MessageListFixtureChild"]);
    NSDictionary *classes=metadata[@"classes"], *protocols=metadata[@"protocols"];
    assert(classes[@"MessageListFixtureChild"] && classes[@"MessageListViewController"] && classes[@"UIViewController"] && classes[@"NSObject"]);
    assert(protocols[@"MailChildProtocol"] && protocols[@"MailParentProtocol"]);
    assert([protocols[@"MailChildProtocol"][@"parents"] containsObject:@"MailParentProtocol"]);
    BOOL found=NO;
    for(NSDictionary *m in classes[@"MessageListViewController"][@"instanceMethods"][@"declarations"])
        if([m[@"selector"] isEqual:@"senderAddress"]) found=YES;
    assert(found);
    printf("PASS: real production metadata inspects declarations/ancestors/protocols, never trap getters/actions\n");
}
static void assertObserver(void) {
    ROSession *session=[ROSession new];
    assert(!ROInstallObserver(WrongApplication.class,^(id owner,id event) { abort(); }));
    __block NSUInteger observed=0;
    assert(ROInstallObserver(ChildApplication.class,^(id owner,id event) {
        observed++; [session eventOwner:owner argument:event];
        if(observed==4) @throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];
    }));
    ChildApplication *app=[ChildApplication new]; SecretEvent *event=[SecretEvent new];
    [app sendEvent:event]; assert(originalCalls==1 && observed==1 && originalOwner==app && originalArgument==event);
    assert([[session document:@"test"][@"publicEventCalls"] count]==0);
    [session start]; [app sendEvent:event];
    assert(originalCalls==2 && observed==2 && originalOwner==app && originalArgument==event);
    assert([[session document:@"test"][@"publicEventCalls"] count]==1);
    [session pause]; [app sendEvent:event];
    NSDictionary *call=[[session document:@"test"][@"publicEventCalls"] firstObject]; assert([call[@"count"] unsignedIntegerValue]==1);
    [session stop]; [app sendEvent:event]; assert(originalCalls==4 && observed==4);
    FakeApplication *base=[FakeApplication new]; [base sendEvent:event]; assert(originalCalls==5 && observed==4);
    assert(!ROInstallObserver(ChildApplication.class,^(id owner,id value) { abort(); }));
    printf("PASS: exact ABI rejection; same owner/arg; original once; base untouched; exception contained; stopped does not collect\n");
}
int main(void) { @autoreleasepool { assertLifecycle(); assertMetadata(); assertObserver(); } return 0; }
