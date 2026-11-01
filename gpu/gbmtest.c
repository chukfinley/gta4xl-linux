/* Render to a GBM scanout surface on Panfork, then read the buffer back in two ways:
 * glReadPixels and a CPU mapping of the dma-buf. No KMS master is necessary.
 * Build: gcc -O2 -o gbmtest gbmtest.c -I/usr/include/libdrm -lgbm -lEGL -lGLESv2 */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <fcntl.h>
#include <gbm.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define W 1200
#define H 2000

static const char *vs =
    "attribute vec4 p; attribute vec3 c; varying vec3 v;\n"
    "void main() { gl_Position = p; v = c; }\n";
static const char *fs =
    "precision mediump float; varying vec3 v; uniform sampler2D t;\n"
    "void main() { gl_FragColor = vec4(v, 1.0) * texture2D(t, vec2(0.25, 0.25)); }\n";

static GLuint sh(GLenum type, const char *src)
{
        GLuint s = glCreateShader(type);
        GLint ok;
        glShaderSource(s, 1, &src, NULL);
        glCompileShader(s);
        glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
        if (!ok) { fprintf(stderr, "shader error\n"); exit(1); }
        return s;
}

static void ppm(const char *path, const uint8_t *rgba, int w, int h, int stride, int bgra)
{
        FILE *f = fopen(path, "wb");
        fprintf(f, "P6\n%d %d\n255\n", w, h);
        for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                        const uint8_t *p = rgba + y * stride + x * 4;
                        uint8_t o[3] = { p[bgra ? 2 : 0], p[1], p[bgra ? 0 : 2] };
                        fwrite(o, 1, 3, f);
                }
        fclose(f);
}

int main(void)
{
        int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
        struct gbm_device *gbm = gbm_create_device(fd);
        if (!gbm) { perror("gbm_create_device"); return 1; }
        struct gbm_surface *surf = gbm_surface_create(gbm, W, H, GBM_FORMAT_XRGB8888,
                                                      GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
        if (!surf) { perror("gbm_surface_create"); return 1; }

        PFNEGLGETPLATFORMDISPLAYEXTPROC gpd = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
        EGLDisplay dpy = gpd(EGL_PLATFORM_GBM_KHR, gbm, NULL);
        eglInitialize(dpy, NULL, NULL);
        eglBindAPI(EGL_OPENGL_ES_API);
        EGLint ca[] = { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_DEPTH_SIZE, 24, EGL_NONE };
        EGLConfig cfgs[64], cfg = 0;
        EGLint n = 0;
        eglChooseConfig(dpy, ca, cfgs, 64, &n);
        for (int i = 0; i < n; i++) {
                EGLint id;
                eglGetConfigAttrib(dpy, cfgs[i], EGL_NATIVE_VISUAL_ID, &id);
                if (id == GBM_FORMAT_XRGB8888) { cfg = cfgs[i]; break; }
        }
        if (!cfg) { fprintf(stderr, "no XRGB config (%d configs)\n", n); return 1; }
        EGLint cta[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
        EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, cta);
        EGLSurface es = eglCreateWindowSurface(dpy, cfg, (EGLNativeWindowType)surf, NULL);
        if (es == EGL_NO_SURFACE) { fprintf(stderr, "eglCreateWindowSurface failed %x\n", eglGetError()); return 1; }
        eglMakeCurrent(dpy, es, es, ctx);
        printf("renderer: %s\n", glGetString(GL_RENDERER));

        GLuint pr = glCreateProgram();
        glAttachShader(pr, sh(GL_VERTEX_SHADER, vs));
        glAttachShader(pr, sh(GL_FRAGMENT_SHADER, fs));
        glBindAttribLocation(pr, 0, "p");
        glBindAttribLocation(pr, 1, "c");
        glLinkProgram(pr);
        glUseProgram(pr);

        /* 2x2 texture: the sampled texel is pure white, so a wrong sample shows as dark. */
        static const uint8_t tex[16] = { 255,255,255,255, 80,80,80,255, 80,80,80,255, 80,80,80,255 };
        GLuint t;
        glGenTextures(1, &t);
        glBindTexture(GL_TEXTURE_2D, t);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, tex);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

        /* Near red triangle over the left half, far green triangle drawn after it over all of
         * the screen, blue background in the corners. The depth test must keep red. */
        static const GLfloat v[] = {
                /* x y z w   r g b */
                -1.0, -1.0, -0.5, 1,  1, 0, 0,
                 0.0, -1.0, -0.5, 1,  1, 0, 0,
                -1.0,  1.0, -0.5, 1,  1, 0, 0,
                -0.9, -0.9,  0.5, 1,  0, 1, 0,
                 0.9, -0.9,  0.5, 1,  0, 1, 0,
                -0.9,  0.9,  0.5, 1,  0, 1, 0,
        };
        glEnableVertexAttribArray(0);
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(0, 4, GL_FLOAT, 0, 28, v);
        glVertexAttribPointer(1, 3, GL_FLOAT, 0, 28, v + 4);
        glEnable(GL_DEPTH_TEST);
        glViewport(0, 0, W, H);
        glClearColor(0, 0, 1, 1);

        for (int frame = 0; frame < 4; frame++) {
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
                glDrawArrays(GL_TRIANGLES, 0, 6);
                if (frame == 3)
                        break;
                eglSwapBuffers(dpy, es);
                struct gbm_bo *b = gbm_surface_lock_front_buffer(surf);
                if (!b) { fprintf(stderr, "lock_front_buffer failed\n"); return 1; }
                gbm_surface_release_buffer(surf, b);
        }

        static uint8_t rd[W * H * 4];
        glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, rd);
        printf("gl  (y up): near=%02x%02x%02x far=%02x%02x%02x bg=%02x%02x%02x\n",
               rd[(H/4*W + W/8)*4], rd[(H/4*W + W/8)*4+1], rd[(H/4*W + W/8)*4+2],
               rd[(H/4*W + W*5/8)*4], rd[(H/4*W + W*5/8)*4+1], rd[(H/4*W + W*5/8)*4+2],
               rd[((H-3)*W + W-3)*4], rd[((H-3)*W + W-3)*4+1], rd[((H-3)*W + W-3)*4+2]);
        ppm("/root/gbmtest-gl.ppm", rd, W, H, W * 4, 0);

        eglSwapBuffers(dpy, es);
        struct gbm_bo *bo = gbm_surface_lock_front_buffer(surf);
        if (!bo) { fprintf(stderr, "lock_front_buffer failed\n"); return 1; }
        int dfd = gbm_bo_get_fd(bo);
        int stride = gbm_bo_get_stride(bo);
        printf("scanout bo: %ux%u stride %d modifier %llx fd %d\n", gbm_bo_get_width(bo),
               gbm_bo_get_height(bo), stride, (unsigned long long)gbm_bo_get_modifier(bo), dfd);
        uint8_t *m = mmap(NULL, stride * H, PROT_READ, MAP_SHARED, dfd, 0);
        if (m == MAP_FAILED) {
                perror("mmap dma-buf");
        } else {
                ppm("/root/gbmtest-bo.ppm", m, W, H, stride, 1);
                const uint32_t *row = (const uint32_t *)(m + stride * (H - H / 4));
                printf("bo  (y dn): near=%08x far=%08x\n", row[W / 8], row[W * 5 / 8]);
        }
        return 0;
}
