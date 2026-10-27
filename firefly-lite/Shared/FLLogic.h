#ifndef FL_LOGIC_H
#define FL_LOGIC_H
#include <math.h>
static inline double FLUnit(double value, double fallback) {
    if (!isfinite(value)) return fallback;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
}
static inline int FLShouldGlow(int enabled, int badge, int folder, int attached,
                               double intensity) {
    return enabled && badge && !folder && attached && intensity > 0;
}
#endif
