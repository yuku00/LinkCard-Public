#include <assert.h>
#include "../Shared/FLSamplePolicy.h"
int main(void) {
    assert(FLNeedsIconSample(0, 1, 0));
    for (int i=0; i<1000; ++i) assert(!FLNeedsIconSample(1, 1, 0));
    assert(FLNeedsIconSample(1, 0, 0)); // reused icon/view/image/contents
    assert(FLNeedsIconSample(1, 1, 1)); // same identity, new pixels
    int samples = 1, paths = 1;
    // Production predicates, simulated callbacks/layouts (not a UIKit benchmark).
    for (int i=0; i<40; ++i) samples += FLNeedsIconSample(1, 1, 0);
    assert(samples == 1); // static layer.contents must not become a dynamic capture
    for (int i=0; i<1000; ++i) {
        samples += FLNeedsIconSample(1, 1, 0);
        paths += FLNeedsHaloPath(1, 1);
    }
    assert(samples == 1 && paths == 1);
    assert(FLNeedsHaloPath(0, 1));
    assert(FLNeedsHaloPath(1, 0));
    assert(FLNeedsIconSample(1, 0, 0)); // changed CGImage
    assert(!FLNeedsIconSample(1, 1, 0)); // offscreen/re-entry, same CGImage
    assert(FLAcceptIconSample(1, 1, 1));
    assert(!FLAcceptIconSample(0, 1, 1)); // stale worker
    assert(!FLAcceptIconSample(1, 0, 1)); // reused view
    assert(!FLAcceptIconSample(1, 1, 0)); // switch off/uninstall
}
