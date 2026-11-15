#include "WUCardPolicy.h"
#include <assert.h>
#include <stdio.h>

typedef struct { int routeCalls, originalCalls, pushes; } Mock;
static void run(Mock *m, int enabled, int compatible, int result, int push, int presented, int transition) {
    if (!enabled || !compatible) { m->originalCalls++; return; }
    m->routeCalls++;
    m->pushes += push;
    if (WUCardShouldFallback(1,result,!push,presented,transition)) m->originalCalls++;
}
int main(void) {
    assert(WUCardRouteKind(1,0)==1); /* void */
    assert(WUCardRouteKind(0,1)==2); /* BOOL */
    assert(WUCardRouteKind(0,0)==0); /* incompatible: never call */
    Mock m={0}; run(&m,0,1,1,1,0,0); assert(m.originalCalls==1 && !m.routeCalls);
    m=(Mock){0}; run(&m,1,0,1,1,0,0); assert(m.originalCalls==1 && !m.routeCalls);
    m=(Mock){0}; run(&m,1,1,1,1,0,0); assert(!m.originalCalls && m.pushes==1);
    m=(Mock){0}; run(&m,1,1,0,0,0,0); assert(!m.originalCalls && m.routeCalls==1);
    m=(Mock){0}; run(&m,1,1,0,1,0,0); assert(!m.originalCalls && m.pushes==1);
    m=(Mock){0}; run(&m,1,1,0,0,1,0); assert(!m.originalCalls);
    m=(Mock){0}; run(&m,1,1,0,0,0,1); assert(!m.originalCalls);
    assert(WUCardShouldFallback(0,0,1,0,0));
    puts("card policy mock passed"); return 0;
}
