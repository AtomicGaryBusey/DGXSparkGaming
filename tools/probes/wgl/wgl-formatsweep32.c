/* wgl-formatsweep32.c — can ANY pixel format be set, or none?
 *
 * WHY THIS EXISTS
 *   wgl-pixelformat32.c showed that a 32-bit PE under FEX fails SetPixelFormat
 *   on format 1 with GetLastError()==0, while the SAME SOURCE built 64-bit
 *   succeeds under FEX and the 32-bit build succeeds under Box64. That tested
 *   one format, which cannot distinguish:
 *
 *     "format 1 is unusable here"     -> a workaround exists: pick another
 *     "no format can ever be set"     -> the GLX drawable path is broken
 *
 *   id Tech 4 asks for format 1 specifically ("PIXELFORMAT 1 selected"), so if
 *   some other format works the games are one launch option away from running.
 *   That is worth one probe.
 *
 *   SetPixelFormat may only be called ONCE per window, so each format gets a
 *   fresh window. The windows are never shown -- this must stay runnable while
 *   someone is working on the machine.
 *
 * BUILD:
 *   i686-w64-mingw32-gcc-win32 -O1 -o fmt32.exe wgl-formatsweep32.c \
 *       -lopengl32 -lgdi32 -luser32
 */
#include <windows.h>
#include <stdio.h>

int main(void) {
    WNDCLASSA wc; ZeroMemory(&wc, sizeof wc);
    wc.lpfnWndProc = DefWindowProcA; wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "fmtsweep";
    RegisterClassA(&wc);

    HWND w0 = CreateWindowExA(0, "fmtsweep", "fmtsweep", WS_OVERLAPPEDWINDOW,
                              0, 0, 64, 64, NULL, NULL, wc.hInstance, NULL);
    HDC d0 = GetDC(w0);
    PIXELFORMATDESCRIPTOR pfd; ZeroMemory(&pfd, sizeof pfd);
    int total = DescribePixelFormat(d0, 1, sizeof pfd, &pfd);
    printf("formats reported by the driver: %d\n", total);
    ReleaseDC(w0, d0); DestroyWindow(w0);

    int ok = 0, fail = 0, ctx = 0, first_ok = 0, first_ctx = 0;
    for (int f = 1; f <= total; f++) {
        HWND w = CreateWindowExA(0, "fmtsweep", "fmtsweep", WS_OVERLAPPEDWINDOW,
                                 0, 0, 64, 64, NULL, NULL, wc.hInstance, NULL);
        if (!w) break;
        HDC d = GetDC(w);
        PIXELFORMATDESCRIPTOR p; ZeroMemory(&p, sizeof p);
        DescribePixelFormat(d, f, sizeof p, &p);
        if (SetPixelFormat(d, f, &p)) {
            ok++;
            if (!first_ok) first_ok = f;
            HGLRC rc = wglCreateContext(d);
            if (rc) { ctx++; if (!first_ctx) first_ctx = f; wglDeleteContext(rc); }
        } else {
            fail++;
        }
        ReleaseDC(w, d); DestroyWindow(w);
    }
    printf("SetPixelFormat  succeeded on %d / %d formats (first ok: %d)\n", ok, total, first_ok);
    printf("wglCreateContext succeeded on %d formats (first ok: %d)\n", ctx, first_ctx);
    if (ok == 0)
        printf("VERDICT: NO format can be set -> the GLX drawable path is broken,\n"
               "         not a bad choice of format. No launch-option workaround exists.\n");
    else if (first_ok != 1)
        printf("VERDICT: format 1 is unusable but %d works -> a workaround may exist.\n", first_ok);
    else
        printf("VERDICT: format 1 works here.\n");
    return 0;
}
