#ifndef WU_NATIVE_LOGIC_H
#define WU_NATIVE_LOGIC_H
#include <stdbool.h>
#include <stddef.h>
/* Shared by production and the local C tests; no host object is simulated here. */
typedef struct { bool disable, compat; } WUNativeHotPolicy;
static inline bool WUNativeSetHot(WUNativeHotPolicy *p, bool compat, bool on) {
    if (!p || (compat && on && p->disable)) return false;
    if (compat) p->compat=on;
    else { p->disable=on; if(on) p->compat=false; }
    return true;
}
static inline bool WUNativeKeepFocus(bool enabled, bool mainThread, bool scoped,
                                    bool sameOwner, bool editing, bool sameGeneration) {
    return enabled && mainThread && scoped && sameOwner && editing && sameGeneration;
}
static inline bool WUNativeConfirmValid(bool enabled, bool consumed, bool visible,
                                        bool sameIdentity, bool sameGeneration) {
    return enabled && !consumed && visible && sameIdentity && sameGeneration;
}
static inline unsigned WUNativeGameContent(unsigned type, unsigned choice) {
    if(type==1 && choice<3) return choice+1; // scissors, rock, paper
    if(type==2 && choice<6) return choice+4; // dice 1..6 => content 4..9
    return 0;
}
#endif
