#import "WU.h"
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
    WUHook(@"BrandTLExptConfig",@"isExptNotShowAd",NO,@encode(BOOL),@[],(IMP)NoAd,&notShow);
    WUHook(@"BrandTLFlutterViewController",@"enableAd",NO,@encode(BOOL),@[],(IMP)Enable,&enableAd);
    WUHook(@"BrandTLCanvasCardMgr",@"isAdRequestOpen",YES,@encode(BOOL),@[],(IMP)Request,&canvasRequest);
    WUHook(@"BrandTLCanvasCardMgr",@"isAdCardOpen",YES,@encode(BOOL),@[],(IMP)Card,&canvasCard);
    WUHook(@"BrandTLFlutterViewController",@"getMagicBrushFlutterPlugins",NO,"@",@[],(IMP)Plugins,&plugins);
}
