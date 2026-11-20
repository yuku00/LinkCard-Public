#ifndef WU_DICTATION_LOGIC_H
#define WU_DICTATION_LOGIC_H
#include <stdbool.h>
#include <stdint.h>
#include <math.h>

/* Shared by production Objective-C and the native C test; no UIKit dependency. */
typedef struct { bool active, desiredHidden; } WUDMask;
static inline bool WUDMaskApply(WUDMask *s, bool enabled, bool current) {
    if (enabled && !s->active) s->desiredHidden = current;
    if (!enabled && s->active) current = s->desiredHidden;
    s->active = enabled;
    return enabled ? true : current;
}
static inline bool WUDMaskHostWrite(WUDMask *s, bool requested) {
    if (s->active) s->desiredHidden = requested;
    return s->active ? true : requested;
}

typedef struct { bool pending; double began; uint64_t generation; } WUDTap;
static inline bool WUDShouldRoute(bool enabled, bool focused, bool iconHit,
                                  bool originalHitsIcon, bool singleTouch) {
    return enabled && !focused && iconHit && originalHitsIcon && singleTouch;
}
static inline void WUDTapCancel(WUDTap *s) { *s = (WUDTap){0}; }
static inline void WUDTapBegin(WUDTap *s, bool eligible, double timestamp,
                                uint64_t generation) {
    *s = (WUDTap){eligible && isfinite(timestamp) && timestamp >= 0,
                  timestamp, generation};
}
/* The result permits ONLY focus, never a dictation start/submit/replay. */
static inline bool WUDTapEnd(WUDTap *s, bool enabled, bool focused,
                              bool sameTargetAndTouch, bool inside,
                              double timestamp, uint64_t generation) {
    const double elapsed = timestamp - s->began;
    bool focus = s->pending && enabled && !focused && sameTargetAndTouch &&
                 inside && s->generation == generation && isfinite(timestamp) &&
                 isfinite(elapsed) && elapsed >= 0 && elapsed < 0.35;
    WUDTapCancel(s);
    return focus;
}
#endif
