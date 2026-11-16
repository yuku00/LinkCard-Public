#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>
// Extracted verbatim from production by test_account_encoding.py.
#include "account_match.inc"
@interface AccountEncodingCenter : NSObject
+ (instancetype)defaultCenter;
+ (void)badReturn;
+ (id)badArgument:(id)value;
@end
@implementation AccountEncodingCenter
+ (instancetype)defaultCenter { return [self new]; }
+ (void)badReturn {}
+ (id)badArgument:(id)value { return value; }
@end
int main(void) { @autoreleasepool {
    Class c=AccountEncodingCenter.class;
    Method m=class_getClassMethod(c,@selector(defaultCenter));
    char *r=method_copyReturnType(m);
    assert(strcmp(r,@encode(id))==0); free(r);
    assert(method_getNumberOfArguments(m)==2);
    assert(Has(c,@"defaultCenter","@",@[]));
    assert(!Has(c,@"badReturn","@",@[]));
    assert(!Has(c,@"badArgument:","@",@[]));
    assert(!Has(c,@"missing","@",@[]));
    assert(!Has(nil,@"defaultCenter","@",@[]));
    puts("account runtime encoding checks: OK");
} return 0; }
