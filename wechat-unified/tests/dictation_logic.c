#include "WUDictationLogic.h"
#include <assert.h>
#include <stdio.h>

static void masks(void) {
    for (int original = 0; original < 2; ++original) {
        WUDMask s = {0};
        assert(WUDMaskApply(&s, false, original) == original);
        assert(WUDMaskApply(&s, true, original));
        assert(WUDMaskApply(&s, true, true));
        assert(WUDMaskApply(&s, false, true) == original);
        assert(!s.active);
        for (int requested = 0; requested < 2; ++requested) {
            assert(WUDMaskApply(&s, true, original));
            assert(WUDMaskHostWrite(&s, requested));
            assert(WUDMaskApply(&s, false, true) == requested);
            assert(WUDMaskHostWrite(&s, !requested) == !requested);
        }
    }
}
static void routing(void) {
    for (unsigned bits = 0; bits < 32; ++bits) {
        bool enabled = bits & 1, focused = bits & 2, inside = bits & 4;
        bool originalIcon = bits & 8, single = bits & 16;
        assert(WUDShouldRoute(enabled, focused, inside, originalIcon, single) ==
               (enabled && !focused && inside && originalIcon && single));
    }
}
static void taps(void) {
    WUDTap s = {0};
    assert(!WUDTapEnd(&s, true, false, true, true, 0.1, 7));
    WUDTapBegin(&s, true, 0, 7);
    assert(WUDTapEnd(&s, true, false, true, true, 0.349, 7));
    assert(!WUDTapEnd(&s, true, false, true, true, 0.349, 7));
    const double rejected[] = {0.35, 0.5, -0.01, NAN, INFINITY};
    for (unsigned i = 0; i < sizeof rejected / sizeof *rejected; ++i) {
        WUDTapBegin(&s, true, 0, 7);
        assert(!WUDTapEnd(&s, true, false, true, true, rejected[i], 7));
        assert(!s.pending);
    }
    for (unsigned bits = 0; bits < 32; ++bits) {
        bool enabled = bits & 1, focused = bits & 2, same = bits & 4;
        bool inside = bits & 8, generationOK = bits & 16;
        WUDTapBegin(&s, true, 0, 7);
        assert(WUDTapEnd(&s, enabled, focused, same, inside, 0.1,
                        generationOK ? 7 : 8) ==
               (enabled && !focused && same && inside && generationOK));
        assert(!s.pending);
    }
    WUDTapBegin(&s, true, 1, 7); WUDTapCancel(&s);
    assert(!WUDTapEnd(&s, true, false, true, true, 1.1, 7));
    WUDTapBegin(&s, true, NAN, 7); assert(!s.pending);
    WUDTapBegin(&s, true, -1, 7); assert(!s.pending);
    WUDTapBegin(&s, false, 0, 7); assert(!s.pending);
}
int main(void) {
    masks(); routing(); taps();
    puts("PASS: production mask/route/tap logic (C assertions; not UIKit/XCTest)");
    return 0;
}
