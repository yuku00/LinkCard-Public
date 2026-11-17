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
/* The old plugin passes a SEL in the fifth Objective-C argument register.
   This gate checks ABI shape only; it does not establish dispatch semantics. */
static inline int WUMenuInitializerSignatureMatches(unsigned count, const char *result,
                                                    const char *self, const char *cmd,
                                                    const char *title, const char *icon,
                                                    const char *action) {
    return count == 5 && result && self && cmd && title && icon && action &&
        strcmp(result, "@") == 0 && strcmp(self, "@") == 0 &&
        strcmp(cmd, ":") == 0 && strcmp(title, "@") == 0 &&
        strcmp(icon, "@") == 0 && strcmp(action, ":") == 0;
}
#endif
