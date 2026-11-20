#ifndef WU_MERGE_SPACING_GEOMETRY_H
#define WU_MERGE_SPACING_GEOMETRY_H
#include <math.h>
static inline double WUMergeSpacingHeight(double original, double baseline, double target) {
    if(!isfinite(original) || !isfinite(baseline) || !isfinite(target) || target<0 || target>30) return original;
    double candidate=original-fmax(baseline-target,0.0);
    return isfinite(candidate) && candidate>20.0?candidate:original;
}
#endif
