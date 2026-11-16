#include <assert.h>
#include <math.h>
#include "../Sources/WUInputReservationGeometry.h"
int main(void) {
    /* Captured 390x844: tool stays full-screen, the 90pt container grows upward. */
    WUInputRect container={0,754,390,90}, expanded={0,710,390,134}, actualBar={0,754,390,56};
    WUInputRect fullScreen={0,0,390,844};
    assert(WUInputReserved(container,expanded,actualBar,actualBar,44));
    assert(!WUInputReserved(fullScreen,fullScreen,actualBar,actualBar,44));
    WUInputRect movedInput={0,710,390,56};
    assert(!WUInputReserved(container,expanded,actualBar,movedInput,44));
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
