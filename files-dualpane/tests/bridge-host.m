#import <Foundation/Foundation.h>
#include <assert.h>
static void (^scheduled)(void);
static void schedule(void (^block)(void)) { assert(!scheduled); scheduled=[block copy]; }
#define dispatch_after(t,q,b) schedule(b)
#define dispatch_time(a,b) 0
#define dispatch_get_main_queue() 0
#undef DISPATCH_TIME_NOW
#undef NSEC_PER_SEC
#define DISPATCH_TIME_NOW 0
#define NSEC_PER_SEC 1000000000
#define UIModalPresentationFormSheet 2
@interface TestView : NSObject
@property(nonatomic,strong) id window;
@end
@implementation TestView @end
@interface TestItem : NSObject
@property(nonatomic) BOOL enabled;
@end
@implementation TestItem @end
@interface TestNavigation : NSObject
@property(nonatomic,strong) TestItem *rightBarButtonItem;
@end
@implementation TestNavigation @end
@class UINavigationController;
@interface UIViewController : NSObject
@property(nonatomic,strong) TestView *viewIfLoaded;
@property(nonatomic,weak) UIViewController *presentingViewController;
@property(nonatomic,strong) UIViewController *presentedViewController;
@property(nonatomic,strong) id transitionCoordinator;
@property(nonatomic) BOOL isBeingDismissed;
@property(nonatomic,weak) UINavigationController *navigationController;
@property(nonatomic,strong) TestNavigation *navigationItem;
@property(nonatomic) NSInteger modalPresentationStyle;
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void(^)(void))completion;
@end
static int presentations, snapshots, failures;
static BOOL FPBridgeCaptured, FPBridgeBusy, failSnapshot, throwSnapshot;
static void (^presentationCompletion)(void);
@implementation UIViewController
- (instancetype)init { if((self=[super init])) { self.viewIfLoaded=[TestView new]; self.navigationItem=[TestNavigation new]; self.navigationItem.rightBarButtonItem=[TestItem new]; self.navigationItem.rightBarButtonItem.enabled=YES; } return self; }
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void(^)(void))completion {
    assert(self.viewIfLoaded.window); assert(!self.presentedViewController); assert(!self.transitionCoordinator);
    presentations++; self.presentedViewController=vc; vc.presentingViewController=self;
    vc.viewIfLoaded.window=self.viewIfLoaded.window; presentationCompletion=[completion copy];
}
@end
@interface UIAlertController : UIViewController @end
@implementation UIAlertController @end
@interface FPDualContainer : UIViewController
@property(nonatomic) BOOL closing;
@property(nonatomic,strong) id paneState;
@end
@implementation FPDualContainer @end
@interface FPBridgeReport : UIViewController
@property(nonatomic,copy) NSString *text;
@end
@implementation FPBridgeReport @end
@interface UINavigationController : UIViewController
@property(nonatomic,strong) UIViewController *root;
- (instancetype)initWithRootViewController:(UIViewController *)root;
@end
@implementation UINavigationController
- (instancetype)initWithRootViewController:(UIViewController *)root { if((self=[super init])) self.root=root; return self; }
@end
static NSString *FPBridgeSnapshot(FPDualContainer *container) {
    assert(container.viewIfLoaded.window && !container.presentedViewController);
    snapshots++;
    if(throwSnapshot) @throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];
    return failSnapshot ? nil : @"anonymous fixture";
}
static void FPBridgeFailure(FPDualContainer *container) { failures++; FPBridgeBusy=NO; }
/* PRODUCTION */
static void tick(void) { void (^block)(void)=scheduled; scheduled=nil; assert(block); block(); }
static void finishPresentation(void) { void (^block)(void)=presentationCompletion; presentationCompletion=nil; assert(block); block(); }
static FPDualContainer *host(void) { FPDualContainer *h=[FPDualContainer new]; h.viewIfLoaded.window=[NSObject new]; h.paneState=[NSObject new]; return h; }
int main(void) { @autoreleasepool {
    FPDualContainer *h=host(); id originalState=h.paneState;
    UIAlertController *a=[UIAlertController new]; a.viewIfLoaded.window=h.viewIfLoaded.window;
    a.presentingViewController=h; h.presentedViewController=a; FPBridgeBusy=YES;
    FPBridgeAfterAlert(h,a,60);
    assert(snapshots==0 && presentations==0 && scheduled && !FPBridgeCaptured);
    a.viewIfLoaded.window=nil; tick(); // Relationship still attached: do not present.
    assert(snapshots==0 && scheduled);
    a.presentingViewController=nil; h.presentedViewController=nil;
    h.transitionCoordinator=[NSObject new]; tick(); assert(snapshots==0 && scheduled);
    h.transitionCoordinator=nil; tick();
    assert(snapshots==1 && presentations==1 && !FPBridgeCaptured);
    assert(h.navigationItem.rightBarButtonItem.enabled && h.paneState==originalState && !h.closing);
    finishPresentation(); assert(FPBridgeCaptured && !FPBridgeBusy && !h.navigationItem.rightBarButtonItem.enabled);
    FPBridgeReport *report=(id)[(UINavigationController *)h.presentedViewController root];
    assert([report.text isEqualToString:@"anonymous fixture"]);
    h=host(); FPBridgeCaptured=NO; FPBridgeBusy=YES; failSnapshot=YES;
    FPBridgeAfterAlert(h,a,60); assert(failures==1 && !FPBridgeBusy && !FPBridgeCaptured && h.navigationItem.rightBarButtonItem.enabled);
    failSnapshot=NO; FPBridgeBusy=YES; FPBridgeAfterAlert(h,a,60); finishPresentation(); assert(FPBridgeCaptured);
    h=host(); FPBridgeCaptured=NO; FPBridgeBusy=YES; throwSnapshot=YES;
    FPBridgeAfterAlert(h,a,60); assert(failures==2 && !FPBridgeCaptured && !FPBridgeBusy); throwSnapshot=NO;
    h=host(); h.viewIfLoaded.window=nil; int before=snapshots;
    FPBridgeAfterAlert(h,a,60); assert(failures==3 && snapshots==before);
    h=host(); a.viewIfLoaded.window=h.viewIfLoaded.window;
    FPBridgeAfterAlert(h,a,0); assert(failures==4 && snapshots==before && !FPBridgeCaptured);
    a.viewIfLoaded.window=nil;
    __weak FPDualContainer *retained;
    @autoreleasepool {
        FPDualContainer *local=host(); retained=local; a.viewIfLoaded.window=local.viewIfLoaded.window;
        FPBridgeAfterAlert(local,a,60); local=nil;
        assert(retained); a.viewIfLoaded.window=nil; tick(); assert(retained);
        finishPresentation();
    }
    assert(!retained);
    puts("PASS production bridge gate: alert off-window AND detached, transition complete, attached host, presentation success consumes once, failure retries, state and async lifetime preserved");
} return 0; }
