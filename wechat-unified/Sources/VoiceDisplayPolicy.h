#ifndef WU_VOICE_DISPLAY_POLICY_H
#define WU_VOICE_DISPLAY_POLICY_H
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
/* PCM is milliseconds; only the host's bubble projection saturates at 60s. */
static inline uint32_t WUVoiceDisplayMS(double ms) {
    if(!isfinite(ms) || ms<=0 || ms>180000) return 0;
    return (uint32_t)fmax(1, floor(fmin(ms,60000)));
}
typedef struct {
    uintptr_t model, message;
    uint64_t generation, request, version;
} WUVoiceDisplayIdentity;
static inline bool WUVoiceDisplaySame(WUVoiceDisplayIdentity a, WUVoiceDisplayIdentity b) {
    return a.model && a.message && a.version && a.model==b.model && a.message==b.message &&
        a.generation==b.generation && a.request==b.request && a.version==b.version;
}
static inline uint32_t WUVoiceDisplayProject(uint32_t host, double ms,
    WUVoiceDisplayIdentity lease, WUVoiceDisplayIdentity now,
    bool enabled, bool mainThread, bool layout, bool matchingReceiver) {
    uint32_t value=WUVoiceDisplayMS(ms);
    return value && enabled && mainThread && layout && matchingReceiver &&
        WUVoiceDisplaySame(lease,now) ? value : host;
}
#endif
