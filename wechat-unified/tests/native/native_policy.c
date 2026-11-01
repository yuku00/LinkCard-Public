#include "WUNativeLogic.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
int main(void) {
    for(unsigned bits=0;bits<64;bits++) {
        bool got=WUNativeKeepFocus(bits&1,bits&2,bits&4,bits&8,bits&16,bits&32);
        assert(got==(bits==63));
    }
    for(unsigned bits=0;bits<32;bits++) {
        bool got=WUNativeConfirmValid(bits&1,bits&2,bits&4,bits&8,bits&16);
        assert(got==(bits==29));
    }
    WUNativeHotPolicy p={false,false};
    assert(WUNativeSetHot(&p,true,true) && p.compat);
    assert(WUNativeSetHot(&p,false,true) && p.disable && !p.compat);
    assert(!WUNativeSetHot(&p,true,true) && p.disable && !p.compat);
    assert(WUNativeSetHot(&p,false,false) && !p.disable && !p.compat);
    assert(WUNativeSetHot(&p,true,true) && p.compat);
    assert(WUNativeSetHot(&p,true,false) && !p.compat);
    assert(!WUNativeSetHot(NULL,true,false));
    for(unsigned i=0;i<3;i++) assert(WUNativeGameContent(1,i)==i+1);
    for(unsigned i=0;i<6;i++) assert(WUNativeGameContent(2,i)==i+4);
    assert(!WUNativeGameContent(1,3)); assert(!WUNativeGameContent(2,6));
    assert(!WUNativeGameContent(0,0)); assert(!WUNativeGameContent(3,0));
    assert(!WUNativeGameContent(2,UINT_MAX));
    puts("native production policy: 64 focus + 32 confirmation cases; hot mutual exclusion; all nine game mappings PASS");
    return 0;
}
