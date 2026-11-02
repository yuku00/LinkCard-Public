#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>
static NSMutableDictionary *hooks;
static BOOL permitted=YES;
static unsigned registrations;
BOOL WUNativeGuardAllowsHooks(void) { return permitted; }
void WUNativeRecordHook(Class c,SEL s,IMP replacement,IMP *original) { assert(c && s && replacement && original && *original); registrations++; }
#include "hook_ownership_core.inc"
@interface WUOwnerParent : NSObject
- (int)value;
@end
@implementation WUOwnerParent
- (int)value { return 4; }
@end
@interface WUOwnerChild : WUOwnerParent @end
@implementation WUOwnerChild @end
@interface WUOwnerPhantom : WUOwnerParent @end
@implementation WUOwnerPhantom @end
static IMP saved;
static int Added(id o,SEL s) { return ((int(*)(id,SEL))saved)(o,s)+1; }
static int Other(id o,SEL s) { return 90; }
int main(void) { @autoreleasepool {
    hooks=[NSMutableDictionary dictionary];
    assert(!WUHook(@"WUOwnerChild",@"value",NO,"i",@[],(IMP)Added,NULL));
    assert(WUHook(@"WUOwnerChild",@"value",NO,"i",@[],(IMP)Added,&saved));
    IMP original=saved; assert(registrations==1 && [[WUOwnerChild new] value]==5 && [[WUOwnerParent new] value]==4);
    assert(WUHook(@"WUOwnerChild",@"value",NO,"i",@[],(IMP)Added,&saved) && saved==original && registrations==1);
    IMP competing=NULL;
    assert(!WUHook(@"WUOwnerChild",@"value",NO,"i",@[],(IMP)Added,&competing) && !competing);
    assert(!WUHook(@"WUOwnerChild",@"value",NO,"i",@[],(IMP)Other,&competing) && !competing);
    assert(!WUHook(@"WUOwnerChild",@"value",NO,"v",@[],(IMP)Added,&saved) && saved==original);
    assert([[WUOwnerChild new] value]==5);
    Method m=class_getInstanceMethod(WUOwnerChild.class,@selector(value)); method_setImplementation(m,(IMP)Other);
    assert(!WUHook(@"WUOwnerChild",@"value",NO,"i",@[],(IMP)Added,&saved));
    assert(!WUHook(@"WUOwnerChild",@"value",NO,"i",@[],(IMP)Added,&saved));
    assert([[WUOwnerChild new] value]==90 && saved==original && registrations==1);
    hooks[@"-WUOwnerPhantom value"]=@"installed";
    assert(!WUHook(@"WUOwnerPhantom",@"value",NO,"i",@[],(IMP)Added,&competing) && !competing);
    assert([[WUOwnerPhantom new] value]==4);
    permitted=NO; assert(!WUHook(@"WUOwnerParent",@"value",NO,"i",@[],(IMP)Other,&competing));
    assert([[WUOwnerParent new] value]==4 && registrations==1);
    puts("PASS actual production WUHook ownership: idempotence, distinct slot/replacement refusal, inherited safety, stale/foreign preservation and startup gate");
} return 0; }
