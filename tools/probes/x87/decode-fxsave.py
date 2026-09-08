import sys
d=sys.stdin.buffer.read()
if len(d)<112: print("SHORT READ %d"%len(d)); sys.exit(1)
u16=lambda b,o:b[o]|(b[o+1]<<8)
u32=lambda b,o:b[o]|(b[o+1]<<8)|(b[o+2]<<16)|(b[o+3]<<24)
nm={0:"Valid",1:"Zero",2:"Special",3:"Empty"}
def show(label,b,etw,etop):
    cw,sw,tw=u16(b,0),u16(b,4),u16(b,8); top=(sw>>11)&7
    ok = tw==etw and top==etop
    print("%-34s CW=%04x SW=%04x TW=%04x TOP=%d  [%s]"%(label,cw,sw,tw,top,"OK" if ok else "MISMATCH"))
    if not ok:
        print("%-34s   expected TW=%04x TOP=%d"%("",etw,etop))
        print("%-34s   tags: %s"%("", " ".join("R%d=%s"%(r,nm[(tw>>(2*r))&3]) for r in range(8))))
    return ok
print("FXSAVE/FXRSTOR round-trip fidelity, 32-bit")
print("-"*80)
a=show("A empty, through round-trip",   d[0:28],  0xffff,0)
b=show("B 3 pushes, through round-trip",d[28:56], 0x03ff,5)
c=show("C 3 pushes, NO round-trip",     d[56:84], 0x03ff,5)
h=d[84:100]
print("-"*80)
print("D raw FXSAVE header from the 3-push state:")
print("   FCW=%04x FSW=%04x FTW(abridged)=%02x  FOP=%04x FIP=%08x"
      %(u16(h,0),u16(h,2),h[4],u16(h,6),u32(h,8)))
print("   abridged tag bits (1=in use): %s"%format(h[4],'08b'))
print("   -> registers in use per FXSAVE: %s"%[r for r in range(8) if (h[4]>>r)&1])
print("   (3 pushes from empty occupy physical R5,R6,R7, so 0b11100000 = 0xe0 is correct)")
print("-"*80)
print("VERDICT:", "round-trip is FAITHFUL — FEX exonerated again" if (a and b and c)
      else "ROUND-TRIP CORRUPTS THE TAG WORD — this is the id Tech 4 bug")
