/* mousefeel32.c — MEASURE the id Tech 4 mouse anomaly instead of describing it.
 *
 * WHY THIS EXISTS
 *   Prey (2006) and Quake 4 are both playable here under Box64 and both have
 *   "odd" mouse behaviour. Two explanations were published and both were wrong:
 *   the c0000005 flood beside them turned out to be a filesystem-status bug
 *   (notes/box64-bug-3-ntcreatefile-collision.md), and this directory's OWN
 *   earlier probe reported the DirectInput path clean.
 *
 *   That earlier probe was measuring the wrong thing. It used
 *       DISCL_NONEXCLUSIVE | DISCL_BACKGROUND
 *   and read the device once. id Tech 4 uses
 *       DISCL_EXCLUSIVE | DISCL_FOREGROUND, DIPROPAXISMODE_REL,
 *       DIPROP_BUFFERSIZE = 256, buffered GetDeviceData every frame
 *   (DOOM 3 / Quake 4 / Prey share win_input.cpp). Exclusive relative mode is a
 *   DIFFERENT path in Wine — it is where pointer grabs, cursor clipping and warp
 *   emulation live. "DirectInput is clean" was a true statement about code the
 *   games never execute.
 *
 * WHAT IT MEASURES
 *   It reads the SAME physical motion two ways at once and compares them:
 *
 *     DirectInput  exclusive + relative + buffered   <- what the game sees
 *     Win32 raw input (WM_INPUT)                     <- ground truth
 *
 *   Raw input is the control. It is a separate Wine code path that does no
 *   warping, no grabbing and no clipping, so if the two disagree about the same
 *   hand movement, the fault is in the DirectInput path and the SHAPE of the
 *   disagreement says which bug it is:
 *
 *     motion during the STILL phase, raw silent   -> spurious events. Classic
 *         warp-feedback: Wine recentres the pointer for exclusive mode and the
 *         recentring is not excluded from the motion stream, so the game reads
 *         its own warp back as player movement.
 *     DI travel MUCH GREATER than raw             -> duplicated/echoed deltas.
 *     DI travel MUCH LESS than raw                -> dropped events; check the
 *         buffer-overflow and lost-acquisition counters printed alongside.
 *     DI max delta clamped, raw not               -> saturation on fast flicks.
 *     DI and raw agree closely                    -> the input layer is FINE and
 *         the anomaly is above it (engine smoothing, frame timing) or below it
 *         (Xwayland pointer handling). Say so and look elsewhere; do not invent
 *         a fourth story, which is how this question wasted two prior rounds.
 *
 *   `absolute-flag` counts raw packets carrying MOUSE_MOVE_ABSOLUTE. A real
 *   mouse reports relative motion; absolute packets mean the pointer is being
 *   synthesised (remote desktop, tablet, or a compositor feeding warps back),
 *   which on Xwayland is a live possibility and would explain a lot.
 *
 * BUILD (32-bit, matching every id Tech 4 title here):
 *   ~/dgx-gaming-work/toolchain/root/usr/bin/i686-w64-mingw32-gcc-win32 \
 *       -O1 -o mousefeel32.exe mousefeel32.c -ldinput8 -ldxguid -lole32 -luser32
 *
 * RUN — needs a human moving a real mouse, and MUST be run under both runtimes:
 *   tools/mousefeel.sh          (wrapper: builds, runs, prints both side by side)
 *
 *   It opens a small window for ~20 s and takes an EXCLUSIVE grab of the mouse,
 *   so the cursor disappears while it runs. It always exits on its own; ESC also
 *   quits. Do not run it while something else needs the pointer.
 */
#define DIRECTINPUT_VERSION 0x0800
#include <windows.h>
#include <dinput.h>
#include <stdio.h>

#define BUFSZ      256      /* id Tech 4's DINPUT_BUFFERSIZE */
#define PHASE_MS  5000

static LONG g_rn, g_rsx, g_rsy, g_rabs, g_rmax, g_rabsolute;

static void raw_reset(void) { g_rn = g_rsx = g_rsy = g_rabs = g_rmax = g_rabsolute = 0; }

static LRESULT CALLBACK wp(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_INPUT) {
        UINT sz = 0;
        GetRawInputData((HRAWINPUT)l, RID_INPUT, NULL, &sz, sizeof(RAWINPUTHEADER));
        if (sz && sz <= 512) {
            BYTE b[512];
            if (GetRawInputData((HRAWINPUT)l, RID_INPUT, b, &sz, sizeof(RAWINPUTHEADER)) != (UINT)-1) {
                RAWINPUT *ri = (RAWINPUT *)b;
                if (ri->header.dwType == RIM_TYPEMOUSE) {
                    LONG dx = ri->data.mouse.lLastX, dy = ri->data.mouse.lLastY;
                    if (ri->data.mouse.usFlags & MOUSE_MOVE_ABSOLUTE) g_rabsolute++;
                    if (dx || dy) {
                        LONG a = dx < 0 ? -dx : dx;
                        g_rn++; g_rsx += dx; g_rsy += dy; g_rabs += a;
                        if (a > g_rmax) g_rmax = a;
                    }
                }
            }
        }
    }
    if (m == WM_DESTROY) PostQuitMessage(0);
    return DefWindowProcA(h, m, w, l);
}

struct stats {
    long polls, ev, sx, sy, absx, maxabs, overflow, lost, reacq, zero_ev;
};

static void pump(void) {
    MSG msg;
    while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
        TranslateMessage(&msg); DispatchMessageA(&msg);
    }
}

/* One timed phase: poll DirectInput exactly as the engine does, while WM_INPUT
 * accumulates the control in the window proc. */
static void run_phase(LPDIRECTINPUTDEVICE8A dev, const char *name, const char *ask,
                      int poll_ms, struct stats *s)
{
    memset(s, 0, sizeof *s);
    raw_reset();
    fprintf(stderr, "\n### PHASE %s\n", name);
    printf("\n>>> %-38s (%d s)\n", ask, PHASE_MS / 1000);
    fflush(stdout);

    DWORD t0 = GetTickCount();
    while (GetTickCount() - t0 < PHASE_MS) {
        pump();
        if (GetAsyncKeyState(VK_ESCAPE) & 0x8000) break;

        DIDEVICEOBJECTDATA od[BUFSZ];
        DWORD n = BUFSZ;
        HRESULT hr = IDirectInputDevice8_GetDeviceData(dev, sizeof(DIDEVICEOBJECTDATA), od, &n, 0);
        s->polls++;

        if (hr == DIERR_INPUTLOST || hr == DIERR_NOTACQUIRED) {
            s->lost++;
            if (SUCCEEDED(IDirectInputDevice8_Acquire(dev))) s->reacq++;
            Sleep(poll_ms);
            continue;
        }
        if (hr == DI_BUFFEROVERFLOW) s->overflow++;
        else if (FAILED(hr)) { Sleep(poll_ms); continue; }

        if (n == 0) s->zero_ev++;
        for (DWORD i = 0; i < n; i++) {
            LONG d = (LONG)od[i].dwData;
            if (od[i].dwOfs == DIMOFS_X || od[i].dwOfs == DIMOFS_Y) {
                LONG a = d < 0 ? -d : d;
                s->ev++;
                if (od[i].dwOfs == DIMOFS_X) { s->sx += d; s->absx += a; if (a > s->maxabs) s->maxabs = a; }
                else                          { s->sy += d; }
            }
        }
        Sleep(poll_ms);
    }
}

static void report(const char *name, const struct stats *s) {
    printf("  %-14s | DI ev %5ld  travel|x| %7ld  sum x %7ld  max|dx| %4ld  "
           "ovf %3ld lost %3ld | RAW ev %5ld  travel|x| %7ld  sum x %7ld  max|dx| %4ld  abs-flag %ld\n",
           name, s->ev, s->absx, s->sx, s->maxabs, s->overflow, s->lost,
           (long)g_rn, (long)g_rabs, (long)g_rsx, (long)g_rmax, (long)g_rabsolute);
}

static void verdict(const char *name, const struct stats *s) {
    long di = s->absx, raw = g_rabs;
    printf("    %-14s ", name);
    if (raw == 0 && di == 0)      printf("both silent\n");
    else if (raw == 0 && di > 0)  printf("** DI reports %ld px of travel while RAW saw NONE -> spurious/echoed motion **\n", di);
    else if (di == 0 && raw > 0)  printf("** DI saw NOTHING while RAW saw %ld px -> DirectInput delivered no motion **\n", raw);
    else {
        double r = (double)di / (double)raw;
        printf("DI/RAW travel ratio = %.2f  ", r);
        if      (r > 1.5) printf("** DI inflated -> duplicated/echoed deltas **\n");
        else if (r < 0.67) printf("** DI deflated -> dropped deltas (check ovf/lost) **\n");
        else               printf("(agrees within 1.5x)\n");
    }
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    printf("id Tech 4 mouse-path probe — DirectInput(exclusive,relative,buffered) vs raw input\n");
    printf("================================================================================\n");
    printf("A window will open and the cursor will vanish (exclusive grab). ~20 s, ESC quits.\n");

    WNDCLASSA wc; ZeroMemory(&wc, sizeof wc);
    wc.lpfnWndProc = wp; wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "mousefeel"; wc.hCursor = LoadCursorA(NULL, IDC_ARROW);
    RegisterClassA(&wc);
    HWND hw = CreateWindowExA(0, "mousefeel", "id Tech 4 mouse probe — keep this focused",
                              WS_OVERLAPPEDWINDOW, 100, 100, 520, 260,
                              NULL, NULL, wc.hInstance, NULL);
    ShowWindow(hw, SW_SHOW); UpdateWindow(hw); SetForegroundWindow(hw); SetFocus(hw);
    pump();

    RAWINPUTDEVICE rid;
    rid.usUsagePage = 0x01; rid.usUsage = 0x02;
    rid.dwFlags = RIDEV_INPUTSINK; rid.hwndTarget = hw;
    printf("  raw input registered : %s\n",
           RegisterRawInputDevices(&rid, 1, sizeof rid) ? "yes" : "NO (control unavailable!)");

    LPDIRECTINPUT8A di = NULL;
    if (FAILED(DirectInput8Create(GetModuleHandleA(NULL), DIRECTINPUT_VERSION,
                                  &IID_IDirectInput8A, (void **)&di, NULL)) || !di) {
        printf("  DirectInput8Create FAILED\n"); return 1;
    }
    LPDIRECTINPUTDEVICE8A dev = NULL;
    if (FAILED(IDirectInput8_CreateDevice(di, &GUID_SysMouse, &dev, NULL)) || !dev) {
        printf("  CreateDevice(GUID_SysMouse) FAILED\n"); return 1;
    }

    HRESULT h1 = IDirectInputDevice8_SetDataFormat(dev, &c_dfDIMouse2);
    /* EXACTLY what id Tech 4 asks for. */
    HRESULT h2 = IDirectInputDevice8_SetCooperativeLevel(dev, hw, DISCL_EXCLUSIVE | DISCL_FOREGROUND);

    DIPROPDWORD ax;
    ax.diph.dwSize = sizeof ax; ax.diph.dwHeaderSize = sizeof ax.diph;
    ax.diph.dwObj = 0; ax.diph.dwHow = DIPH_DEVICE; ax.dwData = DIPROPAXISMODE_REL;
    HRESULT h3 = IDirectInputDevice8_SetProperty(dev, DIPROP_AXISMODE, &ax.diph);

    DIPROPDWORD bs = ax; bs.dwData = BUFSZ;
    HRESULT h4 = IDirectInputDevice8_SetProperty(dev, DIPROP_BUFFERSIZE, &bs.diph);

    printf("  SetDataFormat=0x%08lx  CoopLevel(EXCLUSIVE|FOREGROUND)=0x%08lx\n",
           (unsigned long)h1, (unsigned long)h2);
    printf("  AxisMode(REL)=0x%08lx   BufferSize(%d)=0x%08lx\n",
           (unsigned long)h3, BUFSZ, (unsigned long)h4);

    HRESULT ha = DIERR_OTHERAPPHASPRIO;
    for (int i = 0; i < 200 && FAILED(ha); i++) { pump(); ha = IDirectInputDevice8_Acquire(dev); Sleep(10); }
    printf("  Acquire=0x%08lx %s\n", (unsigned long)ha, SUCCEEDED(ha) ? "" : "<- never acquired; result below is meaningless");

    struct stats still, slow, flick, frame;
    run_phase(dev, "STILL", "DO NOT TOUCH the mouse", 4, &still);
    struct stats s_still = still; LONG r_still_n=g_rn, r_still_abs=g_rabs, r_still_sx=g_rsx, r_still_max=g_rmax, r_still_a=g_rabsolute;
    printf("\n=== per-phase ===\n"); report("STILL", &still); verdict("STILL", &still);

    run_phase(dev, "SLOW", "move SLOWLY left and right", 4, &slow);
    report("SLOW", &slow); verdict("SLOW", &slow);

    run_phase(dev, "FLICK", "FLICK fast left and right", 4, &flick);
    report("FLICK", &flick); verdict("FLICK", &flick);

    run_phase(dev, "FRAMERATE", "move steadily (polled at 16 ms)", 16, &frame);
    report("FRAMERATE", &frame); verdict("FRAMERATE", &frame);

    (void)s_still; (void)r_still_n; (void)r_still_abs; (void)r_still_sx; (void)r_still_max; (void)r_still_a;

    IDirectInputDevice8_Unacquire(dev);
    IDirectInputDevice8_Release(dev);
    IDirectInput8_Release(di);
    DestroyWindow(hw);
    printf("\n================================================================================\n");
    printf("Compare the two runtimes. If DI and RAW agree in BOTH, the input layer is fine\n");
    printf("and the anomaly is above it (engine smoothing / frame timing) or below it\n");
    printf("(Xwayland pointer handling) — go there, do not guess again.\n");
    return 0;
}
