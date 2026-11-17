#ifndef WU_INPUT_RESERVATION_GEOMETRY_H
#define WU_INPUT_RESERVATION_GEOMETRY_H
#include <math.h>
typedef struct { double x,y,w,h; } WUInputRect;
static int WUInputNear(double a,double b) { return isfinite(a) && isfinite(b) && fabs(a-b)<=2.0; }
/* Only the host moving its top edge up by the requested amount counts as reservation. */
static int WUInputReserved(WUInputRect before, WUInputRect after, WUInputRect barBefore, WUInputRect barAfter, double extra) {
    if (!isfinite(extra) || extra<44 || before.w<=0 || before.h<=0 || after.w<=0 || after.h<=0 || barBefore.w<=0 || barBefore.h<=0 || barAfter.w<=0 || barAfter.h<=0) return 0;
    return WUInputNear(before.x,after.x) && WUInputNear(before.w,after.w) &&
        WUInputNear(before.y,after.y+extra) && WUInputNear(before.y+before.h,after.y+after.h) &&
        WUInputNear(barBefore.x,barAfter.x) && WUInputNear(barBefore.y,barAfter.y) &&
        WUInputNear(barBefore.w,barAfter.w) && WUInputNear(barBefore.h,barAfter.h);
}
#endif
