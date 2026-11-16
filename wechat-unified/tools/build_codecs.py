#!/usr/bin/env python3
"""Build pinned offline decoder and SILK encoder units; no downloads."""
import concurrent.futures, hashlib, json, pathlib, subprocess, sys
root=pathlib.Path(__file__).resolve().parents[1]; vendor=root/'Vendor'
manifest=json.loads((vendor/'manifest.json').read_text())
for name,digest in manifest['sha256'].items():
    assert hashlib.sha256((vendor/name).read_bytes()).hexdigest()==digest, name
platform=sys.argv[1]; assert platform in ('macosx','iphoneos','linux')
out=root/'build'/('codec-'+platform); out.mkdir(parents=True,exist_ok=True)
base=vendor/'amr/opencore/codecs_v2/audio/gsm_amr/amr_nb'
includes=[vendor/'silk/interface',vendor/'silk/src',vendor/'amr/oscl',base/'dec/src',base/'dec/include',base/'common/include',base.parent/'common/dec/include',base/'enc/src',root/'Sources']
flags=['-Os','-fPIC','-fvisibility=hidden','-fwrapv','-fno-strict-aliasing']+['-I'+str(p) for p in includes]
if platform!='linux':
    sdk=subprocess.check_output(['xcrun','--sdk',platform,'--show-sdk-path'],text=True).strip(); flags+=['-isysroot',sdk]
    if platform=='iphoneos': flags+=['-arch','arm64','-miphoneos-version-min=16.6']
files=[vendor/p for key in ('silk','silk_encoder','amr') for p in manifest[key]]+[root/'Sources/OfflineVoice.c',root/'Sources/WUSilkEncode.c']
def compile_one(pair):
    i,f=pair; obj=out/(str(i)+'.o'); cpp=f.suffix=='.cpp'
    compiler=(['g++' if cpp else 'gcc'] if platform=='linux' else ['xcrun','--sdk',platform,'clang++' if cpp else 'clang'])
    subprocess.run(compiler+flags+(['-std=c++98','-Wno-register'] if cpp else ['-std=c99'])+['-c',str(f),'-o',str(obj)],check=True)
    return str(obj)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: objects=list(pool.map(compile_one,enumerate(files)))
lib=out/'libWUOffline.a'
subprocess.run((['ar'] if platform=='linux' else ['xcrun','ar'])+['rcs',str(lib)]+objects,check=True)
for obj in objects: pathlib.Path(obj).unlink()
print(platform, len(files), 'offline codec units;',lib.stat().st_size,'archive bytes')
