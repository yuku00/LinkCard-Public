#include <assert.h>
#include "../Shared/FLLogic.h"
int main(void) {
    assert(FLUnit(-1, .65) == 0);
    assert(FLUnit(2, .65) == 1);
    assert(FLUnit(.5, .65) == .5);
    assert(FLUnit(NAN, .65) == .65);
    assert(FLUnit(INFINITY, .65) == .65);
    assert(FLShouldGlow(1, 1, 0, 1, .65));
    assert(!FLShouldGlow(0, 1, 0, 1, .65));
    assert(!FLShouldGlow(1, 0, 0, 1, .65));
    assert(!FLShouldGlow(1, 1, 1, 1, .65));
    assert(!FLShouldGlow(1, 1, 0, 0, .65));
    assert(!FLShouldGlow(1, 1, 0, 1, 0));
    return 0;
}
