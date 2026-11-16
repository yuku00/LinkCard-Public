#import "WU.h"
#import "WUCardPolicy.h"
#import <objc/message.h>
#import <objc/runtime.h>

static IMP cardOriginal, cardsEntryOriginal;
static BOOL cardReady;
static char cardBusy;
static BOOL Has(id obj, NSString *name, const char *ret, NSArray *args) {
    return obj && WUMatches(class_getInstanceMethod(object_getClass(obj), NSSelectorFromString(name)), ret, args);
}
static int RouteKind(Class route) {
    return WUCardRouteKind(Has(route,@"openLegacyCardHomePageWithNavigationController:","v",@[@"@"]),
                           Has(route,@"openLegacyCardHomePageWithNavigationController:",@encode(BOOL),@[@"@"]));
}
static BOOL TryCardRoute(UIViewController *vc) {
    if (!WUEnabled(@"cardDirect") || !NSThread.isMainThread || ![vc isKindOfClass:NSClassFromString(@"MoreViewController")]) return NO;
    UINavigationController *nav=vc.navigationController;
    Class route=NSClassFromString(@"MMUIRouteRegistry"); SEL open=NSSelectorFromString(@"openLegacyCardHomePageWithNavigationController:");
    if (nav && objc_getAssociatedObject(nav,&cardBusy)) return YES;
    int routeKind=RouteKind(route);
    if (!vc.isViewLoaded || !vc.view.window || !nav || nav.topViewController!=vc || vc.presentedViewController || nav.transitionCoordinator || !routeKind) return NO;
    NSArray *before=[nav.viewControllers copy]; BOOL handled=NO, attempted=NO;
    objc_setAssociatedObject(nav,&cardBusy,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        attempted=YES;
        if(routeKind==1) ((void(*)(id,SEL,id))objc_msgSend)(route,open,nav);
        else handled=((BOOL(*)(id,SEL,id))objc_msgSend)(route,open,nav);
    } @catch (NSException *e) {
        // Once invoked, an exception does not prove that navigation was not scheduled.
        handled=YES;
    } @finally { objc_setAssociatedObject(nav,&cardBusy,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return !WUCardShouldFallback(attempted,handled,[nav.viewControllers isEqualToArray:before],vc.presentedViewController!=nil,nav.transitionCoordinator!=nil);
}
static void CardJump(id service, SEL sel, id from, id session) {
    if (![from isKindOfClass:UIViewController.class] || !TryCardRoute(from)) ((void(*)(id,SEL,id,id))cardOriginal)(service,sel,from,session);
}
static void CardsEntry(id vc, SEL sel) {
    if (!TryCardRoute(vc)) ((void(*)(id,SEL))cardsEntryOriginal)(vc,sel);
}
void WUInstallCardDirect(void) {
    Class route=NSClassFromString(@"MMUIRouteRegistry");
    if (!RouteKind(route) || !NSClassFromString(@"MoreViewController")) { cardReady=NO; return; }
    BOOL service=WUHook(@"EcsOrderService",@"jumpOrderAndCardCenterFromVc:clickSessionId:",NO,"v",@[@"@",@"@"],(IMP)CardJump,&cardOriginal) && cardOriginal;
    BOOL entry=WUHook(@"MoreViewController",@"onCardsEntryClicked",NO,"v",@[],(IMP)CardsEntry,&cardsEntryOriginal) && cardsEntryOriginal;
    cardReady=service || entry;
}
BOOL WUCardDirectAvailable(void) { return cardReady; }
