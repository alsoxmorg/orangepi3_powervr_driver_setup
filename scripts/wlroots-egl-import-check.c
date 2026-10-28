#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* Opt-in wlroots 0.18 experiment using public APIs only. The manager's ordinary
 * protocol/format validation remains intact; replace its kernel PRIME check
 * with an actual renderer texture import, not unconditional acceptance.
 * Loaded with ld.so --preload so exec'ed applications do not inherit it.
 */
struct wl_display;
struct wlr_renderer;
struct wlr_texture;
struct wlr_linux_dmabuf_v1;
struct wlr_dmabuf_attributes;
struct context {
    struct wl_display *display;
    struct wlr_renderer *renderer;
    struct context *next;
    unsigned accepted, rejected;
};
static struct context *contexts;
static struct wlr_texture *(*import_texture)(struct wlr_renderer *, struct wlr_dmabuf_attributes *);
static void (*destroy_texture)(struct wlr_texture *);

static void *required(const char *name) {
    void *symbol = dlsym(RTLD_NEXT, name);
    if (!symbol) {
        fprintf(stderr, "PowerVR import-check: missing API %s: %s\n", name, dlerror());
        abort();
    }
    return symbol;
}

static bool check_buffer(struct wlr_dmabuf_attributes *attributes, void *data) {
    struct context *context = data;
    if (!context->renderer) {
        fprintf(stderr, "PowerVR import-check: rejected after renderer destruction\n");
        return false;
    }
    struct wlr_texture *texture = import_texture(context->renderer, attributes);
    if (!texture) {
        context->rejected++;
        fprintf(stderr, "PowerVR import-check: renderer REJECTED DMA-BUF (%u rejected)\n", context->rejected);
        return false;
    }
    destroy_texture(texture);
    context->accepted++;
    if (context->accepted <= 4)
        fprintf(stderr, "PowerVR import-check: renderer ACCEPTED DMA-BUF (%u accepted)\n", context->accepted);
    return true;
}

struct wlr_linux_dmabuf_v1 *wlr_linux_dmabuf_v1_create_with_renderer(
        struct wl_display *display, uint32_t version, struct wlr_renderer *renderer) {
    struct wlr_linux_dmabuf_v1 *(*create)(struct wl_display *, uint32_t, struct wlr_renderer *) =
        required("wlr_linux_dmabuf_v1_create_with_renderer");
    void (*set_check)(struct wlr_linux_dmabuf_v1 *,
        bool (*)(struct wlr_dmabuf_attributes *, void *), void *) =
        required("wlr_linux_dmabuf_v1_set_check_dmabuf_callback");
    import_texture = required("wlr_texture_from_dmabuf");
    destroy_texture = required("wlr_texture_destroy");
    struct context *context = calloc(1, sizeof(*context));
    if (!context) return NULL;
    struct wlr_linux_dmabuf_v1 *manager = create(display, version, renderer);
    if (!manager) { free(context); return NULL; }
    context->display = display;
    context->renderer = renderer;
    context->next = contexts;
    contexts = context;
    set_check(manager, check_buffer, context);
    fprintf(stderr, "PowerVR import-check: installed actual renderer texture-import validation\n");
    return manager;
}

void wlr_renderer_destroy(struct wlr_renderer *renderer) {
    void (*destroy)(struct wlr_renderer *) = required("wlr_renderer_destroy");
    for (struct context *context = contexts; context; context = context->next)
        if (context->renderer == renderer) context->renderer = NULL;
    destroy(renderer);
}

void wl_display_destroy(struct wl_display *display) {
    void (*destroy)(struct wl_display *) = required("wl_display_destroy");
    destroy(display);
    struct context **link = &contexts;
    while (*link) {
        struct context *context = *link;
        if (context->display != display) { link = &context->next; continue; }
        fprintf(stderr, "PowerVR import-check: totals accepted=%u rejected=%u\n",
            context->accepted, context->rejected);
        *link = context->next;
        free(context);
    }
}
