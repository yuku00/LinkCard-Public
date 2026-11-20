// Geometry shared by the host hook and its local executable regression test.
#ifndef WU_INPUT_HOST_GEOMETRY_H
#define WU_INPUT_HOST_GEOMETRY_H
#include <math.h>
static inline double WUInputHostY(double original, double translation, long positionMode) {
    return fmax(original, 0.0) + (translation > 0.0 ? (positionMode == 2 ? 40.0 : 10.0) : 0.0);
}
static inline double WUInputHostHeight(double original, double translation, int eligible) {
    return eligible ? original + (translation > 0.0 ? 48.0 : 35.0) : original;
}
static inline int WUInputHostDisjoint(double x, double y, double w, double h,
                                      double bx, double by, double bw, double bh) {
    if (!isfinite(x) || !isfinite(y) || !isfinite(w) || !isfinite(h) ||
        !isfinite(bx) || !isfinite(by) || !isfinite(bw) || !isfinite(bh) ||
        w <= 0 || h <= 0 || bw <= 0 || bh <= 0) return 0;
    return x + w <= bx || bx + bw <= x || y + h <= by || by + bh <= y;
}
#endif
