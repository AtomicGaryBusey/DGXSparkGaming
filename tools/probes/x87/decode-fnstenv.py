import sys
d=sys.stdin.buffer.read()
scen=[("after finit",0xffff,0,"untouched stack must read all-Empty"),
      ("after 3x fld1",0x03ff,5,"3 pushes -> TOP=5, R5/R6/R7 Valid"),
      ("after 3 push + 3 pop",0xffff,0,"pops must re-mark slots Empty"),
      ("after fld1 + fstp",0xffff,0,"balanced pair -> empty again")]
n={0:"Valid",1:"Zero",2:"Special",3:"Empty"}
if len(d)<112: print("SHORT READ: %d bytes"%len(d)); sys.exit(1)
u16=lambda b,o:b[o]|(b[o+1]<<8)
u32=lambda b,o:b[o]|(b[o+1]<<8)|(b[o+2]<<16)|(b[o+3]<<24)
bad=0
for i,(name,etw,etop,note) in enumerate(scen):
    b=d[i*28:(i+1)*28]
    cw,sw,tw=u16(b,0),u16(b,4),u16(b,8)
    fip,fdp=u32(b,12),u32(b,20)
    top=(sw>>11)&7
    ok = tw==etw and top==etop
    if not ok: bad+=1
    print("%-22s CW=%04x SW=%04x TW=%04x TOP=%d FIP=%08x FDP=%08x  [%s]"
          %(name,cw,sw,tw,top,fip,fdp,"OK" if ok else "MISMATCH"))
    if not ok:
        print("%-22s   expected TW=%04x TOP=%d  (%s)"%("",etw,etop,note))
        print("%-22s   tags: %s"%("", " ".join("R%d=%s"%(r,n[(tw>>(2*r))&3]) for r in range(8))))
b0=d[0:28]; tw0=u16(b0,8)
b3=d[84:112]
print("-"*78)
print("FIP after a real x87 op:", "populated" if u32(b3,12) else "ZERO -- FNSTENV is not recording the x87 instruction pointer")
print("id Tech 4 test on the *empty* stack: (TW ^ 0xffff) = 0x%04x  %s"
      %(tw0^0xffff, "<-- FatalError: 'the FPU stack is not empty'" if (tw0^0xffff) else "(engine would be happy)"))
sys.exit(1 if bad else 0)
