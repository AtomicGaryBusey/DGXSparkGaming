#include <windows.h>
__declspec(dllexport) int probe(void){ return 0x1234; }
BOOL WINAPI DllMain(HINSTANCE h, DWORD r, LPVOID v){ (void)h;(void)r;(void)v; return TRUE; }
