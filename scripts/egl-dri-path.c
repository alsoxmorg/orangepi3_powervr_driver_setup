#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

/* Loaded with ld.so --preload, never LD_PRELOAD. Give this process's legacy
 * Mesa EGL loader a private DRI path without exporting LIBGL_DRIVERS_PATH
 * to applications launched by the compositor. Leave other getenv calls alone.
 */
extern char **environ;
static char *(*next_getenv)(const char *);

static char *environment_lookup(const char *name) {
    size_t length = strlen(name);
    if (!length || !environ) return NULL;
    for (char **entry = environ; *entry; ++entry) {
        if (!strncmp(*entry, name, length) && (*entry)[length] == '=')
            return *entry + length + 1;
    }
    return NULL;
}

__attribute__((constructor)) static void initialize(void) {
    /* The fallback handles any getenv calls made while dlsym initializes. */
    next_getenv = (char *(*)(const char *))dlsym(RTLD_NEXT, "getenv");
}

char *getenv(const char *name) {
    if (!strcmp(name, "LIBGL_DRIVERS_PATH")) {
        char *path = environment_lookup("POWERVR_PRIVATE_DRI_PATH");
        if (path && *path) return path;
    }
    return next_getenv ? next_getenv(name) : environment_lookup(name);
}
