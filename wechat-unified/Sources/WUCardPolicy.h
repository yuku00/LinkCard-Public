#ifndef WU_CARD_POLICY_H
#define WU_CARD_POLICY_H
/* WCPulse ignores the route return; metadata selects the exact call ABI. */
static inline int WUCardRouteKind(int matchesVoid, int matchesBool) {
    return matchesVoid ? 1 : (matchesBool ? 2 : 0);
}
static inline int WUCardShouldFallback(int attempted, int handled, int unchanged, int presented, int transitioning) {
    (void)handled; (void)unchanged; (void)presented; (void)transitioning;
    return !attempted;
}
#endif
