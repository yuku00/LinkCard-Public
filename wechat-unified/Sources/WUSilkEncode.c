#include "WUSilkEncode.h"
#include "SKP_Silk_SDK_API.h"
#include <stdlib.h>
#include <string.h>
#define FRAME 320u
#define MAX_SAMPLES 960000u
#define MAX_OUTPUT (8u * 1024u * 1024u)
#define MAX_PACKET 5120
int WUSilkEncode16k(const int16_t *samples, size_t count, WUSilkCancel cancel, void *context, WUSilkEncoded *out) {
    void *state = NULL; uint8_t *data = NULL; size_t pos = 10, offset;
    SKP_int32 state_size = 0; SKP_SILK_SDK_EncControlStruct control;
    if (!out) return -1;
    memset(out, 0, sizeof(*out));
    if (!samples || !count || count > MAX_SAMPLES || (cancel && cancel(context))) return -1;
    if (SKP_Silk_SDK_Get_Encoder_Size(&state_size) || state_size <= 0 || state_size > 1024*1024) return -1;
    state = calloc(1, (size_t)state_size); data = malloc(MAX_OUTPUT);
    if (!state || !data) goto fail;
    memset(&control, 0, sizeof(control));
    if (SKP_Silk_SDK_InitEncoder(state, &control)) goto fail;
    control.API_sampleRate = 16000; control.maxInternalSampleRate = 16000;
    control.packetSize = FRAME; control.bitRate = 24000; control.packetLossPercentage = 0;
    control.complexity = 2; control.useInBandFEC = 0; control.useDTX = 0;
    memcpy(data, "\x02#!SILK_V3", 10);
    for (offset = 0; offset < count; offset += FRAME) {
        int16_t input[FRAME] = {0}; SKP_uint8 packet[MAX_PACKET]; SKP_int16 n = MAX_PACKET;
        size_t ncopy = count - offset; if (ncopy > FRAME) ncopy = FRAME;
        if (cancel && cancel(context)) goto fail;
        memcpy(input, samples + offset, ncopy * sizeof(*samples));
        if (SKP_Silk_SDK_Encode(state, &control, input, FRAME, packet, &n) || n <= 0 || n > MAX_PACKET || pos > MAX_OUTPUT - (size_t)n - 2) goto fail;
        data[pos++] = (uint8_t)n; data[pos++] = (uint8_t)((unsigned)n >> 8);
        memcpy(data + pos, packet, (size_t)n); pos += (size_t)n;
    }
    if (cancel && cancel(context)) goto fail;
    free(state); out->bytes = data; out->length = pos;
    out->encoded_samples = ((count + FRAME - 1) / FRAME) * FRAME;
    return 0;
fail:
    free(state); free(data); return -1;
}
