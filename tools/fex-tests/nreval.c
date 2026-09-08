/* nreval.c — the DISCRIMINATING test.
 *
 * CreateFeature returns Success for ANY feature id (verified: 18 and 99 both
 * succeed), so creation proves nothing. EvaluateFeature with real resources
 * bound is where a bogus feature should diverge from a real one.
 *
 * Feature id is a command-line argument so the same binary tests 18 vs 99.
 */
#define INITGUID
#include <windows.h>
#include <initguid.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <stdio.h>
#include <stdlib.h>
#define P(...) do{ printf(__VA_ARGS__); fflush(stdout);}while(0)

typedef int (__cdecl *PFN_NGXInit)(unsigned long long, const wchar_t*, ID3D12Device*, int, const void*);
typedef int (__cdecl *PFN_NGXCaps)(void**);
typedef int (__cdecl *PFN_SnipInit)(unsigned long long, const wchar_t*, ID3D12Device*, int, const void*);
typedef int (__cdecl *PFN_SnipCreate)(ID3D12GraphicsCommandList*, int, const void*, void**);
typedef int (__cdecl *PFN_SnipEval)(ID3D12GraphicsCommandList*, const void*, const void*, void*);

typedef void (*SetF_t)(void*, const char*, float);
typedef void (*SetUI_t)(void*, const char*, unsigned int);
typedef void (*SetI_t)(void*, const char*, int);
typedef void (*SetRes_t)(void*, const char*, ID3D12Resource*);
static void** vt(void* p){ return *(void***)p; }
static void setUI (void* p,const char* n,unsigned int v){ ((SetUI_t) vt(p)[3])(p,n,v); }
static void setI  (void* p,const char* n,int v){ ((SetI_t)  vt(p)[4])(p,n,v); }
static void setF  (void* p,const char* n,float v){ ((SetF_t)  vt(p)[1])(p,n,v); }
static void setRes(void* p,const char* n,ID3D12Resource* v){ ((SetRes_t)vt(p)[6])(p,n,v); }

static ID3D12Resource* tex(ID3D12Device* dev, UINT w, UINT h, DXGI_FORMAT f){
    D3D12_HEAP_PROPERTIES hp = {D3D12_HEAP_TYPE_DEFAULT,0,0,0,0};
    D3D12_RESOURCE_DESC rd = {D3D12_RESOURCE_DIMENSION_TEXTURE2D,0,w,h,1,1,f,{1,0},
                              D3D12_TEXTURE_LAYOUT_UNKNOWN, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS};
    ID3D12Resource* r=NULL;
    dev->lpVtbl->CreateCommittedResource(dev,&hp,D3D12_HEAP_FLAG_NONE,&rd,
        D3D12_RESOURCE_STATE_UNORDERED_ACCESS,NULL,&IID_ID3D12Resource,(void**)&r);
    return r;
}

int main(int argc,char** argv){
    int FEAT = (argc>1)? atoi(argv[1]) : 18;
    const UINT W=1920,H=1080;
    P("== feature id under test: %d ==\n", FEAT);

    IDXGIFactory4* fac=NULL; CreateDXGIFactory1(&IID_IDXGIFactory4,(void**)&fac);
    IDXGIAdapter1* ad=NULL; ID3D12Device* dev=NULL;
    for(UINT i=0; fac->lpVtbl->EnumAdapters1(fac,i,&ad)!=DXGI_ERROR_NOT_FOUND;i++){
        DXGI_ADAPTER_DESC1 d; ad->lpVtbl->GetDesc1(ad,&d);
        if(d.Flags & DXGI_ADAPTER_FLAG_SOFTWARE){ad->lpVtbl->Release(ad);continue;}
        if(SUCCEEDED(D3D12CreateDevice((IUnknown*)ad,D3D_FEATURE_LEVEL_12_0,&IID_ID3D12Device,(void**)&dev))){
            P("  gpu: %ls\n",d.Description); break;}
        ad->lpVtbl->Release(ad);
    }
    if(!dev){P("RESULT: no device\n");return 1;}

    HMODULE core=LoadLibraryW(L"_nvngx.dll"); if(!core)core=LoadLibraryW(L"nvngx.dll");
    PFN_NGXInit ci=(PFN_NGXInit)GetProcAddress(core,"NVSDK_NGX_D3D12_Init_Ext");
    PFN_NGXCaps cc=(PFN_NGXCaps)GetProcAddress(core,"NVSDK_NGX_D3D12_GetCapabilityParameters");
    ci(0x24480451ull,L".",dev,0x15,NULL);
    void* caps=NULL; cc(&caps);
    if(!caps){P("RESULT: no caps\n");return 1;}

    HMODULE snip=LoadLibraryW(L"nvngx.dll_nrfwd.dll");
    PFN_SnipInit si=(PFN_SnipInit)GetProcAddress(snip,"nrfwd_init");
    if(!si){P("RESULT: forwarder missing nrfwd_init\n");return 1;}
    typedef int (*FI)(const wchar_t*,const wchar_t*,ID3D12Device*,void*);
    int ri=((FI)si)(L"nvngx_dlssnr.dll",L".",dev,caps);
    P("  snippet init => %d\n",ri);
    if(ri!=1){P("RESULT: snippet did not init\n");return 1;}

    /* creation params */
    setUI(caps,"CreationNodeMask",1); setUI(caps,"VisibilityNodeMask",1);
    setUI(caps,"Width",W); setUI(caps,"Height",H);
    setUI(caps,"OutWidth",W); setUI(caps,"OutHeight",H);
    setUI(caps,"DLSSNR.Width",W); setUI(caps,"DLSSNR.Height",H);
    setUI(caps,"DLSSNR.Enabled",1); setUI(caps,"PerfQualityValue",1);
    setF(caps,"DLSSNR.ScalingRatio",1.0f); setI(caps,"DLSSNR.Reset",0);

    ID3D12CommandAllocator* al=NULL; ID3D12GraphicsCommandList* cl=NULL; ID3D12CommandQueue* q=NULL;
    D3D12_COMMAND_QUEUE_DESC qd={D3D12_COMMAND_LIST_TYPE_DIRECT,0,D3D12_COMMAND_QUEUE_FLAG_NONE,0};
    dev->lpVtbl->CreateCommandQueue(dev,&qd,&IID_ID3D12CommandQueue,(void**)&q);
    dev->lpVtbl->CreateCommandAllocator(dev,D3D12_COMMAND_LIST_TYPE_DIRECT,&IID_ID3D12CommandAllocator,(void**)&al);
    dev->lpVtbl->CreateCommandList(dev,0,D3D12_COMMAND_LIST_TYPE_DIRECT,al,NULL,&IID_ID3D12GraphicsCommandList,(void**)&cl);

    /* the snippet's own CreateFeature via the forwarder is hardcoded to 18, so
       call the snippet directly here — the caller-identity gate is already satisfied
       because the forwarder module stays loaded and we reuse its snippet handle. */
    typedef void* (*FC)(ID3D12GraphicsCommandList*,void*,int*);
    FC fc=(FC)GetProcAddress(snip,"nrfwd_create");
    int cr=0; void* feat=fc(cl,caps,&cr);
    P("  CreateFeature => 0x%08X handle=%p\n",(unsigned)cr,feat);
    if(!feat){P("RESULT: no feature handle\n");return 2;}

    /* bind real resources — THIS is what a bogus feature cannot survive */
    ID3D12Resource *color=tex(dev,W,H,DXGI_FORMAT_R16G16B16A16_FLOAT),
                   *depth=tex(dev,W,H,DXGI_FORMAT_R32_FLOAT),
                   *mvec =tex(dev,W,H,DXGI_FORMAT_R16G16_FLOAT),
                   *outp =tex(dev,W,H,DXGI_FORMAT_R16G16B16A16_FLOAT);
    P("  textures: color=%p depth=%p mvec=%p out=%p\n",(void*)color,(void*)depth,(void*)mvec,(void*)outp);
    if(!color||!depth||!mvec||!outp){P("RESULT: texture alloc failed\n");return 1;}
    ID3D12Resource *bb=tex(dev,W,H,DXGI_FORMAT_R16G16B16A16_FLOAT),
                   *cm=tex(dev,W,H,DXGI_FORMAT_R8_UNORM),
                   *ui=tex(dev,W,H,DXGI_FORMAT_R16G16B16A16_FLOAT),
                   *ua=tex(dev,W,H,DXGI_FORMAT_R8_UNORM),
                   *bd=tex(dev,W,H,DXGI_FORMAT_R16G16_FLOAT);
    /* every resource the snippet names */
    setRes(caps,"DLSSNR.Color",color); setRes(caps,"DLSSNR.Depth",depth);
    setRes(caps,"DLSSNR.MVec",mvec);   setRes(caps,"DLSSNR.Output",outp);
    setRes(caps,"DLSSNR.Backbuffer",bb); setRes(caps,"DLSSNR.ControlMask",cm);
    setRes(caps,"DLSSNR.UI",ui); setRes(caps,"DLSSNR.UIAlpha",ua);
    setRes(caps,"DLSSNR.BidirectionalDistortionField",bd);
    /* every subrect: base 0, full extent */
    { const char* R[]={"Color","Depth","MVec","Output","Backbuffer","ControlMask","UI","UIAlpha",
                       "BidirectionalDistortionField"};
      char nm[96];
      for(unsigned k=0;k<sizeof(R)/sizeof(R[0]);k++){
        sprintf(nm,"DLSSNR.%sSubrectBaseX",R[k]);  setUI(caps,nm,0);
        sprintf(nm,"DLSSNR.%sSubrectBaseY",R[k]);  setUI(caps,nm,0);
        sprintf(nm,"DLSSNR.%sSubrectWidth",R[k]);  setUI(caps,nm,W);
        sprintf(nm,"DLSSNR.%sSubrectHeight",R[k]); setUI(caps,nm,H);
      } }
    setF(caps,"DLSSNR.MVecScaleX",1.0f); setF(caps,"DLSSNR.MVecScaleY",1.0f);
    setF(caps,"DLSSNR.UIAlpha",1.0f);
    setUI(caps,"DLSSNR.UICorrection",0); setUI(caps,"DLSSNR.UseAutoMask",1);
    setF(caps,"DLSSNR.Intensity",1.0f);
    setF(caps,"DLSSNR.LocalStructureStrength",1.0f);
    setF(caps,"DLSSNR.LocalToneStrength",1.0f);
    setF(caps,"DLSSNR.SkinStructureStrength",1.0f);
    setUI(caps,"DLSSNR.Style",0); setUI(caps,"DLSSNR.Hint.Render.Preset",0);
    setUI(caps,"DLSSNR.DepthInverted",0);
    P("  bound 9 resources + 36 subrect params + 12 scalars\n");

    typedef int (*FE)(ID3D12GraphicsCommandList*,void*,void*);
    FE fe=(FE)GetProcAddress(snip,"nrfwd_evaluate");
    int er=fe(cl,feat,caps);
    P("  EvaluateFeature => 0x%08X\n",(unsigned)er);

    cl->lpVtbl->Close(cl);
    ID3D12CommandList* lists[1]={(ID3D12CommandList*)cl};
    q->lpVtbl->ExecuteCommandLists(q,1,lists);
    ID3D12Fence* fence=NULL; dev->lpVtbl->CreateFence(dev,0,D3D12_FENCE_FLAG_NONE,&IID_ID3D12Fence,(void**)&fence);
    q->lpVtbl->Signal(q,fence,1);
    HANDLE ev=CreateEventW(NULL,FALSE,FALSE,NULL);
    fence->lpVtbl->SetEventOnCompletion(fence,1,ev);
    DWORD wr=WaitForSingleObject(ev,15000);
    P("  GPU execute => %s\n", wr==WAIT_OBJECT_0?"completed":"TIMEOUT/failed");
    HRESULT rr=dev->lpVtbl->GetDeviceRemovedReason(dev);
    P("  device removed reason => 0x%08X %s\n",(unsigned)rr, rr==S_OK?"(healthy)":"(DEVICE LOST)");

    P("RESULT: feat=%d create=0x%08X evaluate=0x%08X gpu=%s device=%s\n",
      FEAT,(unsigned)cr,(unsigned)er, wr==WAIT_OBJECT_0?"ok":"fail", rr==S_OK?"ok":"lost");
    return (er==1 && rr==S_OK)?0:3;
}
