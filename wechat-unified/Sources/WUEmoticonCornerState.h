#ifndef WU_EMOTICON_CORNER_STATE_H
#define WU_EMOTICON_CORNER_STATE_H
#include <stdbool.h>
typedef struct { double oldRadius, appliedRadius; bool oldMasks, appliedMasks, active, blocked; } WUCornerState;
static inline bool WUCornerApply(WUCornerState *s, double *r, bool *m, double desired) {
    if (s->blocked) return false;
    if (s->active && (*r != s->appliedRadius || *m != s->appliedMasks)) {
        if (*r == s->appliedRadius) *r=s->oldRadius;
        if (*m == s->appliedMasks) *m=s->oldMasks;
        s->active=false; s->blocked=true; return false;
    }
    if (!s->active) { s->oldRadius=*r; s->oldMasks=*m; s->active=true; }
    s->appliedRadius=desired; s->appliedMasks=true; *r=desired; *m=true; return true;
}
static inline void WUCornerRestore(WUCornerState *s, double *r, bool *m) {
    if (s->active) { if (*r==s->appliedRadius) *r=s->oldRadius; if (*m==s->appliedMasks) *m=s->oldMasks; }
    *s=(WUCornerState){0};
}
#endif
