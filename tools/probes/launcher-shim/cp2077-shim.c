// cp2077-shim — stands in for REDprelauncher.exe and launches the game directly.
//
// WHY: REDlauncher is a Qt+CEF app, and CEF under FEX is the single least reliable thing on this
// rig (it failed to hand off ~10 times in a row on 2026-09-07). The game itself does not need it.
// Steam insists on running REDprelauncher.exe, so we replace that file rather than fight Steam's
// config (editing launch options needs Steam closed; this does not).
//
// It must WAIT on the child: Steam tracks the process it launched, so exiting immediately would
// make Steam think the game had closed.
#include <windows.h>
#include <stdio.h>

int main(void) {
    wchar_t self[MAX_PATH];
    if (!GetModuleFileNameW(NULL, self, MAX_PATH)) return 1;
    wchar_t *slash = wcsrchr(self, L'\\');
    if (slash) *slash = 0;                       // -> game root

    wchar_t dir[MAX_PATH], exe[MAX_PATH];
    _snwprintf(dir, MAX_PATH, L"%s\\bin\\x64", self);
    _snwprintf(exe, MAX_PATH, L"%s\\Cyberpunk2077.exe", dir);

    // Forward our own arguments, minus argv[0].
    const wchar_t *cl = GetCommandLineW();
    const wchar_t *args = cl;
    if (*args == L'"') { args++; while (*args && *args != L'"') args++; if (*args) args++; }
    else { while (*args && *args != L' ') args++; }
    while (*args == L' ') args++;

    static wchar_t cmd[32768];
    _snwprintf(cmd, 32768, L"\"%s\" %s", exe, args);

    STARTUPINFOW si; PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si)); si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    if (!CreateProcessW(exe, cmd, NULL, NULL, FALSE, 0, NULL, dir, &si, &pi)) {
        wchar_t msg[MAX_PATH + 128];
        _snwprintf(msg, MAX_PATH + 128, L"cp2077-shim: could not start\n%s\n(error %lu)", exe, GetLastError());
        MessageBoxW(NULL, msg, L"cp2077-shim", MB_ICONERROR | MB_OK);
        return 1;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);   // Steam tracks THIS process
    DWORD code = 0; GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
    return (int)code;
}
