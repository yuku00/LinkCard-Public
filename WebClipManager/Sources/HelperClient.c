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
                   unsigned char **output, size_t *length, int *child_status,
                   WCMHelperDiagnostic *diagnostic) {
    *output = NULL; *length = 0; *child_status = -255;
    *diagnostic = (WCMHelperDiagnostic){.stage = "validate"};
    if (!path || !command || strcmp(command, "webclip-list") || !timeout_ms || timeout_ms > 10000) return EINVAL;
    struct stat st;
    diagnostic->stage = "lstat";
    if (lstat(path, &st)) return errno;
    diagnostic->stage = "fileType";
    if (!S_ISREG(st.st_mode) || !(st.st_mode & 0111)) return EACCES;
    diagnostic->stage = "pipe";
    int fds[2]; if (pipe(fds)) return errno;
    int error = 0, status = 0, reaped = 0, eof = 0;
    pid_t pid = -1;
    diagnostic->stage = "allocate";
    unsigned char *bytes = malloc(CAP + 1);
    if (!bytes) { close(fds[0]); close(fds[1]); return ENOMEM; }
    diagnostic->stage = "fcntl";
    if (fcntl(fds[0], F_SETFL, O_NONBLOCK) < 0 || fcntl(fds[0], F_SETFD, FD_CLOEXEC) < 0 || fcntl(fds[1], F_SETFD, FD_CLOEXEC) < 0) { error = errno; goto cleanup; }
    posix_spawn_file_actions_t actions;
    diagnostic->stage = "actionsInit";
    error = posix_spawn_file_actions_init(&actions);
    if (error) goto cleanup;
#define ACTION(stageName, x) do { diagnostic->stage = stageName; error = (x); if (error) goto actions_done; } while (0)
    ACTION("actionsCloseRead", posix_spawn_file_actions_addclose(&actions, fds[0]));
    ACTION("actionsDupOutput", posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO));
    ACTION("actionsCloseWrite", posix_spawn_file_actions_addclose(&actions, fds[1]));
    ACTION("actionsOpenInput", posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0));
    ACTION("actionsOpenError", posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0));
    {
        char *argv[] = {(char *)path, (char *)command, NULL};
        // No inherited secrets, HOME rebinding, persona or UID changes.
        char *env[] = {"LANG=C", NULL};
#ifdef __APPLE__
        posix_spawnattr_t attr;
        diagnostic->stage = "attrInit";
        error = posix_spawnattr_init(&attr);
        if (!error) {
            diagnostic->stage = "attrFlags";
            error = posix_spawnattr_setflags(&attr, POSIX_SPAWN_CLOEXEC_DEFAULT);
            if (!error) {
                diagnostic->stage = "spawn";
                error = posix_spawn(&pid, path, &actions, &attr, argv, env);
            }
            posix_spawnattr_destroy(&attr);
        }
#else
        diagnostic->stage = "spawn";
        error = posix_spawn(&pid, path, &actions, NULL, argv, env);
#endif
        if (!error) diagnostic->spawned = 1;
    }
actions_done:
    posix_spawn_file_actions_destroy(&actions);
    if (error) goto cleanup;
    close(fds[1]); fds[1] = -1;
    uint64_t deadline = now_ms() + timeout_ms;
    while (!eof || !reaped) {
        if (now_ms() >= deadline) { diagnostic->stage = "timeout"; error = ETIMEDOUT; break; }
        diagnostic->stage = "read";
        ssize_t n = read(fds[0], bytes + *length, CAP + 1 - *length);
        if (n > 0) { *length += (size_t)n; if (*length > CAP) { diagnostic->stage = "outputLimit"; error = EFBIG; break; } }
        else if (!n) eof = 1;
        else if (errno != EAGAIN && errno != EINTR) { error = errno; break; }
        if (!reaped) {
            diagnostic->stage = "waitpid";
            pid_t result = waitpid(pid, &status, WNOHANG);
            if (result == pid) reaped = 1;
            else if (result < 0 && errno != EINTR) { error = errno; diagnostic->waitError = error; break; }
        }
        if (!eof || !reaped) {
            struct pollfd p = {fds[0], POLLIN, 0};
            diagnostic->stage = "poll";
            if (poll(eof ? NULL : &p, eof ? 0 : 1, 10) < 0 && errno != EINTR) { error = errno; break; }
        }
    }
    if (!reaped && !diagnostic->waitError) {
        kill(pid, SIGKILL);
        pid_t result;
        do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
        if (result == pid) reaped = 1;
        else {
            diagnostic->waitError = errno;
            if (!error) { error = errno; diagnostic->stage = "waitpid"; }
        }
    }
    // A zero-initialized wait status is NOT evidence of a successfully exited child.
    if (reaped && (WIFSIGNALED(status) || WIFEXITED(status))) {
        diagnostic->statusValid = 1;
        *child_status = WIFSIGNALED(status) ? -WTERMSIG(status) : WEXITSTATUS(status);
    }
    if (!error && !diagnostic->statusValid) { diagnostic->stage = "waitpid"; error = ECHILD; }
    if (!error && *child_status) { diagnostic->stage = "childExit"; error = ECHILD; }
    if (!error) diagnostic->stage = "complete";
cleanup:
    close(fds[0]); if (fds[1] >= 0) close(fds[1]);
    if (error) { free(bytes); *length = 0; }
    else *output = bytes;
    return error;
}
