#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

/* Public wlroots 0.18 functions, loaded dynamically so building this tool
 * does not require compositor development headers. No structure layouts or
 * private APIs are assumed. Creating a renderer never acquires DRM master. */
struct wlr_renderer;
struct wlr_drm_format_set;

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (argc != 2) {
        fprintf(stderr, "Usage: %s /dev/dri/renderD128\n", argv[0]);
        return 2;
    }
    void *library = dlopen("libwlroots-0.18.so", RTLD_NOW | RTLD_LOCAL);
    if (!library) { fprintf(stderr, "wlroots 0.18: %s\n", dlerror()); return 1; }
    struct wlr_renderer *(*create)(int) = dlsym(library, "wlr_gles2_renderer_create_with_drm_fd");
    const struct wlr_drm_format_set *(*get_formats)(struct wlr_renderer *) =
        dlsym(library, "wlr_renderer_get_render_formats");
    bool (*has)(const struct wlr_drm_format_set *, uint32_t, uint64_t) =
        dlsym(library, "wlr_drm_format_set_has");
    void (*destroy)(struct wlr_renderer *) = dlsym(library, "wlr_renderer_destroy");
    if (!create || !get_formats || !has || !destroy) {
        fprintf(stderr, "Required wlroots 0.18 API unavailable\n");
        dlclose(library); return 1;
    }
    int fd = open(argv[1], O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("open render node"); dlclose(library); return 1; }
    struct wlr_renderer *renderer = create(fd);
    int result = 1;
    if (!renderer) { fprintf(stderr, "wlroots GLES renderer creation failed\n"); goto done; }
    const struct wlr_drm_format_set *formats = get_formats(renderer);
    const uint32_t xrgb8888 = UINT32_C(0x34325258);
    const uint64_t implicit = UINT64_C(0x00ffffffffffffff);
    bool implicit_ok = formats && has(formats, xrgb8888, implicit);
    bool linear_ok = formats && has(formats, xrgb8888, 0);
    printf("wlroots XRGB8888 render formats: implicit=%s linear=%s\n",
        implicit_ok ? "yes" : "no", linear_ok ? "yes" : "no");
    if (!implicit_ok) {
        fprintf(stderr, "FAIL: wlroots rejects the HDMI render format; do not start DRM Sway\n");
        goto done;
    }
    puts("PASS: actual wlroots renderer accepts implicit XRGB8888");
    result = 0;
done:
    if (renderer) destroy(renderer);
    close(fd);
    dlclose(library);
    return result;
}
