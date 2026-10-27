// Host-side executable test of the exact production MRC wrappers, not Files classes.
#import "../LifecycleTrace.m"
#include <assert.h>
static unsigned destroyed, called;
@interface FPFixture : NSObject
- (id)initSame;
- (id)initNil;
- (id)initReplacement;
- (id)initUnsigned:(unsigned long long)n host:(id)host;
- (id)value;
@end
@implementation FPFixture
- (id)initSame { called++; return [super init]; }
- (id)initNil { called++; [self release]; return nil; }
- (id)initReplacement { called++; [self release]; return (id)[[NSObject alloc] init]; }
- (id)initUnsigned:(unsigned long long)n host:(id)host { assert(n==42 && host==nil); called++; return [super init]; }
- (id)value { called++; return self; }
- (void)dealloc { destroyed++; [super dealloc]; }
@end
int main(void) {
 @autoreleasepool {
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    secondsPerTick=(double)tb.numer/tb.denom/1e9; startTicks=mach_absolute_time();
    Method m=class_getInstanceMethod([FPFixture class],@selector(initUnsigned:host:));
    assert(matches(m,"@@:Q@")); assert(!matches(m,"@@:q@")); assert(!matches(m,"@@:@@"));
    hook("FPFixture","initSame","@@:");
    hook("FPFixture","initNil","@@:");
    hook("FPFixture","initReplacement","@@:");
    hook("FPFixture","initUnsigned:host:","@@:Q@");
    hook("FPFixture","value","@@:");
    hook("FPFixture","dealloc","v@:");
    // Fixture initializer names are not the production no-argument init selector.
    for(unsigned i=0;i<3;i++) hooks[i].sampled=NO;
    for(unsigned i=0;i<hnum;i++) assert(!strcmp(hooks[i].state,"INSTALLED"));
    atomic_store(&enabled,true);
    FPFixture *raw=[FPFixture alloc]; FPFixture *same=[raw initSame];
    assert(same==raw && called==1 && destroyed==0);
    [same release]; assert(destroyed==1);
    assert([[FPFixture alloc] initNil]==nil); assert(called==2 && destroyed==2);
    id replacement=[[FPFixture alloc] initReplacement];
    assert(replacement && object_getClass(replacement)==[NSObject class]);
    assert(called==3 && destroyed==3); [replacement release];
    FPFixture *f=[[FPFixture alloc] initUnsigned:42 host:nil]; assert(called==4);
    unsigned before=enum_;
    for(unsigned i=0;i<10000;i++) assert([f value]==f);
    assert(called==10004 && enum_-before==32 && atomic_load(&hooks[4].hits)==10000);
    [f release]; assert(destroyed==4);
    unsigned critical=enum_; assert([[FPFixture alloc] initNil]==nil);
    assert(enum_>critical && destroyed==5); // Getter storm did not consume lifecycle budget.
    FPLifecycleStop(); unsigned stopped=enum_;
    assert([[FPFixture alloc] initNil]==nil); assert(enum_==stopped && destroyed==6);
    NSString *report=FPLifecycleReport(); assert([report containsString:@"sampledGetter=1"]);
    assert([report containsString:@"TARGETED_CONTRACT_METADATA"]);
    puts("PASS real MRC wrappers: self/nil/replacement ownership, dealloc, Q versus q, single original call, getter budget, stop/export");
 }
 return 0;
}
