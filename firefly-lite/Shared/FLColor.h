#ifndef FL_COLOR_H
#define FL_COLOR_H
#include <stddef.h>
#include <stdint.h>
#include <math.h>
typedef struct { double red, green, blue; } FLRGB;
static inline FLRGB FLChooseColor(int follow, int valid, FLRGB sampled, FLRGB manual) {
    return follow && valid ? sampled : manual;
}
// Input: small premultiplied RGBA bitmap. Prefer chroma, accept neutral icons.
static inline int FLRepresentativeColor(const uint8_t *pixels, size_t count, FLRGB *out) {
    double weights[64] = {0}, red[64] = {0}, green[64] = {0}, blue[64] = {0};
    double neutralR = 0, neutralG = 0, neutralB = 0, alpha = 0;
    if (!pixels || !out || count > 576) return 0;
    for (size_t i = 0; i < count; ++i) {
        const uint8_t *p = pixels + i * 4;
        if (p[3] < 128) continue;
        double r = fmin(1, (double)p[0]/p[3]);
        double g = fmin(1, (double)p[1]/p[3]);
        double b = fmin(1, (double)p[2]/p[3]);
        neutralR += p[0]; neutralG += p[1]; neutralB += p[2]; alpha += p[3];
        double hi = fmax(r, fmax(g,b)), lo = fmin(r, fmin(g,b));
        if (hi < .12 || hi - lo < .10) continue;
        unsigned bin = ((unsigned)(r*3.99)<<4) | ((unsigned)(g*3.99)<<2) | (unsigned)(b*3.99);
        double w = (hi-lo) * p[3]/255.0;
        weights[bin] += w; red[bin] += r*w; green[bin] += g*w; blue[bin] += b*w;
    }
    unsigned best = 0;
    for (unsigned i = 1; i < 64; ++i) if (weights[i] > weights[best]) best = i;
    if (!weights[best]) {
        if (!alpha) return 0;
        *out = (FLRGB){neutralR/alpha, neutralG/alpha, neutralB/alpha};
        return 1;
    }
    *out = (FLRGB){red[best]/weights[best], green[best]/weights[best], blue[best]/weights[best]};
    return 1;
}
#endif
