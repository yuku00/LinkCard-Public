#import "WUNative.h"
#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <limits.h>
static BOOL invalidMD5;
BOOL WUMatches(Method m,const char *ret,NSArray *args) {
    if(!m || method_getNumberOfArguments(m)!=args.count+2) return NO;
    char *r=method_copyReturnType(m); BOOL ok=!strcmp(r,ret); free(r);
    for(unsigned i=0;ok && i<args.count;i++){char *a=method_copyArgumentType(m,i+2);ok=!strcmp(a,[args[i] UTF8String]);free(a);}return ok;
}
@interface GameController : NSObject + (NSString *)getMD5ByGameContent:(unsigned long long)n; @end
@implementation GameController
+ (NSString *)getMD5ByGameContent:(unsigned long long)n { return invalidMD5?@"not-an-md5":[NSString stringWithFormat:@"%032llx",n]; }
@end
@interface Wrap32 : NSObject
@property(nonatomic) unsigned m_uiMessageType;
@property(nonatomic) unsigned m_uiGameType;
@property(nonatomic) unsigned m_uiGameContent;
@property(nonatomic,copy) NSString *m_nsEmoticonMD5;
@end
@implementation Wrap32 @end
@interface Wrap64 : NSObject
@property(nonatomic) unsigned long long m_uiMessageType;
@property(nonatomic) unsigned long long m_uiGameType;
@property(nonatomic) unsigned long long m_uiGameContent;
@property(nonatomic,copy) NSString *m_nsEmoticonMD5;
@end
@implementation Wrap64 @end
@interface WrongWidth : NSObject - (double)m_uiGameType; @end
@implementation WrongWidth - (double)m_uiGameType {return 1;} @end
int main(void) { @autoreleasepool {
    Wrap32 *a=[Wrap32 new]; a.m_uiMessageType=47; a.m_uiGameType=1;
    for(unsigned i=0;i<3;i++){assert(WUNativeApplyGameChoice(a,1,i)); assert(a.m_uiGameContent==i+1); assert([a.m_nsEmoticonMD5 isEqual:[GameController getMD5ByGameContent:i+1]]);}
    Wrap64 *b=[Wrap64 new]; b.m_uiMessageType=47; b.m_uiGameType=2;
    for(unsigned i=0;i<6;i++){assert(WUNativeApplyGameChoice(b,2,i)); assert(b.m_uiGameContent==i+4);}
    NSString *before=a.m_nsEmoticonMD5; unsigned content=a.m_uiGameContent;
    invalidMD5=YES; assert(!WUNativeApplyGameChoice(a,1,0)); assert(a.m_uiGameContent==content && [a.m_nsEmoticonMD5 isEqual:before]); invalidMD5=NO;
    assert(!WUNativeApplyGameChoice(a,1,3)); assert(!WUNativeApplyGameChoice(b,2,6));
    assert(!WUNativeApplyGameChoice(a,2,0)); a.m_uiMessageType=1; assert(!WUNativeApplyGameChoice(a,1,0));
    b.m_uiGameType=ULLONG_MAX; assert(WUNativeGameNumber(b,@"m_uiGameType")==UINT_MAX);
    assert(WUNativeGameNumber([WrongWidth new],@"m_uiGameType")==UINT_MAX);
    assert(!WUNativeApplyGameChoice(nil,1,0));
    puts("native production game adapter: nine contents, I/Q ABI, md5 validation, mismatch and overflow PASS");
} return 0; }
