/* nrtest.c — does DLSS 5 Neural Rendering initialise on GB10 under FEX?
 *
 * Tests the ONE remaining unknown in Path A: whether a 158 MB CUDA-bearing PE
 * (nvngx_dlssnr.dll) drives nvcuda.dll through FEX -> vkd3d-proton -> NVX.
 * Needs no ReShade, no add-on, no game. Our own code end to end.
 *
 * Chain: D3D12 device -> driver's _nvngx.dll for capability params ->
 *        our forwarder -> the snippet's own CreateFeature(18).
 */
#define INITGUID
#include <windows.h>
#include <initguid.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <stdio.h>
#define P(...) do{ printf(__VA_ARGS__); fflush(stdout);}while(0)

typedef int (__cdecl *PFN_NGXInit)(unsigned long long, const wchar_t*, ID3D12Device*, int, const void*);
typedef int (__cdecl *PFN_NGXCaps)(void**);
typedef int (*PFN_FwdInit)(const wchar_t*, const wchar_t*, ID3D12Device*, void*);
typedef void*(*PFN_FwdCreate)(ID3D12GraphicsCommandList*, void*, int*);

/* NVSDK_NGX_Parameter is a C++ abstract class: 8 Set overloads then 8 Get, in
 * declaration order (nvsdk_ngx_params.h). Reached from C via the vtable.
 * Order: 0=ULL 1=float 2=double 3=uint 4=int 5=ID3D11Res 6=ID3D12Res 7=void* */
typedef void (*SetULL_t)(void*, const char*, unsigned long long);
typedef void (*SetF_t)  (void*, const char*, float);
typedef void (*SetUI_t) (void*, const char*, unsigned int);
typedef void (*SetI_t)  (void*, const char*, int);
static void** vt(void* p){ return *(void***)p; }
static void setUI(void* p, const char* n, unsigned int v){ ((SetUI_t)vt(p)[3])(p,n,v); }
static void setI (void* p, const char* n, int v){ ((SetI_t) vt(p)[4])(p,n,v); }
static void setF (void* p, const char* n, float v){ ((SetF_t) vt(p)[1])(p,n,v); }

int main(int argc, char** argv){
    const wchar_t* snippet = (argc>1) ? (const wchar_t*)0 : 0;
    wchar_t snip[1024];
    if (argc>1) MultiByteToWideChar(CP_ACP,0,argv[1],-1,snip,1024);
    else wcscpy(snip, L"nvngx_dlssnr.dll");
    (void)snippet;

    P("== step 1: D3D12 device ==\n");
    IDXGIFactory4* fac=NULL;
    if (FAILED(CreateDXGIFactory1(&IID_IDXGIFactory4,(void**)&fac))){ P("RESULT: no DXGI factory\n"); return 1; }
    IDXGIAdapter1* ad=NULL; ID3D12Device* dev=NULL;
    for (UINT i=0; fac->lpVtbl->EnumAdapters1(fac,i,&ad)!=DXGI_ERROR_NOT_FOUND; i++){
        DXGI_ADAPTER_DESC1 d; ad->lpVtbl->GetDesc1(ad,&d);
        if (d.Flags & DXGI_ADAPTER_FLAG_SOFTWARE){ ad->lpVtbl->Release(ad); continue; }
        if (SUCCEEDED(D3D12CreateDevice((IUnknown*)ad,D3D_FEATURE_LEVEL_12_0,&IID_ID3D12Device,(void**)&dev))){
            P("  adapter: %ls  vendor=0x%04X device=0x%04X\n", d.Description, d.VendorId, d.DeviceId); break; }
        ad->lpVtbl->Release(ad);
    }
    if(!dev){ P("RESULT: no D3D12 device\n"); return 1; }

    P("== step 2: driver NGX core (capability params) ==\n");
    HMODULE core = LoadLibraryW(L"_nvngx.dll");
    if(!core) core = LoadLibraryW(L"nvngx.dll");
    if(!core){ P("RESULT: driver NGX core not loadable (err=%lu)\n", GetLastError()); return 1; }
    PFN_NGXInit ngxinit = (PFN_NGXInit)GetProcAddress(core,"NVSDK_NGX_D3D12_Init_Ext");
    PFN_NGXCaps ngxcaps = (PFN_NGXCaps)GetProcAddress(core,"NVSDK_NGX_D3D12_GetCapabilityParameters");
    P("  Init_Ext=%p GetCapabilityParameters=%p\n",(void*)ngxinit,(void*)ngxcaps);
    if(!ngxinit||!ngxcaps){ P("RESULT: NGX core missing entry points\n"); return 1; }
    int r = ngxinit(0x24480451ull, L".", dev, 0x0000015, NULL);
    P("  NVSDK_NGX_D3D12_Init_Ext => 0x%08X  (1 = Success)\n", (unsigned)r);
    void* caps=NULL; int rc = ngxcaps(&caps);
    P("  GetCapabilityParameters  => 0x%08X  params=%p\n", (unsigned)rc, caps);
    if(!caps){ P("RESULT: no capability block — cannot proceed\n"); return 1; }

    P("== step 3: forwarder + NR snippet ==\n");
    HMODULE fwd = LoadLibraryW(L"nvngx.dll_ctl99.dll");
    if(!fwd){ P("RESULT: forwarder not loadable (err=%lu)\n", GetLastError()); return 1; }
    PFN_FwdInit fi = (PFN_FwdInit)GetProcAddress(fwd,"nrfwd_init");
    PFN_FwdCreate fc = (PFN_FwdCreate)GetProcAddress(fwd,"nrfwd_create");
    if(!fi||!fc){ P("RESULT: forwarder missing exports\n"); return 1; }
    P("  loading snippet: %ls\n", snip);
    int ri = fi(snip, L".", dev, caps);
    P("  nrfwd_init  => %d   (1 = snippet initialised, 0 = would not load)\n", ri);
    if(ri!=1){ P("RESULT: NR SNIPPET DID NOT INITIALISE (init=%d)\n", ri); return 2; }

    P("== step 3b: writing DLSSNR creation parameters ==\n");
    /* The ReShade addon normally writes these; without them CreateFeature returns
     * 0xBAD00005 (InvalidParameter) — which is an ACCEPTED call, not a rejection. */
    const unsigned W_=1920, H_=1080;
    setUI(caps,"CreationNodeMask",1);
    setUI(caps,"VisibilityNodeMask",1);
    setUI(caps,"Width",W_);          setUI(caps,"Height",H_);
    setUI(caps,"OutWidth",W_);       setUI(caps,"OutHeight",H_);
    setUI(caps,"DLSSNR.Width",W_);   setUI(caps,"DLSSNR.Height",H_);
    setUI(caps,"PerfQualityValue",1);
    setUI(caps,"DLSSNR.Enabled",1);
    setUI(caps,"DLSSNR.DepthInverted",0);
    setUI(caps,"DLSSNR.UseAutoMask",1);
    setUI(caps,"DLSSNR.Style",0);
    setUI(caps,"DLSSNR.Hint.Render.Preset",0);
    setF (caps,"DLSSNR.ScalingRatio",1.0f);
    setF (caps,"DLSSNR.Intensity",1.0f);
    setF (caps,"DLSSNR.LocalStructureStrength",1.0f);
    setF (caps,"DLSSNR.LocalToneStrength",1.0f);
    setF (caps,"DLSSNR.SkinStructureStrength",1.0f);
    setI (caps,"DLSSNR.Reset",0);
    P("  wrote %d params (Width=%u Height=%u)\n", 19, W_, H_);

    P("== step 4: CreateFeature(18) — the actual gate ==\n");
    ID3D12CommandAllocator* alloc=NULL; ID3D12GraphicsCommandList* cl=NULL;
    dev->lpVtbl->CreateCommandAllocator(dev,D3D12_COMMAND_LIST_TYPE_DIRECT,&IID_ID3D12CommandAllocator,(void**)&alloc);
    dev->lpVtbl->CreateCommandList(dev,0,D3D12_COMMAND_LIST_TYPE_DIRECT,alloc,NULL,&IID_ID3D12GraphicsCommandList,(void**)&cl);
    if(!cl){ P("RESULT: could not create command list\n"); return 1; }
    int cr=0; void* feat = fc(cl, caps, &cr);
    P("  CreateFeature(18) => 0x%08X  handle=%p\n",(unsigned)cr,feat);
    if(cr==1 && feat){ P("RESULT: *** DLSS 5 NEURAL RENDERING FEATURE CREATED ON GB10 ***\n"); return 0; }
    P("RESULT: feature 18 refused (0x%08X)\n",(unsigned)cr);
    return 3;
}
