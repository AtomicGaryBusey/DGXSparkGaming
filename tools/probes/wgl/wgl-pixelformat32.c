/* wgl-pixelformat32.c — why does SetPixelFormat fail under FEX?
 *
 * WHY THIS EXISTS
 *   Every id Tech 4 title tested under FEX dies at the same place:
 *       ...PIXELFORMAT 1 selected
 *       ...SetPixelFormat failed
 *       Fatal Error: Unable to initialize OpenGL
 *   The same titles get a GL context under Box64 and Quake 4 actually plays.
 *   So this, not the famous x87 assertion, is FEX's real id Tech 4 blocker --
 *   the assertion never fires at all.
 *
 *   id Tech 4 reports only "failed", with no error code, so the engine cannot
 *   tell you which call broke or why. This replicates its exact WGL sequence and
 *   reports GetLastError at every step, plus how many pixel formats the driver
 *   offers and what DescribePixelFormat says about the one being chosen.
 *
 *   A ~40-line probe answers in seconds what a game launch answers in minutes,
 *   and it can be run under both translators with everything else identical.
 *
 * BUILD (32-bit, matching every id Tech 4 title here):
 *   i686-w64-mingw32-gcc-win32 -O1 -o wglpf.exe wgl-pixelformat32.c -lopengl32 -lgdi32
 *   (toolchain from tools/setup-mingw.sh MINGW_ARCH=i686)
 *
 * RUN under both, with the same Proton:
 *   tools/run-both.sh --wine /path/to/wglpf.exe
 *
 * READING IT
 *   Formats == 0            the driver/ICD offered nothing -- a loader problem,
 *                           not a translation one.
 *   ChoosePixelFormat == 0  the requested attributes cannot be matched.
 *   SetPixelFormat == 0     the interesting case, and what the games hit. The
 *                           error code says whether it is a bad format index, a
 *                           bad DC, or the format already being set.
 *   Compare the two runtimes: if they differ, the translator is implicated. If
 *   they fail IDENTICALLY, suspect this probe before either JIT.
 */
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#include <stdlib.h>

static void step(const char *what, int ok) {
    DWORD e = GetLastError();
    printf("  %-28s %-4s  GetLastError=%lu (0x%08lx)\n",
           what, ok ? "ok" : "FAIL", (unsigned long)e, (unsigned long)e);
    SetLastError(0);
}

int main(void) {
    printf("WGL pixel-format probe (32-bit)\n");
    printf("--------------------------------------------------------------\n");

    WNDCLASSA wc;
    ZeroMemory(&wc, sizeof wc);
    wc.lpfnWndProc   = DefWindowProcA;
    wc.hInstance     = GetModuleHandleA(NULL);
    wc.lpszClassName = "wglprobe";
    wc.style         = CS_OWNDC;          /* id Tech 4 uses CS_OWNDC too */
    SetLastError(0);
    step("RegisterClassA", RegisterClassA(&wc) != 0);

    HWND w = CreateWindowExA(0, "wglprobe", "wglprobe", WS_OVERLAPPEDWINDOW,
                             0, 0, 640, 480, NULL, NULL, wc.hInstance, NULL);
    step("CreateWindowExA", w != NULL);
    if (!w) return 1;

    HDC dc = GetDC(w);
    step("GetDC", dc != NULL);
    if (!dc) return 1;

    /* How many formats does this DC actually offer? id Tech 4 never asks. */
    PIXELFORMATDESCRIPTOR probe;
    ZeroMemory(&probe, sizeof probe);
    probe.nSize = sizeof probe;
    int n = DescribePixelFormat(dc, 1, sizeof probe, &probe);
    printf("  %-28s %d\n", "formats available", n);
    if (n > 0)
        printf("  %-28s flags=0x%08lx cColorBits=%u cDepthBits=%u iPixelType=%u\n",
               "  format 1 describes as", (unsigned long)probe.dwFlags,
               probe.cColorBits, probe.cDepthBits, probe.iPixelType);

    PIXELFORMATDESCRIPTOR pfd;
    ZeroMemory(&pfd, sizeof pfd);
    pfd.nSize      = sizeof pfd;
    pfd.nVersion   = 1;
    pfd.dwFlags    = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.cStencilBits = 8;

    SetLastError(0);
    int pf = ChoosePixelFormat(dc, &pfd);
    printf("  %-28s %d\n", "ChoosePixelFormat ->", pf);
    step("ChoosePixelFormat", pf != 0);

    /* id Tech 4 selects format 1 explicitly in the failing logs, so try both:
       whatever ChoosePixelFormat picked, then format 1 on a FRESH DC (a DC can
       only have its pixel format set once, so reusing it would confuse the
       result). */
    if (pf) {
        SetLastError(0);
        step("SetPixelFormat(chosen)", SetPixelFormat(dc, pf, &pfd) != 0);
        SetLastError(0);
        HGLRC rc = wglCreateContext(dc);
        step("wglCreateContext", rc != NULL);
        if (rc) {
            SetLastError(0);
            step("wglMakeCurrent", wglMakeCurrent(dc, rc) != 0);
            const char *ver = (const char *)glGetString(GL_VERSION);
            const char *ren = (const char *)glGetString(GL_RENDERER);
            printf("  %-28s %s\n", "GL_VERSION", ver ? ver : "(null)");
            printf("  %-28s %s\n", "GL_RENDERER", ren ? ren : "(null)");
            wglMakeCurrent(NULL, NULL);
            wglDeleteContext(rc);
        }
    }

    ReleaseDC(w, dc);
    DestroyWindow(w);

    HWND w2 = CreateWindowExA(0, "wglprobe", "wglprobe2", WS_OVERLAPPEDWINDOW,
                              0, 0, 640, 480, NULL, NULL, wc.hInstance, NULL);
    HDC dc2 = w2 ? GetDC(w2) : NULL;
    if (dc2) {
        SetLastError(0);
        /* This is literally what the failing engines do. */
        step("SetPixelFormat(format 1)", SetPixelFormat(dc2, 1, &pfd) != 0);
        ReleaseDC(w2, dc2);
    }
    if (w2) DestroyWindow(w2);

    printf("--------------------------------------------------------------\n");
    /* Hold the process open so its /proc/<pid>/maps can be inspected — the
     * question "is FEX's 32-bit GL thunk actually loaded?" is answered by what
     * is mapped, not by what the config file says. Off unless asked for. */
    if (getenv("WGLPROBE_SLEEP")) {
        printf("  sleeping %s ms for maps inspection\n", getenv("WGLPROBE_SLEEP"));
        fflush(stdout);
        Sleep((DWORD)atoi(getenv("WGLPROBE_SLEEP")));
    }
    printf("id Tech 4 logs \"PIXELFORMAT 1 selected\" then \"SetPixelFormat failed\",\n");
    printf("so the last line above is the one that matters.\n");
    return 0;
}
