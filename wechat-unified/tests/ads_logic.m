#import <Foundation/Foundation.h>
#import "AdsLogic.h"
#include <assert.h>
@interface WCDataItem : NSObject @end
@implementation WCDataItem @end
@interface OtherItem : WCDataItem @end
@implementation OtherItem @end
int main(void) { @autoreleasepool {
    id ad=[NSObject new], item=[WCDataItem new];
    assert(!WUMomentsAdResult(YES,YES,ad,item));
    assert(WUMomentsAdResult(YES,NO,ad,item));
    assert(!WUMomentsAdResult(NO,NO,ad,item));
    assert(!WUMomentsAdResult(NO,YES,ad,item));
    assert(WUMomentsAdResult(YES,YES,nil,item));
    assert(WUMomentsAdResult(YES,YES,ad,nil));
    assert(WUMomentsAdResult(YES,YES,ad,[NSObject new]));
    assert(WUMomentsAdResult(YES,YES,ad,[OtherItem new]));
    assert(WUMomentsAdResult(YES,YES,ad,@{@"isAd":@YES}));
    assert(WUMomentsAdResult(YES,YES,ad,@"advertisement reward"));
    assert(!WUSplashAdResult(YES,YES));
    assert(!WUSplashAdResult(NO,YES));
    assert(WUSplashAdResult(YES,NO));
    assert(!WUSplashAdResult(NO,NO));
    puts("AdsLogic: 14 assertions passed");
} return 0; }
