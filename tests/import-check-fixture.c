/* A fake public API provider tests helper behavior without graphics hardware.
 * These structs belong to the fixture; the helper only sees opaque pointers. */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

struct wl_display { int id; };
struct wlr_renderer { bool alive; };
struct wlr_dmabuf_attributes { bool importable; };
struct wlr_texture { int unused; };
struct wlr_linux_dmabuf_v1 {
    struct wl_display *display;
    bool (*check)(struct wlr_dmabuf_attributes *, void *);
    void *data;
};

#ifdef FIXTURE_LIBRARY
static struct wlr_linux_dmabuf_v1 *managers[8];
static unsigned attempts, created, destroyed;
struct wlr_linux_dmabuf_v1 *wlr_linux_dmabuf_v1_create_with_renderer(
        struct wl_display *display, uint32_t version, struct wlr_renderer *renderer) {
    (void)version; (void)renderer;
    for (unsigned i = 0; i < 8; i++) {
        if (managers[i]) continue;
        managers[i] = calloc(1, sizeof(*managers[i]));
        assert(managers[i]);
        managers[i]->display = display;
        return managers[i];
    }
    return NULL;
}
void wlr_linux_dmabuf_v1_set_check_dmabuf_callback(struct wlr_linux_dmabuf_v1 *manager,
        bool (*check)(struct wlr_dmabuf_attributes *, void *), void *data) {
    manager->check = check; manager->data = data;
}
struct wlr_texture *wlr_texture_from_dmabuf(struct wlr_renderer *renderer,
        struct wlr_dmabuf_attributes *attributes) {
    attempts++;
    assert(renderer->alive);
    if (!attributes->importable) return NULL;
    created++;
    return calloc(1, sizeof(struct wlr_texture));
}
void wlr_texture_destroy(struct wlr_texture *texture) { assert(texture); destroyed++; free(texture); }
void wlr_renderer_destroy(struct wlr_renderer *renderer) { renderer->alive = false; }
void wl_display_destroy(struct wl_display *display) {
    for (unsigned i = 0; i < 8; i++) {
        if (managers[i] && managers[i]->display == display) { free(managers[i]); managers[i] = NULL; }
    }
}
unsigned fixture_attempts(void) { return attempts; }
void fixture_check_resources(void) { assert(created == destroyed); }
#else
struct wlr_linux_dmabuf_v1 *wlr_linux_dmabuf_v1_create_with_renderer(
    struct wl_display *, uint32_t, struct wlr_renderer *);
void wlr_renderer_destroy(struct wlr_renderer *);
void wl_display_destroy(struct wl_display *);
unsigned fixture_attempts(void);
void fixture_check_resources(void);
int main(void) {
    struct wl_display a = {1}, b = {2};
    struct wlr_renderer ra = {true}, rb = {true};
    struct wlr_dmabuf_attributes good = {true}, bad = {false};
    struct wlr_linux_dmabuf_v1 *ma = wlr_linux_dmabuf_v1_create_with_renderer(&a, 4, &ra);
    struct wlr_linux_dmabuf_v1 *mb = wlr_linux_dmabuf_v1_create_with_renderer(&b, 4, &rb);
    assert(ma && mb && ma->check && mb->check);
    assert(ma->check(&good, ma->data));
    assert(!ma->check(&bad, ma->data));
    assert(fixture_attempts() == 2);
    fixture_check_resources();
    wlr_renderer_destroy(&ra);
    assert(!ma->check(&good, ma->data));
    assert(fixture_attempts() == 2); /* No call through a destroyed renderer. */
    assert(mb->check(&good, mb->data)); /* Other manager remains usable. */
    wl_display_destroy(&a);
    assert(mb->check(&good, mb->data));
    fixture_check_resources();
    wl_display_destroy(&b);
    wlr_renderer_destroy(&rb);
    puts("PASS: renderer validation accepts/rejects, releases textures, isolates managers and rejects destroyed renderer");
    return 0;
}
#endif
