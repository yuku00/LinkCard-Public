#import "WU.h"
#import "WUCardPolicy.h"
#import <objc/message.h>
#import <objc/runtime.h>

static IMP cardOriginal;
static BOOL cardReady;
static char cardBusy;
static BOOL Has(id obj, NSString *name, const char *ret, NSArray *args) {
    return obj && WUMatches(class_getInstanceMethod(object_getClass(obj), NSSelectorFromString(name)), ret, args);
}
static void CardJump(id service, SEL sel, id from, id session) {
    if (!WUEnabled(@"cardDirect") || !NSThread.isMainThread || object_getClass(from)!=NSClassFromString(@"MoreViewController") || ![from isKindOfClass:UIViewController.class]) {
        ((void(*)(id,SEL,id,id))cardOriginal)(service,sel,from,session); return;
    }
    UIViewController *vc=from; UINavigationController *nav=vc.navigationController;
    Class route=NSClassFromString(@"MMUIRouteRegistry"); SEL open=NSSelectorFromString(@"openLegacyCardHomePageWithNavigationController:");
    if (nav && objc_getAssociatedObject(nav,&cardBusy)) return;
    if (!vc.isViewLoaded || !vc.view.window || !nav || nav.topViewController!=vc || vc.presentedViewController || nav.transitionCoordinator || !Has(route,NSStringFromSelector(open),@encode(BOOL),@[@"@"])) {
        ((void(*)(id,SEL,id,id))cardOriginal)(service,sel,from,session); return;
    }
    NSArray *before=[nav.viewControllers copy]; BOOL handled=NO, attempted=NO;
    objc_setAssociatedObject(nav,&cardBusy,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        attempted=YES;
        handled=((BOOL(*)(id,SEL,id))objc_msgSend)(route,open,nav);
    } @catch (NSException *e) {
        // Once invoked, an exception does not prove that navigation was not scheduled.
        handled=YES;
    } @finally { objc_setAssociatedObject(nav,&cardBusy,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if (WUCardShouldFallback(attempted,handled,[nav.viewControllers isEqualToArray:before],vc.presentedViewController!=nil,nav.transitionCoordinator!=nil))
        ((void(*)(id,SEL,id,id))cardOriginal)(service,sel,from,session);
}
void WUInstallCardDirect(void) {
    Class route=NSClassFromString(@"MMUIRouteRegistry");
    cardReady=Has(route,@"openLegacyCardHomePageWithNavigationController:",@encode(BOOL),@[@"@"]) && NSClassFromString(@"MoreViewController") &&
        WUHook(@"EcsOrderService",@"jumpOrderAndCardCenterFromVc:clickSessionId:",NO,"v",@[@"@",@"@"],(IMP)CardJump,&cardOriginal) && cardOriginal;
}
BOOL WUCardDirectAvailable(void) { return cardReady; }
