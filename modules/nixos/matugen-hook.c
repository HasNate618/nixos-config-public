/*
 * matugen-hook.c — LD_PRELOAD shim for skwd-daemon.
 *
 * skwd-daemon spawns its BUNDLED matugen 4.0.0 (pinned into the daemon's
 * PATH by the skwd-wall package's makeWrapper). That version crashes
 * headless on achromatic/monochrome images ("IO error: not a terminal" —
 * it tries the interactive color picker) and its --fallback-color does not
 * prevent the crash. Result: monochrome wallpapers never generate a theme.
 *
 * This hook redirects ANY exec of a program whose basename is `matugen` to
 * /home/nate/.local/bin/matugen (the wrapper), which runs matugen 4.1.0
 * with --source-color-index 0 (no TUI) and --fallback-color '#00FF00'
 * (green scheme for achromatic images).
 *
 * Intercepts execvp, execvpe, posix_spawn, posix_spawnp:
 * - Rust's std::process::Command uses posix_spawnp for PATH lookups
 * - glibc's execvp internally calls execvpe
 * - QProcess/shell callers hit execvp directly
 *
 * The wrapper path is a shell script; the kernel handles the shebang, so
 * no special ENOEXEC handling is needed.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char WRAPPER[] = "/home/nate/.local/bin/matugen";

static int is_matugen(const char *file) {
  if (file == NULL)
    return 0;
  const char *base = strrchr(file, '/');
  base = (base != NULL) ? base + 1 : file;
  return strcmp(base, "matugen") == 0;
}

static const char *maybe_redirect(const char *file) {
  return is_matugen(file) ? WRAPPER : file;
}

/* execvp */
typedef int (*real_execvp_t)(const char *, char *const[]);
static real_execvp_t real_execvp_fn;
int execvp(const char *file, char *const argv[]) {
  if (real_execvp_fn == NULL)
    real_execvp_fn = (real_execvp_t)dlsym(RTLD_NEXT, "execvp");
  return real_execvp_fn(maybe_redirect(file), argv);
}

/* execvpe */
typedef int (*real_execvpe_t)(const char *, char *const[], char *const[]);
static real_execvpe_t real_execvpe_fn;
int execvpe(const char *file, char *const argv[], char *const envp[]) {
  if (real_execvpe_fn == NULL)
    real_execvpe_fn = (real_execvpe_t)dlsym(RTLD_NEXT, "execvpe");
  return real_execvpe_fn(maybe_redirect(file), argv, envp);
}

/* posix_spawn */
typedef int (*real_posix_spawn_t)(pid_t *, const char *,
                                  const posix_spawn_file_actions_t *,
                                  const posix_spawnattr_t *, char *const[],
                                  char *const[]);
static real_posix_spawn_t real_posix_spawn_fn;
int posix_spawn(pid_t *pid, const char *file,
                const posix_spawn_file_actions_t *file_actions,
                const posix_spawnattr_t *attrp, char *const argv[],
                char *const envp[]) {
  if (real_posix_spawn_fn == NULL)
    real_posix_spawn_fn = (real_posix_spawn_t)dlsym(RTLD_NEXT, "posix_spawn");
  return real_posix_spawn_fn(pid, maybe_redirect(file), file_actions, attrp,
                             argv, envp);
}

/* posix_spawnp */
typedef int (*real_posix_spawnp_t)(pid_t *, const char *,
                                   const posix_spawn_file_actions_t *,
                                   const posix_spawnattr_t *, char *const[],
                                   char *const[]);
static real_posix_spawnp_t real_posix_spawnp_fn;
int posix_spawnp(pid_t *pid, const char *file,
                 const posix_spawn_file_actions_t *file_actions,
                 const posix_spawnattr_t *attrp, char *const argv[],
                 char *const envp[]) {
  if (real_posix_spawnp_fn == NULL)
    real_posix_spawnp_fn =
        (real_posix_spawnp_t)dlsym(RTLD_NEXT, "posix_spawnp");
  return real_posix_spawnp_fn(pid, maybe_redirect(file), file_actions, attrp,
                              argv, envp);
}
