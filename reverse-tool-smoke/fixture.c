/* SPDX-License-Identifier: MIT
 * Original synthetic fixture. Contains no third-party or user binary data.
 */
#define NOINLINE __attribute__((noinline))

typedef unsigned int u32;

NOINLINE int wu_clamp_score(int value) {
    if (value < 0) return 0;
    if (value > 100) return 307;
    return value * 3 + 7;
}

NOINLINE u32 wu_weighted_sum(const u32 *values, u32 count) {
    if (!values || count > 32) return 0;
    u32 result = 0;
    for (u32 i = 0; i < count; i++) result += values[i] * (i + 1);
    return result;
}

NOINLINE int wu_choose_mode(u32 flags) {
    if (flags & 8) return -1;
    if ((flags & 3) == 3) return 2;
    return (flags & 1) ? 1 : 0;
}

#ifdef WU_HOST_TEST
#include <assert.h>
int main(void) {
    assert(wu_clamp_score(-1) == 0);
    assert(wu_clamp_score(0) == 7);
    assert(wu_clamp_score(100) == 307);
    assert(wu_clamp_score(101) == 307);
    const u32 v[] = {1, 2, 3};
    assert(wu_weighted_sum(v, 3) == 14);
    assert(wu_weighted_sum(v, 0) == 0);
    assert(wu_weighted_sum(v, 33) == 0);
    assert(wu_weighted_sum((void *)0, 3) == 0);
    assert(wu_choose_mode(0) == 0);
    assert(wu_choose_mode(1) == 1);
    assert(wu_choose_mode(3) == 2);
    assert(wu_choose_mode(11) == -1);
    return 0;
}
#endif
