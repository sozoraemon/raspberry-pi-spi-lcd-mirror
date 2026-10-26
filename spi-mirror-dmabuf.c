#define _GNU_SOURCE
#include <wayland-client.h>
#include "wlr-export-dmabuf-unstable-v1-client-protocol.h"
#include <drm_fourcc.h>
#include <linux/dma-buf.h>
#include <sys/ioctl.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define OUT_W 480
#define OUT_H 320
#define OUTPUT_NAME "NOOP-1"
#define FB_DEVICE "/dev/fb0"
#define FRAME_BYTES (OUT_W * OUT_H * 2)

static struct wl_display *display;
static struct zwlr_export_dmabuf_manager_v1 *manager;
static struct wl_output *output;
static struct wl_output *candidates[32];
static int candidate_count;
static int output_found;

struct capture {
    void *data;
    size_t bytes;
    uint32_t format, width, height, stride, flags;
    uint64_t modifier;
    int fd, state, permanent;
    uint32_t num_objects, seen_objects;
    uint32_t offset;
};

static double seconds_now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static void dma_frame(void *data, struct zwlr_export_dmabuf_frame_v1 *frame,
                      uint32_t width, uint32_t height, uint32_t offset_x, uint32_t offset_y,
                      uint32_t buffer_flags, uint32_t flags, uint32_t format,
                      uint32_t mod_high, uint32_t mod_low, uint32_t num_objects) {
    (void)frame; (void)flags;
    struct capture *c = data;
    c->width = width; c->height = height; c->format = format;
    c->modifier = ((uint64_t)mod_high << 32) | mod_low;
    c->num_objects = num_objects;
    c->flags = buffer_flags;
    if (offset_x || offset_y || !width || !height || num_objects != 1 ||
        (format != DRM_FORMAT_XRGB8888 && format != DRM_FORMAT_ARGB8888 &&
         format != DRM_FORMAT_XBGR8888 && format != DRM_FORMAT_ABGR8888) ||
        (c->modifier != DRM_FORMAT_MOD_LINEAR)) {
        fprintf(stderr, "DMA-BUF not CPU-linear-compatible: fourcc=0x%08x modifier=0x%016llx objects=%u crop=%u,%u\n",
                format, (unsigned long long)c->modifier, num_objects, offset_x, offset_y);
        c->permanent = 1;
    }
}
static void dma_object(void *data, struct zwlr_export_dmabuf_frame_v1 *frame,
                       uint32_t index, int32_t fd, uint32_t size,
                       uint32_t offset, uint32_t stride, uint32_t plane_index) {
    (void)frame;
    struct capture *c = data;
    ++c->seen_objects;
    if (index != 0 || plane_index != 0 || c->fd >= 0 ||
        !stride || stride < c->width * 4 ||
        (uint64_t)offset + (uint64_t)stride * c->height > size) {
        fprintf(stderr, "Unsupported DMA-BUF plane layout\n");
        c->permanent = 1;
        close(fd);
        return;
    }
    c->fd = fd;
    c->bytes = size;
    c->offset = offset;
    c->stride = stride;
}
static void dma_ready(void *data, struct zwlr_export_dmabuf_frame_v1 *frame,
                      uint32_t hi, uint32_t lo, uint32_t nsec) {
    (void)frame; (void)hi; (void)lo; (void)nsec;
    ((struct capture *)data)->state = 1;
}
static void dma_cancel(void *data, struct zwlr_export_dmabuf_frame_v1 *frame, uint32_t reason) {
    (void)frame;
    struct capture *c = data;
    c->state = -1;
    if (reason == ZWLR_EXPORT_DMABUF_FRAME_V1_CANCEL_REASON_PERMANENT) c->permanent = 1;
}
static const struct zwlr_export_dmabuf_frame_v1_listener frame_listener = {
    .frame = dma_frame, .object = dma_object, .ready = dma_ready, .cancel = dma_cancel
};

/* dma-buf sync must bracket CPU access when supported by the exporter. */
static int dmabuf_sync(int fd, uint64_t flags) {
    struct dma_buf_sync sync = { .flags = flags };
    if (ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync) == 0) return 0;
    if (errno == ENOTTY || errno == EINVAL) return 0; /* not supported by this exporter */
    perror("DMA_BUF_IOCTL_SYNC");
    return -1;
}

static void output_geometry(void *data, struct wl_output *o, int32_t x, int32_t y,
                            int32_t pw, int32_t ph, int32_t subpixel,
                            const char *make, const char *model, int32_t transform) {
    (void)data; (void)o; (void)x; (void)y; (void)pw; (void)ph;
    (void)subpixel; (void)make; (void)model; (void)transform;
}
static void output_mode(void *data, struct wl_output *o, uint32_t flags,
                        int32_t width, int32_t height, int32_t refresh) {
    (void)data; (void)o; (void)flags; (void)width; (void)height; (void)refresh;
}
static void output_done(void *data, struct wl_output *o) { (void)data; (void)o; }
static void output_scale(void *data, struct wl_output *o, int32_t factor) {
    (void)data; (void)o; (void)factor;
}
static void output_name(void *data, struct wl_output *o, const char *name) {
    (void)data;
    if (strcmp(name, OUTPUT_NAME) == 0) { output = o; output_found = 1; }
}
static void output_description(void *data, struct wl_output *o, const char *description) {
    (void)data; (void)o; (void)description;
}
static const struct wl_output_listener output_listener = {
    .geometry = output_geometry, .mode = output_mode, .done = output_done,
    .scale = output_scale, .name = output_name, .description = output_description
};

static void registry_global(void *data, struct wl_registry *registry,
                            uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    if (!strcmp(interface, zwlr_export_dmabuf_manager_v1_interface.name)) {
        manager = wl_registry_bind(registry, name, &zwlr_export_dmabuf_manager_v1_interface, 1);
    } else if (!strcmp(interface, wl_output_interface.name) && candidate_count < 32) {
        if (version < 4) return; /* wl_output.name is required */
        struct wl_output *o = wl_registry_bind(registry, name, &wl_output_interface, 4);
        wl_output_add_listener(o, &output_listener, NULL);
        candidates[candidate_count++] = o;
    }
}
static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}
static const struct wl_registry_listener registry_listener = {
    .global = registry_global, .global_remove = registry_remove
};

static inline void get_rgb(const struct capture *c, int x, int y,
                           int *r, int *g, int *b) {
    if (c->flags & 1) /* zwp_linux_buffer_params_v1 Y_INVERT */
        y = (int)c->height - 1 - y;
    const uint8_t *p = (const uint8_t *)c->data + c->offset + (size_t)y * c->stride + x * 4;
    if (c->format == DRM_FORMAT_XRGB8888 || c->format == DRM_FORMAT_ARGB8888) {
        *b = p[0]; *g = p[1]; *r = p[2];
    } else {
        *r = p[0]; *g = p[1]; *b = p[2];
    }
}

/* Bilinear scale to 480x320, pack little-endian RGB565. */
static void convert_frame(const struct capture *c, uint8_t *dst) {
    for (int y = 0; y < OUT_H; ++y) {
        int fy = (int)(((int64_t)(2*y+1) * c->height * 128) / OUT_H) - 128;
        int y0 = fy >> 8, wy = fy & 255;
        if (y0 < 0) { y0 = 0; wy = 0; }
        if (y0 >= (int)c->height - 1) { y0 = (int)c->height - 1; wy = 0; }
        int y1 = y0 + (y0 < (int)c->height - 1);
        for (int x = 0; x < OUT_W; ++x) {
            int fx = (int)(((int64_t)(2*x+1) * c->width * 128) / OUT_W) - 128;
            int x0 = fx >> 8, wx = fx & 255;
            if (x0 < 0) { x0 = 0; wx = 0; }
            if (x0 >= (int)c->width - 1) { x0 = (int)c->width - 1; wx = 0; }
            int x1 = x0 + (x0 < (int)c->width - 1);
            int r00,g00,b00,r10,g10,b10,r01,g01,b01,r11,g11,b11;
            get_rgb(c,x0,y0,&r00,&g00,&b00);
            get_rgb(c,x1,y0,&r10,&g10,&b10);
            get_rgb(c,x0,y1,&r01,&g01,&b01);
            get_rgb(c,x1,y1,&r11,&g11,&b11);
            int w00=(256-wx)*(256-wy), w10=wx*(256-wy);
            int w01=(256-wx)*wy, w11=wx*wy;
            int r=(r00*w00+r10*w10+r01*w01+r11*w11+32768)>>16;
            int g=(g00*w00+g10*w10+g01*w01+g11*w11+32768)>>16;
            int b=(b00*w00+b10*w10+b01*w01+b11*w11+32768)>>16;
            uint16_t rgb565 = (uint16_t)(((r & 0xf8)<<8) | ((g & 0xfc)<<3) | (b>>3));
            size_t pos = ((size_t)y*OUT_W+x)*2;
            dst[pos] = (uint8_t)rgb565;
            dst[pos+1] = (uint8_t)(rgb565 >> 8);
        }
    }
}

static int write_frame(int fd, const uint8_t *data) {
    if (lseek(fd, 0, SEEK_SET) < 0) { perror("lseek /dev/fb0"); return -1; }
    size_t offset = 0;
    while (offset < FRAME_BYTES) {
        ssize_t n = write(fd, data + offset, FRAME_BYTES - offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { perror("write /dev/fb0"); return -1; }
        offset += (size_t)n;
    }
    return 0;
}

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "Cannot connect to Wayland. Check XDG_RUNTIME_DIR and WAYLAND_DISPLAY.\n"); return 1; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || wl_display_roundtrip(display) < 0 ||
        !manager || !output_found) {
        fprintf(stderr, "Missing Wayland capability or output %s\n", OUTPUT_NAME);
        return 1;
    }
    int fb = open(FB_DEVICE, O_WRONLY | O_CLOEXEC);
    if (fb < 0) { perror("open /dev/fb0"); return 1; }
    uint8_t *out = malloc(FRAME_BYTES);
    if (!out) { perror("malloc"); return 1; }
    fprintf(stderr, "DMA-BUF capturing %s -> %dx%d RGB565 /dev/fb0 (target 20FPS)\n", OUTPUT_NAME, OUT_W, OUT_H);
    double start = seconds_now();
    unsigned frames = 0;
    while (1) {
        double frame_start = seconds_now();
        struct capture c = { .fd = -1 };
        struct zwlr_export_dmabuf_frame_v1 *frame =
            zwlr_export_dmabuf_manager_v1_capture_output(manager, 0, output);
        if (!frame) { fprintf(stderr, "DMA-BUF capture request failed\n"); break; }
        zwlr_export_dmabuf_frame_v1_add_listener(frame, &frame_listener, &c);
        while (c.state == 0) {
            if (wl_display_dispatch(display) < 0) { c.state = -1; c.permanent = 1; break; }
        }
        if (c.state == 1 && !c.permanent && c.fd >= 0 && c.seen_objects == c.num_objects) {
            c.data = mmap(NULL, c.bytes, PROT_READ, MAP_SHARED, c.fd, 0);
            if (c.data == MAP_FAILED) {
                perror("DMA-BUF mmap (GPU buffer may not support CPU mapping)");
                c.data = NULL;
                c.permanent = 1;
            } else if (dmabuf_sync(c.fd, DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ) == 0) {
                convert_frame(&c, out);
                dmabuf_sync(c.fd, DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ);
                if (write_frame(fb, out) != 0) c.permanent = 1;
                else ++frames;
            } else c.permanent = 1;
        } else if (!c.permanent) {
            fprintf(stderr, "DMA-BUF capture canceled; retrying\n");
        }
        if (c.data) munmap(c.data, c.bytes);
        if (c.fd >= 0) close(c.fd);
        zwlr_export_dmabuf_frame_v1_destroy(frame);
        if (c.permanent) {
            fprintf(stderr, "DMA-BUF CPU access unsupported or fatal error; existing screencopy version remains available.\n");
            break;
        }
        double elapsed = seconds_now() - start;
        if (elapsed >= 10.0) {
            printf("FPS: %.1f\n", frames / elapsed);
            frames = 0;
            start = seconds_now();
        }
        double remaining = 0.05 - (seconds_now() - frame_start);
        if (remaining > 0) usleep((useconds_t)(remaining * 1000000));
    }
    free(out);
    close(fb);
    wl_display_disconnect(display);
    return 1;
}
