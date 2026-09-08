// Minimal DLL using the same toolchain + flags as our OptiScaler build, doing the kind of
// static-initialisation C++ that OptiScaler does (std::string, mutex, vector, iostream).
#include <windows.h>
#include <string>
#include <vector>
#include <mutex>
#include <memory>
#include <sstream>

static std::string g_s = "static init string";
static std::vector<std::string> g_v = {"a","b","c"};
static std::mutex g_m;
static std::unique_ptr<std::string> g_p = std::make_unique<std::string>("heap");

struct Init {
    Init() {
        std::lock_guard<std::mutex> lk(g_m);
        std::ostringstream os; os << g_s << " " << g_v.size() << " " << *g_p;
        g_s = os.str();
    }
} g_init;

extern "C" __declspec(dllexport) const char* mini_probe() { return g_s.c_str(); }

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID r) {
    if (reason == DLL_PROCESS_ATTACH) {
        std::lock_guard<std::mutex> lk(g_m);
        g_s += " | attached";
    }
    return TRUE;
}
