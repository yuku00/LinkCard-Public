#include <assert.h>
#include <math.h>
#include "../Sources/WUInputReservationGeometry.h"
int main(void) {
    WUInputRect old={0,500,320,100}, new={0,456,320,144}, bar={0,550,320,50};
    assert(WUInputReserved(old,new,bar,bar,44));
    WUInputRect keyboardOld={0,300,320,100}, keyboardNew={0,256,320,144}, keyboardBar={0,350,320,50};
    assert(WUInputReserved(keyboardOld,keyboardNew,keyboardBar,keyboardBar,44));
    WUInputRect overlay={0,500,320,100}; assert(!WUInputReserved(old,overlay,bar,bar,44));
    WUInputRect movedBar={0,506,320,50}; assert(!WUInputReserved(old,new,bar,movedBar,44));
    WUInputRect bigger={0,456,320,145}; assert(WUInputReserved(old,bigger,bar,bar,44));
    bigger.h=150; assert(!WUInputReserved(old,bigger,bar,bar,44));
    new.y=NAN; assert(!WUInputReserved(old,new,bar,bar,44));
    return 0;
}
