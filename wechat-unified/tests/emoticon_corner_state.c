#include "WUEmoticonCornerState.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    WUCornerState s={0}; double radius=3; bool masks=false;
    assert(WUCornerApply(&s,&radius,&masks,12)); assert(radius==12 && masks);
    assert(WUCornerApply(&s,&radius,&masks,20)); assert(radius==20 && masks);
    WUCornerRestore(&s,&radius,&masks); assert(radius==3 && !masks && !s.active);
    assert(WUCornerApply(&s,&radius,&masks,12)); radius=7;
    assert(!WUCornerApply(&s,&radius,&masks,12)); assert(radius==7 && !masks && s.blocked);
    assert(!WUCornerApply(&s,&radius,&masks,12)); assert(radius==7);
    WUCornerRestore(&s,&radius,&masks); assert(radius==7 && !masks && !s.blocked);
    assert(WUCornerApply(&s,&radius,&masks,12)); masks=false;
    WUCornerRestore(&s,&radius,&masks); assert(radius==7 && !masks);
    puts("emoticon corner state mock: ok"); return 0;
}
