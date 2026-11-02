#import "WU.h"
#import "AdsLogic.h"
#import "WUMiniAds.h"
static IMP momentsValid, splashWindow, splashHot;
static BOOL momentsReady, splashWindowReady, splashHotReady;
BOOL WUAdsAvailable(NSString *key) {
    if([key isEqual:@"momentsAds"]) return momentsReady && NSClassFromString(@"WCDataItem")!=Nil;
    if([key isEqual:@"miniSplashAds"]) return splashWindowReady && splashHotReady;
    return WUMiniAdsAvailable(key);
}
static BOOL MomentsValid(id o,SEL s,id ad,id item) {
    BOOL original=((BOOL(*)(id,SEL,id,id))momentsValid)(o,s,ad,item);
    return WUMomentsAdResult(original,WUEnabled(@"momentsAds"),ad,item);
}
static BOOL SplashWindow(id o,SEL s) {
    BOOL original=((BOOL(*)(id,SEL))splashWindow)(o,s);
    return WUSplashAdResult(original,WUAdsAvailable(@"miniSplashAds") && WUEnabled(@"miniSplashAds"));
}
static BOOL SplashHot(id o,SEL s) {
    BOOL original=((BOOL(*)(id,SEL))splashHot)(o,s);
    return WUSplashAdResult(original,WUAdsAvailable(@"miniSplashAds") && WUEnabled(@"miniSplashAds"));
}
static IMP notShow, enableAd, canvasRequest, canvasCard, plugins;
static BOOL NoAd(id o,SEL s) { return WUEnabled(@"ads") ? YES : ((BOOL(*)(id,SEL))notShow)(o,s); }
static BOOL Enable(id o,SEL s) { return WUEnabled(@"ads") ? NO : ((BOOL(*)(id,SEL))enableAd)(o,s); }
static BOOL Request(id o,SEL s) { return WUEnabled(@"ads") ? NO : ((BOOL(*)(id,SEL))canvasRequest)(o,s); }
static BOOL Card(id o,SEL s) { return WUEnabled(@"ads") ? NO : ((BOOL(*)(id,SEL))canvasCard)(o,s); }
static id Plugins(id o,SEL s) {
    id result=((id(*)(id,SEL))plugins)(o,s);
    if(!WUEnabled(@"ads") || ![result isKindOfClass:NSArray.class]) return result;
    NSMutableArray *out=[NSMutableArray array];
    for(id item in result) if(![NSStringFromClass([item class]) containsString:@"MagicSclBrandAdFlutterPlugin"]) [out addObject:item];
    return [out copy];
}
void WUInstallAds(void) {
    WUInstallMiniAds();
    // Dedicated validation only: no storage, push, serialization or normal feed interception.
    momentsReady=WUHook(@"WCAdvertiseDataHelper",@"IsAdvertiseDataValid:dataItem:",NO,@encode(BOOL),@[@"@",@"@"],(IMP)MomentsValid,&momentsValid);
    // Preserve all JS callbacks, content state and reward paths. Both gates must be present.
    splashWindowReady=WUHook(@"WAAppTaskSplashADConfig",@"canShowSplashADWindow",NO,@encode(BOOL),@[],(IMP)SplashWindow,&splashWindow);
    splashHotReady=WUHook(@"WAAppTaskSplashADConfig",@"canHotStartShowSplashAD",NO,@encode(BOOL),@[],(IMP)SplashHot,&splashHot);
    WUHook(@"BrandTLExptConfig",@"isExptNotShowAd",NO,@encode(BOOL),@[],(IMP)NoAd,&notShow);
    WUHook(@"BrandTLFlutterViewController",@"enableAd",NO,@encode(BOOL),@[],(IMP)Enable,&enableAd);
    WUHook(@"BrandTLCanvasCardMgr",@"isAdRequestOpen",YES,@encode(BOOL),@[],(IMP)Request,&canvasRequest);
    WUHook(@"BrandTLCanvasCardMgr",@"isAdCardOpen",YES,@encode(BOOL),@[],(IMP)Card,&canvasCard);
    WUHook(@"BrandTLFlutterViewController",@"getMagicBrushFlutterPlugins",NO,"@",@[],(IMP)Plugins,&plugins);
}
