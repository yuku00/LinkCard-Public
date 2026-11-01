#import <Foundation/Foundation.h>
#import "InteractionLogic.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSUInteger checks=0;
    for(NSUInteger bits=0;bits<64;bits++) {
        BOOL border=bits&1,pulse=bits&2,visible=bits&4,editing=bits&8,active=bits&16,reduced=bits&32;
        NSUInteger result=WUInputEffect(border,pulse,visible,editing,active,reduced);
        NSUInteger expected=(!visible || !active)?0:((pulse && editing && !reduced)?2:(border?1:0));
        assert(result==expected); checks++;
    }
    // Same view reused/detached, edit ended, switch disabled, background and Reduce Motion.
    assert(WUInputEffect(NO,YES,YES,YES,YES,NO)==2);
    assert(WUInputEffect(NO,YES,NO,YES,YES,NO)==0);
    assert(WUInputEffect(NO,YES,YES,NO,YES,NO)==0);
    assert(WUInputEffect(NO,NO,YES,YES,YES,NO)==0);
    assert(WUInputEffect(NO,YES,YES,YES,NO,NO)==0);
    assert(WUInputEffect(NO,YES,YES,YES,YES,YES)==0);
    assert(WUInputEffect(YES,YES,YES,YES,YES,YES)==1); checks+=7;
    assert([WUCardRole(47,nil) isEqual:@"emoticonSurface"]);
    NSString *file=@"<msg><appmsg><title>发送</title><type>6</type><appattach/></appmsg></msg>";
    assert([WUCardRole(49,file) isEqual:@"fileSurface"]);
    assert(!WUCardRole(1,file)); assert(!WUCardRole(34,file));
    assert([WUCardRole(49,@"<msg><appmsg><type><![CDATA[ 6 ]]></type></appmsg></msg>") isEqual:@"fileSurface"]); checks+=5;
    for(NSString *bad in @[@"",@"发送",@"<msg><appmsg><title>文件</title><type>5</type></appmsg></msg>",@"<msg><appmsg><type>2001</type></appmsg></msg>",@"<msg><appmsg><type>06</type></appmsg></msg>",@"<msg><appmsg><type><b>6</b></type></appmsg></msg>",@"<msg><appmsg><type>6</type><type>6</type></appmsg></msg>",@"<msg><appmsg/><appmsg><type>6</type></appmsg></msg>",@"<msg><type>6</type></msg>",@"<msg><appmsg><type>6</type>",@"<!DOCTYPE msg [<!ENTITY a '6'>]><msg><appmsg><type>&a;</type></appmsg></msg>"]) { assert(!WUCardRole(49,bad)); checks++; }
    assert(!WUCardRole(49,(id)@6)); assert(!WUCardRole(49,[file stringByPaddingToLength:65537 withString:@" " startingAtIndex:0])); checks+=2;
    // Disable/reuse restores our values only; host relayout writes become the new baseline.
    assert(WUSurfaceValueOwned(@14,@14)); assert(!WUSurfaceValueOwned(@8,@14));
    assert(WUSurfaceValueOwned(NSNull.null,NSNull.null)); assert(!WUSurfaceValueOwned(@"dark",@"light"));
    assert(!WUSurfaceValueOwned(@YES,nil)); checks+=5;
    printf("interaction production policy: %lu assertions passed\n",(unsigned long)checks);
} return 0; }
