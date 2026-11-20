#ifndef WU_SILK_ENCODE_H
#define WU_SILK_ENCODE_H
#include <stddef.h>
#include <stdint.h>
/* Input: mono 16 kHz signed 16-bit native-endian PCM, 1..960000 samples.
 * Output: Tencent-style SILK v3 container, NOT proof of host-sendability.
 * Last 20ms packet is zero-padded; encoded_samples reports actual duration.
 * On any error/cancellation, out is zeroed and no bytes are returned.
 * Caller must free(out->bytes). */
typedef int (*WUSilkCancel)(void *context);
typedef struct { uint8_t *bytes; size_t length; size_t encoded_samples; } WUSilkEncoded;
int WUSilkEncode16k(const int16_t *samples, size_t count, WUSilkCancel cancel, void *context, WUSilkEncoded *out);
#endif
