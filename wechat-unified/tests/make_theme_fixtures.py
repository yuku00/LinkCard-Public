from pathlib import Path
import json, struct, zlib, zipfile, hashlib
root=Path(__file__).parent/'fixtures'/'themes'
root.mkdir(parents=True,exist_ok=True)
def png(w,h,rgba):
    def chunk(kind,data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    body=b''.join(b'\0'+bytes(rgba)*w for _ in range(h))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(body))+chunk(b'IEND',b'')
light=png(96,60,(36,170,125,255)); dark=png(144,90,(24,70,90,255)); cover=png(240,160,(245,210,120,255))
files={'Demo/light/chatroom_bubble_text_sender@2x.png':light,'Demo/dark/chatroom_bubble_text_sender@3x.png':dark,'Demo/cover.png':cover,'Demo/icons/icon.png':light,'Demo/other/icon.png':dark,
'Demo/color.css':b':root { --weui-BG-1:#f7faf9; --weui-FG-0:rgba(15,35,30,.95); --weui-FG-3:#66aa9980; --weui-BRAND:#228866; }\n@media (prefers-color-scheme: dark) { :root { --weui-BG-1:#112623; --weui-FG-0:#f1fffa; --weui-BRAND:#55ddbb; } }\n',
'Demo/dark/colors.xml':b'<resources><color name="weui_BG_2">#ff18332d</color></resources>',
'Demo/wu-theme.json':json.dumps({'version':1,'aliases':{'test_icon':'Demo/icons/icon','text_bubble_receiver':'chatroom_bubble_text_sender'}}).encode(),
'Demo/LICENSE.txt':b'Synthetic fixtures created for testing. CC0-1.0. No user or third-party theme assets.\n'}
def archive(name,items):
    with zipfile.ZipFile(root/name,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for path,data in sorted(items.items()):
            info=zipfile.ZipInfo(path,date_time=(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; info.external_attr=0o100600<<16; info.flag_bits|=0x800; z.writestr(info,data)
archive('synthetic-theme.zip',files)
archive('append-conflict.zip',{'Demo/icons/icon.png':cover,'Demo/new/added.png':light})
archive('append-no-conflict.zip',{'Demo/new/added.png':light})
svg=b'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><rect x="4" y="4" width="56" height="56" rx="12" fill="#228866"/><circle cx="32" cy="32" r="12" fill="#ffffff"/></svg>'
archive('synthetic-svg.zip',{'Vector/cover.svg':svg,'Vector/icon.svg':svg})
assets=root/'Synthetic.xcassets'; image=assets/'cover.imageset'; image.mkdir(parents=True,exist_ok=True)
(assets/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
(image/'Contents.json').write_text(json.dumps({'images':[{'filename':'cover.png','idiom':'universal','scale':'1x'}],'info':{'author':'xcode','version':1}}))
(image/'cover.png').write_bytes(cover)
print(json.dumps({p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(root.glob('*.zip'))},indent=2))
