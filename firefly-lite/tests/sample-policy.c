#include <assert.h>
#include "../Shared/FLSamplePolicy.h"
int main(void) {
    assert(FLNeedsIconSample(0, 1, 0));
    for (int i=0; i<1000; ++i) assert(!FLNeedsIconSample(1, 1, 0));
    assert(FLNeedsIconSample(1, 0, 0)); // reused icon/view/image/contents
    assert(FLNeedsIconSample(1, 1, 1)); // same identity, new pixels
    assert(FLRefreshIconSample(0, 0)); // failed getter must recover
    assert(FLRefreshIconSample(0, 1));
    assert(FLRefreshIconSample(1, 1)); // render cache invalidated by image event
    assert(!FLRefreshIconSample(1, 0)); // immutable UIImage fast path
    assert(FLAcceptIconSample(1, 1, 1));
    assert(!FLAcceptIconSample(0, 1, 1)); // stale worker
    assert(!FLAcceptIconSample(1, 0, 1)); // reused view
    assert(!FLAcceptIconSample(1, 1, 0)); // switch off/uninstall
}
