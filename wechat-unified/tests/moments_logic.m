#import <Foundation/Foundation.h>
#import "MomentsLogic.h"
#import "GroupLogic.h"
#include <assert.h>
#include <math.h>
int main(void) { @autoreleasepool {
    assert(WUMomentsCommand(@"rp",NO,YES,YES));
    assert(!WUMomentsCommand(@"rpx",NO,YES,YES));
    assert(!WUMomentsCommand(@"hello rp",NO,YES,YES));
    assert(!WUMomentsCommand(@"RP",NO,YES,YES));
    assert(!WUMomentsCommand(@"rp\n",NO,YES,YES));
    assert(!WUMomentsCommand(@" rp",NO,YES,YES));
    assert(!WUMomentsCommand(@"",NO,YES,YES));
    assert(!WUMomentsCommand(nil,NO,YES,YES));
    assert(!WUMomentsCommand(@"rp",YES,YES,YES));
    assert(!WUMomentsCommand(@"rp",NO,NO,YES));
    assert(!WUMomentsCommand(@"rp",NO,YES,NO));
    assert(WUMomentsContext(@"a",@"chat",7,@"a",@"chat",7,YES,YES));
    assert(!WUMomentsContext(@"a",@"chat",7,@"b",@"chat",7,YES,YES));
    assert(!WUMomentsContext(@"a",@"chat",7,@"a",@"other",7,YES,YES));
    assert(!WUMomentsContext(@"a",@"chat",7,@"a",@"chat",8,YES,YES));
    assert(!WUMomentsContext(@"a",@"chat",7,@"a",@"chat",7,NO,YES));
    assert(!WUMomentsContext(@"a",@"chat",7,@"a",@"chat",7,YES,NO));
    assert(!WUMomentsContext(nil,@"chat",7,nil,@"chat",7,YES,YES));
    assert(!WUMomentsContext(@"a",@"",7,@"a",@"",7,YES,YES));
    assert(WUMomentsHeight(844)==422);
    assert(WUMomentsHeight(390)==195);
    assert(WUMomentsHeight(843)==421);
    assert(WUMomentsHeight(0)==0);
    assert(WUMomentsHeight(-10)==0);
    assert(WUMomentsHeight(NAN)==0);
    assert(WUMomentsHeight(INFINITY)==0);
    assert(([WUToolbarActions(@[@"moments",@"stats",@"moments",@"unknown"]) isEqual:@[@"moments",@"stats"]]));
    assert(WUToolbarActions(nil).count==0);
    assert(WUValidAccountOptions(@{@"a":@{@"toolbar":@[@"moments"]}}));
    puts("MomentsLogic: 29 assertions passed (exact command, marked text, ownership, context cancellation, half geometry, toolbar)");
} return 0; }
