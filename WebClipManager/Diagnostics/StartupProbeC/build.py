#!/usr/bin/env python3
import hashlib, json, pathlib, plistlib, shutil, struct, subprocess, zlib, zipfile
ROOT = pathlib.Path(__file__).resolve().parent
OUT = ROOT / 'out'
OUT.mkdir(exist_ok=True)
def run(*args):
    return subprocess.check_output(args, text=True)
def png(path, size, letter):
    glyph = {'A':['01110','11011','11011','11111','11011','11011','11011'],
             'C':['01111','11000','11000','11000','11000','11000','01111']}[letter]
    bg = (25,85,185) if letter == 'A' else (180,65,25)
    scale = size // 10
    x0, y0 = (size-5*scale)//2, (size-7*scale)//2
    data = bytearray()
    for y in range(size):
        data.append(0)
        for x in range(size):
            xx, yy = (x-x0)//scale, (y-y0)//scale
            white = 0 <= xx < 5 and 0 <= yy < 7 and glyph[yy][xx] == '1'
            data.extend((255,255,255) if white else bg)
    def chunk(t, d):
        return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(data))+chunk(b'IEND',b''))
sdk = run('xcrun','--sdk','iphoneos','--show-sdk-path').strip()
binary = OUT / 'Probe-unsigned'
subprocess.run(['xcrun','--sdk','iphoneos','clang','-arch','arm64','-isysroot',sdk,
    '-miphoneos-version-min=16.0','-fobjc-arc','-O2','-framework','UIKit',
    '-framework','Foundation',str(ROOT/'main.m'),'-o',str(binary)],check=True)
report = {'toolchain':run('xcodebuild','-version'),'variants':{}}
for variant in ('C',):
    payload = OUT / ('package-'+variant) / 'Payload'
    app = payload / 'StartupProbe.app'
    app.mkdir(parents=True,exist_ok=True)
    exe = app/'StartupProbe'
    shutil.copy2(binary,exe)
    info = {'CFBundleIdentifier':'io.github.yuku00.webclip.startupprobe.'+variant.lower(),
        'CFBundleExecutable':'StartupProbe','CFBundleName':'StartupProbe'+variant,
        'CFBundleDisplayName':'探针 '+variant,'CFBundleVersion':'4','CFBundleShortVersionString':'1.0',
        'CFBundlePackageType':'APPL','CFBundleInfoDictionaryVersion':'6.0',
        'LSRequiresIPhoneOS':True,'MinimumOSVersion':'16.0','UIDeviceFamily':[1],
        'UIRequiredDeviceCapabilities':['arm64'],'UILaunchScreen':{},
        'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],
        'ProbeVariant':variant,'CFBundleIcons':{'CFBundlePrimaryIcon':{
            'CFBundleIconFiles':['Icon60'],'UIPrerenderedIcon':False}}}
    (app/'Info.plist').write_bytes(plistlib.dumps(info))
    for size, suffix in [(120,'@2x'),(180,'@3x')]:
        png(app/('Icon60'+suffix+'.png'),size,variant)
    ent = {'com.apple.private.security.container-required':False}
    entpath = OUT/('entitlements-'+variant+'.plist')
    entpath.write_bytes(plistlib.dumps(ent))
    subprocess.run(['ldid','-S'+str(entpath),str(exe)],check=True)
    signed = run('ldid','-e',str(exe))
    assert plistlib.loads(signed.encode()) == ent
    (OUT/('signed-entitlements-'+variant+'.plist')).write_text(signed)
    libs = run('xcrun','otool','-L',str(exe))
    symbols = run('xcrun','nm','-u',str(exe))
    assert 'swift' not in (libs+symbols).lower(), 'Unexpected Swift dependency'
    assert not (app/'Frameworks').exists()
    (OUT/('libraries-'+variant+'.txt')).write_text(libs)
    ipa = OUT/('WebClip-StartupProbe-'+variant+'-build4.ipa')
    with zipfile.ZipFile(ipa,'w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(payload.rglob('*')):
            if p.is_file(): z.write(p,p.relative_to(payload.parent))
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    (OUT/(ipa.name+'.sha256')).write_text(digest+'  '+ipa.name+'\n')
    report['variants'][variant] = {'bundle_id':info['CFBundleIdentifier'],'entitlements':ent,
        'dependencies':libs.splitlines()[1:],'no_swift_imports':True,'ipa_bytes':ipa.stat().st_size,'sha256':digest}
report['single_variant'] = 'C'
report['scope'] = 'Startup and user-triggered directory-open only; no Notes DB access claim'
(OUT/'verification.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
