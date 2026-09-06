import struct
P="/home/aharmon/.local/share/Steam/appcache/appinfo.vdf"
d=open(P,'rb').read()
stroff=struct.unpack_from('<q',d,8)[0]
n=struct.unpack_from('<I',d,stroff)[0]
o=stroff+4; strs=[]
for _ in range(n):
    e=d.index(b'\x00',o); strs.append(d[o:e].decode('utf-8','replace')); o=e+1
def parse(buf,pos):
    out={}
    while True:
        t=buf[pos]; pos+=1
        if t==0x08: return out,pos
        key=strs[struct.unpack_from('<I',buf,pos)[0]]; pos+=4
        if t==0x00: v,pos=parse(buf,pos); out[key]=v
        elif t==0x01:
            e=buf.index(b'\x00',pos); out[key]=buf[pos:e].decode('utf-8','replace'); pos=e+1
        elif t==0x02: out[key]=struct.unpack_from('<i',buf,pos)[0]; pos+=4
        elif t==0x07: out[key]=struct.unpack_from('<Q',buf,pos)[0]; pos+=8
        else: raise ValueError(t)
def apps():
    off=16
    while off < len(d)-4:
        a=struct.unpack_from('<I',d,off)[0]
        if a==0: break
        sz=struct.unpack_from('<I',d,off+4)[0]
        try: kv,_=parse(d[off+8:off+8+sz], 4+4+8+20+4+20); yield a, kv.get('appinfo',{})
        except Exception: pass
        off += 8+sz
