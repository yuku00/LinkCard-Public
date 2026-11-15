#ifndef WU_CARD_POLICY_H
#define WU_CARD_POLICY_H
/* A BOOL route contract is the only supported ABI; unknown/void routes are never called. */
static inline int WUCardShouldFallback(int attempted, int handled, int unchanged, int presented, int transitioning) {
    (void)handled; (void)unchanged; (void)presented; (void)transitioning;
    return !attempted;
}
#endif
