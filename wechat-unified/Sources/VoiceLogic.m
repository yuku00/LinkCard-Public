#import "VoiceLogic.h"
#include <math.h>
uint32_t WUVoiceSeekMS(double fraction, double durationMS) {
    if(!isfinite(fraction) || !isfinite(durationMS) || durationMS<=0 || durationMS>180000) return 0;
    return (uint32_t)floor(fmax(0,fmin(1,fraction))*durationMS);
}
NSString *WUVoiceTime(double ms, BOOL carry) {
    if(!isfinite(ms) || ms<0 || ms>180000) return @"—";
    unsigned seconds=(unsigned)floor(ms/1000.0);
    return carry ? [NSString stringWithFormat:@"%u:%02u",seconds/60,seconds%60] : [NSString stringWithFormat:@"%u秒",seconds];
}
NSArray<NSNumber *> *WUVoicePeaks(const float *pcm, NSUInteger frames, NSUInteger channels, NSUInteger bins) {
    if(!pcm || !frames || frames>8640000 || channels<1 || channels>2 || !bins || bins>128) return nil;
    bins=MIN(bins,frames); NSMutableArray *result=[NSMutableArray arrayWithCapacity:bins];
    for(NSUInteger b=0;b<bins;b++) {
        double peak=0;
        for(NSUInteger f=b*frames/bins;f<(b+1)*frames/bins;f++) for(NSUInteger c=0;c<channels;c++) {
            float x=pcm[f*channels+c]; if(!isfinite(x)) return nil;
            peak=fmax(peak,fmin(1,fabs(x)));
        }
        [result addObject:@(peak)];
    }
    return result;
}
BOOL WUVoiceLease(NSString *a, NSString *current, NSUInteger g, NSUInteger now, BOOL visible, BOOL enabled, BOOL foreground, BOOL sameMessage) {
    return a.length && [a isEqual:current] && g==now && visible && enabled && foreground && sameMessage;
}
