#ifndef WCM_HELPER_CLIENT_H
#define WCM_HELPER_CLIENT_H
#include <stddef.h>
// Internal transport; app passes only its bundled executable and fixed command.
int wcm_helper_run(const char *path, const char *command, unsigned timeout_ms,
                   unsigned char **output, size_t *length, int *child_status);
#endif
