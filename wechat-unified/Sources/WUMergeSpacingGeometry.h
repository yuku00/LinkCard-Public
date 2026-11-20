#ifndef WU_MERGE_SPACING_GEOMETRY_H
#define WU_MERGE_SPACING_GEOMETRY_H
#include <math.h>
// The row-height integration is quarantined until it is verified on a real host.
#ifndef WU_MERGE_SPACING_EXPERIMENTAL
#define WU_MERGE_SPACING_EXPERIMENTAL 0
#endif
static inline double WUMergeSpacingHeight(double original, double baseline, double target) {
    if(!isfinite(original) || !isfinite(baseline) || !isfinite(target) || target<0 || target>30) return original;
    double candidate=original-fmax(baseline-target,0.0);
    return isfinite(candidate) && candidate>20.0?candidate:original;
}
#endif
