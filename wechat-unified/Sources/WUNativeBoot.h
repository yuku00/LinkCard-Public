#ifndef WU_NATIVE_BOOT_H
#define WU_NATIVE_BOOT_H
#include <stdbool.h>
#include <stdint.h>
typedef struct { uint32_t failures, pending, blocked; } WUNativeBootState;
// dirfd must be a plugin-owned directory opened O_DIRECTORY|O_NOFOLLOW.
// IO failures/corruption fail closed; never read or alter a host safe-mode file.
bool WUNativeBootBeginAt(int dirfd, WUNativeBootState *state);
bool WUNativeBootStableAt(int dirfd, WUNativeBootState *state);
bool WUNativeBootResetAt(int dirfd, WUNativeBootState *state);
#endif
