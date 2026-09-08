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

# ---------------------------------------------------------------------------
# CLI, added 2026-09-07. game-run.sh needs to know a title's real executable to
# launch Proton directly instead of going through `steam -applaunch` (which is
# an IPC forwarder, so no environment we set ever reached the game -- five runs
# produced zero MangoHud CSVs before anyone checked). Guessing the exe from the
# install dir is exactly the kind of guess this file exists to replace.
# Importing the module is unaffected.
if __name__ == "__main__":
    import sys, json as _json

    def _find(appid):
        for a, info in apps():
            if a == appid:
                return info
        return None

    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print("usage: appinfo.py <appid> [--launch|--name|--json]")
        print("  --launch  one line per launch entry: <key> <type> <exe> <description>")
        print("  --name    the store name")
        print("  --json    the whole appinfo record")
        sys.exit(2)

    try:
        _appid = int(args[0])
    except ValueError:
        print(f"not an appid: {args[0]}"); sys.exit(2)
    what = args[1] if len(args) > 1 else "--name"

    _info = _find(_appid)
    if _info is None:
        print(f"appid {_appid} not present in appinfo.vdf"); sys.exit(1)

    if what == "--name":
        print(_info.get("common", {}).get("name", ""))
    elif what == "--json":
        print(_json.dumps(_info, indent=1, default=str))
    elif what == "--launch":
        launch = _info.get("config", {}).get("launch", {})
        if not launch:
            print("no launch entries"); sys.exit(1)
        for k in sorted(launch, key=lambda x: int(x) if x.isdigit() else 999):
            e = launch[k]
            print("\t".join([k, e.get("type", ""), e.get("executable", ""),
                             e.get("description", "")]))
    else:
        print(f"unknown mode: {what}"); sys.exit(2)
