#ifndef WU_OFFLINE_VOICE_H
#define WU_OFFLINE_VOICE_H
#include <stddef.h>
#include <stdint.h>
// Owned float mono PCM derived from signed int16 decoder output, never host PCM.
// SILK explicitly requests 16000 Hz; AMR-NB is 8000 Hz. Apple targets are LE.
typedef int (*WUVoiceCancel)(void *context);
typedef struct { float *samples; size_t frames; unsigned rate; } WUOfflinePCM;
// Zero on COMPLETE success only. Caller frees samples; failures zero the result.
int WUOfflineDecode(const uint8_t *bytes, size_t length, WUVoiceCancel cancel, void *context, WUOfflinePCM *out);
#endif
