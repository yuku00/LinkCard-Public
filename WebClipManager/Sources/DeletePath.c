#include "DeletePath.h"
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

int wcm_path_valid(const char *p) {
    if (!p || p[0] != '/' || !p[1]) return 0;
    const char *s = p + 1;
    while (*s) {
        const char *end = strchr(s, '/');
        size_t n = end ? (size_t)(end-s) : strlen(s);
        if (!n || (n == 1 && s[0] == '.') || (n == 2 && s[0] == '.' && s[1] == '.')) return 0;
        if (!end) return 1;
        s = end + 1;
        if (!*s) return 0;
    }
    return 0;
}
static const char *alias(const char *p) {
    return strncmp(p, "/private/var/", 13) == 0 ? p + 8 : p;
}
int wcm_path_equal_alias(const char *a, const char *b) {
    if (!a || !wcm_path_valid(b)) return 0;
    size_t n = strlen(a);
    // A single final separator denotes the same directory, not a new component.
    if (n > 1 && a[n - 1] == '/') {
        char *trimmed = strndup(a, n - 1);
        if (!trimmed) return 0;
        int equal = wcm_path_valid(trimmed) && strcmp(alias(trimmed), alias(b)) == 0;
        free(trimmed);
        return equal;
    }
    return wcm_path_valid(a) && strcmp(alias(a), alias(b)) == 0;
}
int wcm_open_directory(const char *root, const char *leaf, const char **stage, int *error) {
    *stage = "pathValidation"; *error = 0;
    if (!wcm_path_valid(root) || (leaf && (!*leaf || strchr(leaf, '/') || !strcmp(leaf, ".") || !strcmp(leaf, "..")))) return -1;
    char *copy = strdup(root + 1);
    if (!copy) { *error = ENOMEM; return -1; }
    *stage = "rootOpen";
    int fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) { *error = errno; free(copy); return -1; }
    char *p = copy;
    for (;;) {
        char *slash = strchr(p, '/'); if (slash) *slash = 0;
        *stage = "ancestorOpen";
        int next = openat(fd, p, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0) { int e = errno; close(fd); free(copy); *error = e; return -1; }
        close(fd); fd = next;
        if (!slash) break;
        p = slash + 1;
    }
    free(copy);
    if (leaf) {
        *stage = "leafOpen";
        int next = openat(fd, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0) { int e = errno; close(fd); *error = e; return -1; }
        close(fd); fd = next;
    }
    return fd;
}
