#ifndef WCM_HELPER_CLIENT_H
#define WCM_HELPER_CLIENT_H
#include <stddef.h>
// Internal transport; app passes only its bundled executable and fixed command.
typedef struct {
    const char *stage;
    int spawned;
    int statusValid;
    int waitError;
} WCMHelperDiagnostic;
// child_status is meaningful only when diagnostic.statusValid is nonzero.
int wcm_helper_run(const char *path, const char *command, unsigned timeout_ms,
                   unsigned char **output, size_t *length, int *child_status,
                   WCMHelperDiagnostic *diagnostic);
#endif
