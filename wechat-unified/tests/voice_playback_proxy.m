#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <string.h>
#include <stdlib.h>
static BOOL WUMatches(Method m,const char *ret,NSArray *args) {
    if(!m || method_getNumberOfArguments(m)!=args.count+2) return NO;
    char *r=method_copyReturnType(m); BOOL ok=r && !strcmp(r,ret); free(r);
    for(NSUInteger i=0;i<args.count;i++) { char *a=method_copyArgumentType(m,(unsigned)i+2); ok=ok && a && !strcmp(a,[args[i] UTF8String]); free(a); }
    return ok;
}
#include "voice_signature.inc"
@interface MsgPlayingFacade : NSObject
- (unsigned)currentPlayTime;
- (void)seekToTime:(unsigned)n;
@end
@implementation MsgPlayingFacade
- (unsigned)currentPlayTime { return 42; }
- (void)seekToTime:(unsigned)n { (void)n; }
@end
@interface PlaybackProxy : NSProxy
@property(nonatomic,strong) MsgPlayingFacade *target;
@property(nonatomic) BOOL bad;
@end
@implementation PlaybackProxy
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s {
    if(self.bad && s==@selector(currentPlayTime)) return [NSMethodSignature signatureWithObjCTypes:"Q@:"];
    return [self.target methodSignatureForSelector:s];
}
- (void)forwardInvocation:(NSInvocation *)inv { [inv invokeWithTarget:self.target]; }
@end
#define CHECK(x) do { if(!(x)) abort(); } while(0)
int main(void) { @autoreleasepool {
    MsgPlayingFacade *host=[MsgPlayingFacade new];
    CHECK(Signature(host,@"currentPlayTime","I",@[]));
    CHECK(Signature(host,@"seekToTime:","v",@[@"I"]));
    PlaybackProxy *proxy=[PlaybackProxy alloc]; proxy.target=host;
    CHECK(Signature(proxy,@"currentPlayTime","I",@[]));
    CHECK(Signature(proxy,@"seekToTime:","v",@[@"I"]));
    CHECK(!Signature(proxy,@"seekToTime:","v",@[@"Q"]));
    CHECK(!Signature(proxy,@"missingSelector","@",@[]));
    proxy.bad=YES; CHECK(!Signature(proxy,@"currentPlayTime","I",@[]));
    puts("PASS: playback entity/proxy signature mocks");
} return 0; }
