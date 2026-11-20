#import <Foundation/Foundation.h>
#include <stdint.h>
// All playback values crossing the host boundary are integer milliseconds.
uint32_t WUVoiceSeekMS(double fraction, double durationMS);
NSString *WUVoiceTime(double milliseconds, BOOL carry);
NSArray<NSNumber *> *WUVoicePeaks(const float *pcm, NSUInteger frames, NSUInteger channels, NSUInteger bins);
BOOL WUVoiceLease(NSString *account, NSString *current, NSUInteger generation, NSUInteger now, BOOL visible, BOOL enabled, BOOL foreground, BOOL sameMessage);
