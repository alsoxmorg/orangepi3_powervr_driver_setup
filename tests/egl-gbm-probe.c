#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <gbm.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <libdrm/drm.h>

/* No KMS commits, screen changes, window system or shader compiler required.
 * Clear an RGBA FBO on the selected GBM device and check every returned pixel.
 * Also import a GBM dma-buf as a renderbuffer and verify its pixels. With
 * --display-node, allocate on that display device and import on the render GPU.
 */
static int check_pixels(int size) {
    unsigned char pixels[64 * 64 * 4];
    memset(pixels, 0, sizeof(pixels));
    glViewport(0, 0, size, size);
    glDisable(GL_DITHER);
    glClearColor(1.0f, 0.0f, 1.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glFinish();
    glReadPixels(0, 0, size, size, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    GLenum error = glGetError();
    if (error != GL_NO_ERROR) { fprintf(stderr, "GL error: 0x%x\n", error); return 1; }
    for (int i = 0; i < size * size * 4; i += 4) {
        if (pixels[i] != 255 || pixels[i+1] != 0 || pixels[i+2] != 255 || pixels[i+3] != 255) {
            fprintf(stderr, "Pixel mismatch at %d: %u,%u,%u,%u\n", i / 4,
                    pixels[i], pixels[i+1], pixels[i+2], pixels[i+3]); return 1;
        }
    }
    return 0;
}

int main(int argc, char **argv) {
    int result = 1, fd = -1, export_fd = -1, display_fd = -1;
    struct gbm_device *gbm = NULL;
    struct gbm_device *display_gbm = NULL;
    struct gbm_bo *bo = NULL;
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface surface = EGL_NO_SURFACE;
    EGLImageKHR image = EGL_NO_IMAGE_KHR;
    PFNEGLDESTROYIMAGEKHRPROC destroy_image = NULL;
    GLuint texture = 0, framebuffer = 0, renderbuffer = 0;
    const char *path = argc > 1 ? argv[1] : "/dev/dri/renderD128";
    const char *display_path = NULL;
    int check_prime = argc == 5 && !strcmp(argv[4], "--check-prime");
    setvbuf(stdout, NULL, _IOLBF, 0);
    if ((argc == 4 || check_prime) && !strcmp(argv[2], "--display-node")) display_path = argv[3];
    else if (argc > 2) {
        fprintf(stderr, "Usage: %s [DRM_NODE] [--display-node DISPLAY_NODE [--check-prime]]\n", argv[0]);
        return 2;
    }
    printf("Device: %s\n", path);
    fd = open(path, O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("open DRM node"); goto done; }
    gbm = gbm_create_device(fd);
    if (!gbm) { fprintf(stderr, "gbm_create_device failed\n"); goto done; }
    printf("GBM backend: %s\n", gbm_device_get_backend_name(gbm));
    PFNEGLGETPLATFORMDISPLAYEXTPROC get_display =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    if (!get_display) { fprintf(stderr, "No EGL platform-display entry point\n"); goto done; }
    display = get_display(EGL_PLATFORM_GBM_KHR, gbm, NULL);
    EGLint major = 0, minor = 0, count = 0;
    if (display == EGL_NO_DISPLAY || !eglInitialize(display, &major, &minor)) {
        fprintf(stderr, "eglInitialize failed: 0x%x\n", eglGetError()); goto done;
    }
    printf("EGL %d.%d vendor: %s\n", major, minor, eglQueryString(display, EGL_VENDOR));
    printf("EGL APIs: %s\n", eglQueryString(display, EGL_CLIENT_APIS));
    if (!eglBindAPI(EGL_OPENGL_ES_API)) { fprintf(stderr, "eglBindAPI failed\n"); goto done; }
    EGLConfig config;
    EGLint attributes[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_SURFACE_TYPE, 0, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
    if (!eglChooseConfig(display, attributes, &config, 1, &count) || count < 1) {
        fprintf(stderr, "No GLES2 config: 0x%x\n", eglGetError()); goto done;
    }
    EGLint ctx_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    context = eglCreateContext(display, config, EGL_NO_CONTEXT, ctx_attributes);
    if (context == EGL_NO_CONTEXT) {
        fprintf(stderr, "eglCreateContext failed: 0x%x\n", eglGetError()); goto done;
    }
    const char *extensions = eglQueryString(display, EGL_EXTENSIONS);
    if (!extensions || !strstr(extensions, "EGL_KHR_surfaceless_context")) {
        attributes[3] = EGL_PBUFFER_BIT;
        if (!eglChooseConfig(display, attributes, &config, 1, &count) || count < 1) {
            fprintf(stderr, "Neither surfaceless context nor pbuffer config supported\n"); goto done;
        }
        eglDestroyContext(display, context);
        context = eglCreateContext(display, config, EGL_NO_CONTEXT, ctx_attributes);
        if (context == EGL_NO_CONTEXT) { fprintf(stderr, "Pbuffer context failed\n"); goto done; }
        EGLint sizes[] = {EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE};
        surface = eglCreatePbufferSurface(display, config, sizes);
        if (surface == EGL_NO_SURFACE) { fprintf(stderr, "Pbuffer creation failed\n"); goto done; }
    }
    if (!eglMakeCurrent(display, surface, surface, context)) {
        fprintf(stderr, "eglMakeCurrent failed: 0x%x\n", eglGetError()); goto done;
    }
    const char *renderer = (const char *)glGetString(GL_RENDERER);
    printf("GL renderer: %s\n", renderer ? renderer : "(null)");
    printf("GL version: %s\n", glGetString(GL_VERSION));
    if (!renderer || !strstr(renderer, "PowerVR")) {
        fprintf(stderr, "FAIL: expected hardware PowerVR renderer\n"); goto done;
    }
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 16, 16, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr, "Framebuffer incomplete\n"); goto done;
    }
    if (check_pixels(16)) goto done;
    puts("PASS: PowerVR GLES clear/readback, all 256 pixels match");
    struct gbm_device *allocation_gbm = gbm;
    if (display_path) {
        printf("Cross-device display allocation: %s -> %s\n", display_path, path);
        display_fd = open(display_path, O_RDWR | O_CLOEXEC);
        if (display_fd < 0) { perror("open display node"); goto done; }
        display_gbm = gbm_create_device(display_fd);
        if (!display_gbm) { fprintf(stderr, "Display GBM device creation failed\n"); goto done; }
        allocation_gbm = display_gbm;
    }
    uint32_t usage = GBM_BO_USE_RENDERING;
    if (display_path || strstr(path, "/card")) usage |= GBM_BO_USE_SCANOUT;
    bo = gbm_bo_create(allocation_gbm, 64, 64, GBM_FORMAT_XRGB8888, usage);
    if (!bo) { fprintf(stderr, "XRGB8888 GBM allocation failed\n"); goto done; }
    if (gbm_bo_get_plane_count(bo) != 1) {
        fprintf(stderr, "Expected single-plane XRGB8888 buffer\n"); goto done;
    }
    export_fd = gbm_bo_get_fd(bo);
    if (export_fd < 0) { perror("dma-buf export"); goto done; }
    if (check_prime) {
        struct drm_prime_handle prime = {.fd = export_fd};
        if (ioctl(fd, DRM_IOCTL_PRIME_FD_TO_HANDLE, &prime) != 0) {
            fprintf(stderr, "FAIL: kernel PRIME FD-to-handle import on %s: %s (errno=%d)\n",
                path, strerror(errno), errno);
            goto done;
        }
        struct drm_gem_close close_handle = {.handle = prime.handle};
        if (ioctl(fd, DRM_IOCTL_GEM_CLOSE, &close_handle) != 0) {
            perror("close PRIME GEM handle"); goto done;
        }
        puts("PASS: kernel PRIME FD-to-handle import and GEM handle close");
    }
    printf("GBM XRGB8888 stride=%u offset=%u modifier=0x%016llx\n",
        gbm_bo_get_stride(bo), gbm_bo_get_offset(bo, 0),
        (unsigned long long)gbm_bo_get_modifier(bo));
    PFNEGLCREATEIMAGEKHRPROC create_image =
        (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
    destroy_image = (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
    PFNGLEGLIMAGETARGETRENDERBUFFERSTORAGEOESPROC bind_image =
        (PFNGLEGLIMAGETARGETRENDERBUFFERSTORAGEOESPROC)eglGetProcAddress("glEGLImageTargetRenderbufferStorageOES");
    if (!create_image || !destroy_image || !bind_image) {
        fprintf(stderr, "Missing EGLImage renderbuffer entry points\n"); goto done;
    }
    /* Deliberately omit modifier attributes: this is the legacy implicit path
     * selected by WLR_EGL_NO_MODIFIERS=1 and WLR_DRM_NO_MODIFIERS=1. */
    EGLint image_attributes[] = {
        EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_LINUX_DRM_FOURCC_EXT, GBM_FORMAT_XRGB8888,
        EGL_DMA_BUF_PLANE0_FD_EXT, export_fd,
        EGL_DMA_BUF_PLANE0_OFFSET_EXT, (EGLint)gbm_bo_get_offset(bo, 0),
        EGL_DMA_BUF_PLANE0_PITCH_EXT, (EGLint)gbm_bo_get_stride(bo), EGL_NONE};
    image = create_image(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, image_attributes);
    if (image == EGL_NO_IMAGE_KHR) {
        fprintf(stderr, "Implicit XRGB8888 dma-buf import failed: EGL 0x%x\n", eglGetError()); goto done;
    }
    glGenRenderbuffers(1, &renderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, renderbuffer);
    bind_image(GL_RENDERBUFFER, image);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, renderbuffer);
    if (glGetError() != GL_NO_ERROR || glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr, "Imported dma-buf is not a renderable framebuffer\n"); goto done;
    }
    if (check_pixels(64)) goto done;
    puts("PASS: implicit XRGB8888 dma-buf import/render/readback, all 4096 pixels match");
    if (usage & GBM_BO_USE_SCANOUT) puts("PASS: display SCANOUT|RENDERING allocation and dma-buf export/import");
    result = 0;
done:
    if (display != EGL_NO_DISPLAY && context != EGL_NO_CONTEXT) {
        /* Only delete GL objects when our context is actually current. */
        if (eglGetCurrentContext() == context) {
            if (framebuffer) glDeleteFramebuffers(1, &framebuffer);
            if (renderbuffer) glDeleteRenderbuffers(1, &renderbuffer);
            if (texture) glDeleteTextures(1, &texture);
        }
        if (image != EGL_NO_IMAGE_KHR && destroy_image) destroy_image(display, image);
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (surface != EGL_NO_SURFACE) eglDestroySurface(display, surface);
        eglDestroyContext(display, context);
    }
    if (display != EGL_NO_DISPLAY) eglTerminate(display);
    if (export_fd >= 0) close(export_fd);
    if (bo) gbm_bo_destroy(bo);
    if (display_gbm) gbm_device_destroy(display_gbm);
    if (display_fd >= 0) close(display_fd);
    if (gbm) gbm_device_destroy(gbm);
    if (fd >= 0) close(fd);
    return result;
}
