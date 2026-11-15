#include "WUMenuSignature.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(WUMenuFilterSignatureMatches(3,"@","@",":","@"));
    assert(!WUMenuFilterSignatureMatches(2,"@","@",":","@"));
    assert(!WUMenuFilterSignatureMatches(4,"@","@",":","@"));
    assert(!WUMenuFilterSignatureMatches(3,"v","@",":","@"));
    assert(!WUMenuFilterSignatureMatches(3,"@","@",":","@?"));
    assert(!WUMenuFilterSignatureMatches(3,"@","@",":","^v"));
    assert(!WUMenuFilterSignatureMatches(3,"@","@","@","@"));
    assert(!WUMenuFilterSignatureMatches(3,NULL,"@",":","@"));
    assert(!WUMenuFilterSignatureMatches(3,"@",NULL,":","@"));
    assert(!WUMenuFilterSignatureMatches(3,"@","@",":",NULL));
    assert(WUMenuInitializerSignatureMatches(5,"@","@",":","@","@",":"));
    assert(!WUMenuInitializerSignatureMatches(4,"@","@",":","@","@",":"));
    assert(!WUMenuInitializerSignatureMatches(6,"@","@",":","@","@",":"));
    assert(!WUMenuInitializerSignatureMatches(5,"v","@",":","@","@",":"));
    assert(!WUMenuInitializerSignatureMatches(5,"@","@",":","@","@","@?"));
    assert(!WUMenuInitializerSignatureMatches(5,"@","@",":","@","@","@"));
    assert(!WUMenuInitializerSignatureMatches(5,"@","@",":","@","@",NULL));
    assert(!WUMenuInitializerSignatureMatches(5,"@","@",":","@",NULL,":"));
    assert(!WUMenuInitializerSignatureMatches(5,"@","@",":",NULL,"@",":"));
    assert(!WUMenuInitializerSignatureMatches(5,"@","@",NULL,"@","@",":"));
    assert(!WUMenuInitializerSignatureMatches(5,"@",NULL,":","@","@",":"));
    assert(!WUMenuInitializerSignatureMatches(5,NULL,"@",":","@","@",":"));
    puts("menu signature conservative gate: OK");
}
