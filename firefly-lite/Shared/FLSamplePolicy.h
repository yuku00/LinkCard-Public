#ifndef FL_SAMPLE_POLICY_H
#define FL_SAMPLE_POLICY_H
// Shared by UIKit call sites and host regression tests.
static inline int FLNeedsIconSample(int exists, int sameSource, int dirty) {
    return !exists || !sameSource || dirty;
}
static inline int FLRefreshIconSample(int valid, int localCapture) {
    return !valid || localCapture;
}
static inline int FLAcceptIconSample(int currentState, int sameIcon, int enabled) {
    return currentState && sameIcon && enabled;
}
#endif
