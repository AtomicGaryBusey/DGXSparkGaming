import sys
L1E={0:'FPU',1:'VME',2:'DE',3:'PSE',4:'TSC',15:'CMOV',19:'CLFSH',23:'MMX',24:'FXSR',25:'SSE',26:'SSE2',28:'HTT'}
L1C={0:'SSE3',9:'SSSE3',19:'SSE4.1',20:'SSE4.2',28:'AVX',31:'HYPERVISOR'}
brand=[None]*3
for ln in sys.stdin:
    p=ln.split()
    if len(p)!=5: continue
    try: lf=int(p[0],16); a,b,c,d=(int(x,16) for x in p[1:])
    except ValueError: continue
    if lf==0:
        v=(b.to_bytes(4,'little')+d.to_bytes(4,'little')+c.to_bytes(4,'little')).decode('latin1')
        print("  vendor       : %s   max std leaf 0x%x"%(v,a))
    elif lf==1:
        print("  leaf1.EDX    : %08x  "%d + " ".join("%s=%d"%(n,(d>>i)&1) for i,n in sorted(L1E.items())))
        print("  leaf1.ECX    : %08x  "%c + " ".join("%s=%d"%(n,(c>>i)&1) for i,n in sorted(L1C.items())))
    elif lf==0x80000001:
        print("  8000_0001.EDX: %08x  1GBpage=%d LM=%d"%(d,(d>>26)&1,(d>>29)&1))
    elif 0x80000002<=lf<=0x80000004:
        brand[lf-0x80000002]="".join(x.to_bytes(4,'little').decode('latin1') for x in (a,b,c,d))
if any(brand): print("  brand        : %r"%("".join(x or '' for x in brand).rstrip('\x00')))
