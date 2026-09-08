/* dinput-enum32.c — where does the 32-bit DirectInput path fault?
 *
 * WHY THIS EXISTS
 *   Prey (2006) and Quake 4 are both playable on this rig under Box64, and both
 *   have the SAME odd mouse behaviour. Their logs show it is literally one bug,
 *   not two:
 *
 *     Prey     92 x  c0000005 at ntdll.so+0x71f0 reading 0x7c (null+0x7c)
 *     Quake 4  41 x  c0000005 at ntdll.so+0x71f0 reading 0x7c
 *
 *   Both also load hid.dll three times and unload it once, and both initialise
 *   DirectInput. At the fault: info[0]=0 (a read), eax=c0000035
 *   (STATUS_OBJECT_NAME_COLLISION, a returned status), edi=4. Wine converts it
 *   to c0000005 and returns to the PE side at 7bf1d620.
 *
 *   The games report only "mouse: DirectInput initialized." and carry on, so the
 *   engine cannot say which call is faulting. This walks the same sequence and
 *   reports the HRESULT of every step, plus how many devices each enumeration
 *   pass actually returns.
 *
 *   THE QUESTION IT ANSWERS: is this Box64-specific, or a Wine 32-bit HID bug?
 *   That decides who can fix it. Run it under both:
 *       tools/run-both.sh --wine /path/to/dinput32.exe
 *   Different results  => the translator is implicated.
 *   Identical results  => suspect Wine, or this probe, before either JIT.
 *
 * BUILD (32-bit, matching every id Tech 4 title here):
 *   i686-w64-mingw32-gcc-win32 -O1 -o dinput32.exe dinput-enum32.c \
 *       -ldinput8 -ldxguid -lole32 -luser32
 *
 * READING IT
 *   The fault is a READ of null+0x7c, so watch for a step that "succeeds" while
 *   the enumeration count is 0, or a device whose creation succeeds but whose
 *   Acquire/GetDeviceState fails — that is the shape of a handle that was never
 *   initialised. Counting enumeration passes matters too: hid.dll being loaded
 *   three times suggests the enumeration runs more than once.
 */
#define DIRECTINPUT_VERSION 0x0800
#include <windows.h>
#include <dinput.h>
#include <stdio.h>

static int g_devices, g_pass;

static const char *hrname(HRESULT hr) {
    switch (hr) {
        case DI_OK:                    return "DI_OK";
        case DIERR_INVALIDPARAM:       return "DIERR_INVALIDPARAM";
        case DIERR_NOTINITIALIZED:     return "DIERR_NOTINITIALIZED";
        case DIERR_OUTOFMEMORY:        return "DIERR_OUTOFMEMORY";
        case DIERR_UNSUPPORTED:        return "DIERR_UNSUPPORTED";
        case DIERR_DEVICENOTREG:       return "DIERR_DEVICENOTREG";
        case DIERR_NOTFOUND:           return "DIERR_NOTFOUND/OBJECTNOTFOUND";
        case DIERR_INPUTLOST:          return "DIERR_INPUTLOST";
        case DIERR_ACQUIRED:           return "DIERR_ACQUIRED";
        case DIERR_NOTACQUIRED:        return "DIERR_NOTACQUIRED";
        case DIERR_OTHERAPPHASPRIO:    return "DIERR_OTHERAPPHASPRIO";
        case E_NOINTERFACE:            return "E_NOINTERFACE";
        case E_HANDLE:                 return "E_HANDLE";
        default:                       return "";
    }
}

static void step(const char *what, HRESULT hr) {
    printf("  %-34s hr=0x%08lx %-26s GetLastError=%lu\n",
           what, (unsigned long)hr, hrname(hr), (unsigned long)GetLastError());
    SetLastError(0);
}

static BOOL CALLBACK on_device(LPCDIDEVICEINSTANCEA inst, LPVOID ctx) {
    (void)ctx;
    g_devices++;
    /* Print only the first few: a machine can have many HID devices and the
     * point is the count plus the type, not a full inventory. */
    if (g_devices <= 6)
        printf("      [%d] type=0x%08lx  %s\n", g_devices,
               (unsigned long)inst->dwDevType, inst->tszProductName);
    return DIENUM_CONTINUE;
}

int main(void) {
    printf("32-bit DirectInput enumeration probe\n");
    printf("--------------------------------------------------------------\n");
    SetLastError(0);

    LPDIRECTINPUT8A di = NULL;
    HRESULT hr = DirectInput8Create(GetModuleHandleA(NULL), DIRECTINPUT_VERSION,
                                    &IID_IDirectInput8A, (void **)&di, NULL);
    step("DirectInput8Create", hr);
    if (FAILED(hr) || !di) return 1;

    /* Enumerate three times: the games load hid.dll three times, so a fault that
     * only appears on a later pass is exactly what we are looking for. */
    for (g_pass = 1; g_pass <= 3; g_pass++) {
        g_devices = 0;
        printf("  -- enumeration pass %d (DI8DEVCLASS_ALL) --\n", g_pass);
        hr = IDirectInput8_EnumDevices(di, DI8DEVCLASS_ALL, on_device, NULL,
                                       DIEDFL_ALLDEVICES);
        printf("      devices found: %d\n", g_devices);
        step("EnumDevices", hr);
    }

    /* A window is required before SetCooperativeLevel will accept anything. */
    WNDCLASSA wc;
    ZeroMemory(&wc, sizeof wc);
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "diprobe";
    RegisterClassA(&wc);
    HWND w = CreateWindowExA(0, "diprobe", "diprobe", WS_OVERLAPPEDWINDOW,
                             0, 0, 320, 240, NULL, NULL, wc.hInstance, NULL);
    SetLastError(0);

    LPDIRECTINPUTDEVICE8A mouse = NULL;
    hr = IDirectInput8_CreateDevice(di, &GUID_SysMouse, &mouse, NULL);
    step("CreateDevice(GUID_SysMouse)", hr);

    if (SUCCEEDED(hr) && mouse) {
        step("SetDataFormat(c_dfDIMouse2)",
             IDirectInputDevice8_SetDataFormat(mouse, &c_dfDIMouse2));
        step("SetCooperativeLevel",
             IDirectInputDevice8_SetCooperativeLevel(mouse, w,
                 DISCL_NONEXCLUSIVE | DISCL_BACKGROUND));
        /* id Tech 4 uses buffered mouse input, so ask for a buffer like it does. */
        DIPROPDWORD dp;
        dp.diph.dwSize = sizeof dp;
        dp.diph.dwHeaderSize = sizeof dp.diph;
        dp.diph.dwObj = 0;
        dp.diph.dwHow = DIPH_DEVICE;
        dp.dwData = 16;
        step("SetProperty(DIPROP_BUFFERSIZE=16)",
             IDirectInputDevice8_SetProperty(mouse, DIPROP_BUFFERSIZE, &dp.diph));
        step("Acquire", IDirectInputDevice8_Acquire(mouse));

        DIMOUSESTATE2 st;
        ZeroMemory(&st, sizeof st);
        step("GetDeviceState", IDirectInputDevice8_GetDeviceState(mouse, sizeof st, &st));

        DWORD n = 8;
        DIDEVICEOBJECTDATA od[8];
        step("GetDeviceData(buffered)",
             IDirectInputDevice8_GetDeviceData(mouse, sizeof(DIDEVICEOBJECTDATA), od, &n, 0));
        printf("      buffered events available: %lu\n", (unsigned long)n);

        IDirectInputDevice8_Unacquire(mouse);
        IDirectInputDevice8_Release(mouse);
    }

    /* Keyboard too — the games initialise both, and the logs show two
     * "DirectInput initialized" lines. */
    LPDIRECTINPUTDEVICE8A kbd = NULL;
    hr = IDirectInput8_CreateDevice(di, &GUID_SysKeyboard, &kbd, NULL);
    step("CreateDevice(GUID_SysKeyboard)", hr);
    if (SUCCEEDED(hr) && kbd) {
        step("kbd SetDataFormat", IDirectInputDevice8_SetDataFormat(kbd, &c_dfDIKeyboard));
        step("kbd Acquire", IDirectInputDevice8_Acquire(kbd));
        IDirectInputDevice8_Unacquire(kbd);
        IDirectInputDevice8_Release(kbd);
    }

    IDirectInput8_Release(di);
    if (w) DestroyWindow(w);

    printf("--------------------------------------------------------------\n");
    printf("Both games fault %d-90+ times at ntdll.so+0x71f0 reading null+0x7c\n", 41);
    printf("while DirectInput is in use. If every line above says DI_OK, the\n");
    printf("fault is somewhere this sequence does not reach — widen the probe\n");
    printf("rather than concluding there is no bug.\n");
    return 0;
}
