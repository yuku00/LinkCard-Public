#include "HelperClient.h"
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdint.h>
#define CAP (8u * 1024u * 1024u)
static uint64_t now_ms(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
int wcm_helper_run(const char *path, const char *command, unsigned timeout_ms,
                   unsigned char **output, size_t *length, int *child_status) {
    *output = NULL; *length = 0; *child_status = 0;
    if (!path || !command || strcmp(command, "webclip-list") || !timeout_ms || timeout_ms > 10000) return EINVAL;
    struct stat st;
    if (lstat(path, &st)) return errno;
    if (!S_ISREG(st.st_mode) || !(st.st_mode & 0111)) return EACCES;
    int fds[2]; if (pipe(fds)) return errno;
    int error = 0, status = 0, reaped = 0, eof = 0;
    pid_t pid = -1;
    unsigned char *bytes = malloc(CAP + 1);
    if (!bytes) { close(fds[0]); close(fds[1]); return ENOMEM; }
    if (fcntl(fds[0], F_SETFL, O_NONBLOCK) < 0 || fcntl(fds[0], F_SETFD, FD_CLOEXEC) < 0 || fcntl(fds[1], F_SETFD, FD_CLOEXEC) < 0) { error = errno; goto cleanup; }
    posix_spawn_file_actions_t actions;
    error = posix_spawn_file_actions_init(&actions);
    if (error) goto cleanup;
#define ACTION(x) do { error = (x); if (error) goto actions_done; } while (0)
    ACTION(posix_spawn_file_actions_addclose(&actions, fds[0]));
    ACTION(posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO));
    ACTION(posix_spawn_file_actions_addclose(&actions, fds[1]));
    ACTION(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0));
    ACTION(posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0));
    {
        char *argv[] = {(char *)path, (char *)command, NULL};
        // No inherited secrets, HOME rebinding, persona or UID changes.
        char *env[] = {"LANG=C", NULL};
#ifdef __APPLE__
        posix_spawnattr_t attr;
        error = posix_spawnattr_init(&attr);
        if (!error) {
            error = posix_spawnattr_setflags(&attr, POSIX_SPAWN_CLOEXEC_DEFAULT);
            if (!error) error = posix_spawn(&pid, path, &actions, &attr, argv, env);
            posix_spawnattr_destroy(&attr);
        }
#else
        error = posix_spawn(&pid, path, &actions, NULL, argv, env);
#endif
    }
actions_done:
    posix_spawn_file_actions_destroy(&actions);
    if (error) goto cleanup;
    close(fds[1]); fds[1] = -1;
    uint64_t deadline = now_ms() + timeout_ms;
    while (!eof || !reaped) {
        if (now_ms() >= deadline) { error = ETIMEDOUT; break; }
        ssize_t n = read(fds[0], bytes + *length, CAP + 1 - *length);
        if (n > 0) { *length += (size_t)n; if (*length > CAP) { error = EFBIG; break; } }
        else if (!n) eof = 1;
        else if (errno != EAGAIN && errno != EINTR) { error = errno; break; }
        if (!reaped) {
            pid_t result = waitpid(pid, &status, WNOHANG);
            if (result == pid) reaped = 1;
            else if (result < 0 && errno != EINTR) { error = errno; break; }
        }
        if (!eof || !reaped) { struct pollfd p = {fds[0], POLLIN, 0}; poll(eof ? NULL : &p, eof ? 0 : 1, 10); }
    }
    if (!reaped) {
        kill(pid, SIGKILL);
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    }
    *child_status = WIFSIGNALED(status) ? -WTERMSIG(status) : WIFEXITED(status) ? WEXITSTATUS(status) : -255;
    if (!error && *child_status) error = ECHILD;
cleanup:
    close(fds[0]); if (fds[1] >= 0) close(fds[1]);
    if (error) { free(bytes); *length = 0; }
    else *output = bytes;
    return error;
}
