#ifndef WU_DIAGNOSTIC_RING_H
#define WU_DIAGNOSTIC_RING_H
#include <stddef.h>

typedef enum {
    WUDiagEntrySelected=1, WUDiagEntryManual, WUDiagRejectNoAccount,
    WUDiagRejectBegin, WUDiagRejectNoCandidates, WUDiagRejectDestination,
    WUDiagInputShown, WUDiagCandidatesShown, WUDiagConfirmationShown,
    WUDiagTransitionRejected, WUDiagTransitionStarted, WUDiagTransitionCompleted,
    WUDiagTransitionCancelled, WUDiagPresentRejected, WUDiagPresentException,
    WUDiagSafariRequested, WUDiagSystemRequested, WUDiagSystemAccepted,
    WUDiagSystemRejected, WUDiagRejectDisabled, WUDiagRejectSelection,
    WUDiagRejectContext, WUDiagRejectMessage, WUDiagFlowFinished,
    WUDiagAccountCenterClass, WUDiagAccountCenterSignature, WUDiagAccountCenterMissing,
    WUDiagAccountManagerClass, WUDiagAccountServiceSignature, WUDiagAccountManagerMissing,
    WUDiagAccountSelfSignature, WUDiagAccountSelfMissing, WUDiagAccountNameSignature,
    WUDiagAccountNameInvalid, WUDiagAccountException,
    WUDiagContextClassMissing, WUDiagActiveSignature, WUDiagActiveMissing,
    WUDiagCurrentSignature, WUDiagCurrentMissing, WUDiagContextServiceSignature,
    WUDiagContextServiceMissing, WUDiagLegacyClassMissing, WUDiagLegacySignature,
    WUDiagLegacyMissing, WUDiagLegacyServiceSignature, WUDiagLegacyServiceMissing,
    WUDiagHostServiceException, WUDiagEventEnd
} WUDiagnosticEvent;
#define WU_DIAGNOSTIC_CAPACITY 128
typedef struct { WUDiagnosticEvent values[WU_DIAGNOSTIC_CAPACITY]; size_t start, count; } WUDiagnosticRing;
typedef struct { double last; int recorded; } WUDiagnosticRate;
static inline int WUDiagnosticRateAllow(WUDiagnosticRate *rate, double now) {
    if(rate->recorded && now >= rate->last && now - rate->last < 5.0) return 0;
    rate->last=now; rate->recorded=1; return 1;
}
/* Caller serializes access. Invalid values never enter the buffer. */
static inline void WUDiagnosticRingAdd(WUDiagnosticRing *r, WUDiagnosticEvent e) {
    if(e<=0 || e>=WUDiagEventEnd) return;
    if(r->count<WU_DIAGNOSTIC_CAPACITY) { r->values[(r->start+r->count)%WU_DIAGNOSTIC_CAPACITY]=e; r->count++; }
    else { r->values[r->start]=e; r->start=(r->start+1)%WU_DIAGNOSTIC_CAPACITY; }
}
#endif
