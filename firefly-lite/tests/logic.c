#include <assert.h>
#include "../Shared/FLLogic.h"
#include "../Shared/FLColor.h"
#include <string.h>
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
    FLRGB sampled = {1,0,0}, manual = {.3,.72,1}, out = {0};
    assert(FLChooseColor(0, 1, sampled, manual).blue == 1);
    assert(FLChooseColor(1, 0, sampled, manual).blue == 1);
    assert(FLChooseColor(1, 1, sampled, manual).red == 1);
    assert(!FLRepresentativeColor(NULL, 1, &out));
    uint8_t pixels[576*4];
    memset(pixels, 255, sizeof(pixels));
    assert(FLRepresentativeColor(pixels, 576, &out));
    assert(out.red == 1 && out.green == 1 && out.blue == 1); // white is valid
    memset(pixels, 0, sizeof(pixels));
    assert(!FLRepresentativeColor(pixels, 576, &out)); // transparent fallback
    for (int i = 0; i < 576; ++i) pixels[i*4+3] = 255;
    assert(FLRepresentativeColor(pixels, 576, &out));
    assert(out.red == 0 && out.green == 0 && out.blue == 0); // black is valid
    uint8_t gray[] = {128,128,128,255};
    assert(FLRepresentativeColor(gray, 1, &out));
    assert(out.red == 128.0/255 && out.green == out.red && out.blue == out.red);
    assert(!FLRepresentativeColor(pixels, 577, &out)); // sampling bound
    memset(pixels, 255, sizeof(pixels));
    pixels[1] = pixels[2] = 0; // one red sample beats 575 neutral white samples
    assert(FLRepresentativeColor(pixels, 576, &out));
    assert(out.red == 1 && out.green == 0 && out.blue == 0);
    uint8_t mixed[] = {0,255,0,255, 0,255,0,255, 255,0,0,255, 0,0,127,127};
    assert(FLRepresentativeColor(mixed, 4, &out));
    assert(out.green == 1 && out.red == 0 && out.blue == 0);
    uint8_t alpha[] = {128,0,0,128};
    assert(FLRepresentativeColor(alpha, 1, &out) && out.red == 1);
    return 0;
}
