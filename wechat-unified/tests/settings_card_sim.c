#include <assert.h>
#include <stdio.h>
#include "WUCardPolicy.h"

/* Model of the side-effect policy, not a substitute for Objective-C runtime tests. */
typedef struct { int rows[8], count, entry; } Table;
static void ensure(Table *t, int signatures_ok) {
    if (!signatures_ok) return;
    for (int i=0;i<t->count;i++) if (t->rows[i]==t->entry) return;
    for (int i=t->count;i>0;i--) t->rows[i]=t->rows[i-1];
    t->rows[0]=t->entry; t->count++;
}
int main(void) {
    Table t={{10,11,12},3,99};
    ensure(&t,0); assert(t.count==3 && t.rows[0]==10);
    ensure(&t,1); ensure(&t,1);
    assert(t.count==4 && t.rows[0]==99 && t.rows[1]==10 && t.rows[2]==11 && t.rows[3]==12);
    t.rows[0]=10; t.rows[1]=11; t.count=2; /* host rebuild */
    ensure(&t,1); assert(t.count==3 && t.rows[0]==99 && t.rows[1]==10 && t.rows[2]==11);
    for (int kind=1;kind<=2;kind++) {
        assert(WUCardRouteKind(kind==1,kind==2)==kind);
        assert(WUCardShouldFallback(0,0,1,0,0));
        assert(!WUCardShouldFallback(1,0,1,0,0));
    }
    assert(WUCardRouteKind(0,0)==0);
    puts("settings/card side-effect model passed");
}
