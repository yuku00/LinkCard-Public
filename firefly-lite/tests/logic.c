#include <assert.h>
#include "../Shared/FLLogic.h"
int main(void) {
    assert(FLUnit(-1, .65) == 0);
    assert(FLUnit(2, .65) == 1);
    assert(FLUnit(.5, .65) == .5);
    assert(FLUnit(NAN, .65) == .65);
    assert(FLUnit(INFINITY, .65) == .65);
    // Both modes, including app icons displayed inside folders (folder == 0).
    for (int allApps = 0; allApps <= 1; ++allApps) {
        for (int badge = 0; badge <= 1; ++badge) {
            assert(FLShouldGlow(1, allApps, badge, 0, 1, .65) == (allApps || badge));
            assert(!FLShouldGlow(0, allApps, badge, 0, 1, .65));
            assert(!FLShouldGlow(1, allApps, badge, 1, 1, .65));
            assert(!FLShouldGlow(1, allApps, badge, 0, 0, .65));
            assert(!FLShouldGlow(1, allApps, badge, 0, 1, 0));
        }
    }
    return 0;
}
