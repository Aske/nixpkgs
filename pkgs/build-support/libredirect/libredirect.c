#define _GNU_SOURCE
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <limits.h>
#include <string.h>
#include <spawn.h>

#define MAX_REDIRECTS 128

static int nrRedirects = 0;
static char * from[MAX_REDIRECTS];
static char * to[MAX_REDIRECTS];

// FIXME: might run too late.
static void init() __attribute__((constructor));

static void init()
{
    char * spec = getenv("NIX_REDIRECTS");
    if (!spec) return;

    unsetenv("NIX_REDIRECTS");

    char * spec2 = malloc(strlen(spec) + 1);
    strcpy(spec2, spec);

    char * pos = spec2, * eq;
    while ((eq = strchr(pos, '='))) {
        *eq = 0;
        from[nrRedirects] = pos;
        pos = eq + 1;
        to[nrRedirects] = pos;
        nrRedirects++;
        if (nrRedirects == MAX_REDIRECTS) break;
        char * end = strchr(pos, ':');
        if (!end) break;
        *end = 0;
        pos = end + 1;
    }

}

static const char * rewrite(const char * path, char * buf)
{
    for (int n = 0; n < nrRedirects; ++n) {
        int len = strlen(from[n]);
        if (strncmp(path, from[n], len) != 0) continue;
        if (snprintf(buf, PATH_MAX, "%s%s", to[n], path + len) >= PATH_MAX)
            abort();
        return buf;
    }

    return path;
}

/* The following set of Glibc library functions is very incomplete -
   it contains only what we needed for programs in Nixpkgs. Just add
   more functions as needed. */

int open(const char * path, int flags, ...)
{
    static int (*open_real) (const char *, int, mode_t) = NULL;

    if (open_real == NULL) {
      open_real = dlsym(RTLD_NEXT, "open");
    };

    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    char buf[PATH_MAX];
    return open_real(rewrite(path, buf), flags, mode);
}

int open64(const char * path, int flags, ...)
{
    static int (*open64_real) (const char *, int, mode_t) = NULL;

    if (open64_real == NULL) {
        open64_real = dlsym(RTLD_NEXT, "open64");
    };

    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    char buf[PATH_MAX];

    return open64_real(rewrite(path, buf), flags, mode);
}

FILE * fopen(const char * path, const char * mode)
{
    static FILE * (*fopen_real) (const char *, const char *) = NULL;

    if (fopen_real == NULL) {
        fopen_real = dlsym(RTLD_NEXT, "fopen");
    };

    char buf[PATH_MAX];
    return fopen_real(rewrite(path, buf), mode);
}

FILE * fopen64(const char * path, const char * mode)
{
    static FILE * (*fopen64_real) (const char *, const char *) = NULL;

    if (fopen64_real == NULL) {
        fopen64_real = dlsym(RTLD_NEXT, "fopen64");
    };

    char buf[PATH_MAX];
    return fopen64_real(rewrite(path, buf), mode);
}

int __xstat(int ver, const char * path, struct stat * st)
{
    static int (*__xstat_real) (int ver, const char *, struct stat *) = NULL;

    if (__xstat_real == NULL) {
        __xstat_real = dlsym(RTLD_NEXT, "__xstat");
    };

    char buf[PATH_MAX];
    return __xstat_real(ver, rewrite(path, buf), st);
}

int __xstat64(int ver, const char * path, struct stat64 * st)
{
    static int (*__xstat64_real) (int ver, const char *, struct stat64 *) = NULL;

    if (__xstat64_real == NULL) {
        __xstat64_real =  dlsym(RTLD_NEXT, "__xstat64");
    };

    char buf[PATH_MAX];
    return __xstat64_real(ver, rewrite(path, buf), st);
}

int * access(const char * path, int mode)
{
    static int * (*access_real) (const char *, int mode) = NULL;

    if (access_real == NULL) {
        access_real = dlsym(RTLD_NEXT, "access");
    };

    char buf[PATH_MAX];
    return access_real(rewrite(path, buf), mode);
}

int posix_spawn(pid_t * pid, const char * path,
    const posix_spawn_file_actions_t * file_actions,
    const posix_spawnattr_t * attrp,
    char * const argv[], char * const envp[])
{
    static int (*posix_spawn_real) (pid_t *, const char *,
        const posix_spawn_file_actions_t *,
        const posix_spawnattr_t *,
        char * const argv[], char * const envp[]) = NULL;

    if (posix_spawn_real == NULL) {
        posix_spawn_real = dlsym(RTLD_NEXT, "posix_spawn");
    }

    char buf[PATH_MAX];
    return posix_spawn_real(pid, rewrite(path, buf), file_actions, attrp, argv, envp);
}

int execv(const char *path, char *const argv[])
{
    static int (*execv_real) (const char *path, char *const argv[]) = NULL;

    if (execv_real == NULL) {
        execv_real = dlsym(RTLD_NEXT, "execv");
    };

    char buf[PATH_MAX];
    return execv_real(rewrite(path, buf), argv);
}
