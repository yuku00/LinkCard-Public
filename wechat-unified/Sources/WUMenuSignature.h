#ifndef WU_MENU_SIGNATURE_H
#define WU_MENU_SIGNATURE_H
#include <string.h>
/* Conservative diagnostic only; a match never authorizes a hook or invocation. */
static inline int WUMenuFilterSignatureMatches(unsigned count, const char *result,
                                               const char *self, const char *cmd,
                                               const char *argument) {
    return count == 3 && result && self && cmd && argument &&
        strcmp(result, "@") == 0 && strcmp(self, "@") == 0 &&
        strcmp(cmd, ":") == 0 && strcmp(argument, "@") == 0;
}
#endif
