#!/usr/bin/env python3
"""Portable synthetic exercise of the production streaming copy implementation."""
import ctypes, os, pathlib, subprocess, tempfile, hashlib
ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as td:
    p = pathlib.Path(td); lib = p/'copy.so'
    subprocess.run(['cc','-std=c11','-D_GNU_SOURCE','-shared','-fPIC','-O2',str(ROOT/'Sources/RecycleCopy.c'),'-o',str(lib)],check=True)
    c = ctypes.CDLL(str(lib), use_errno=True); callback = ctypes.CFUNCTYPE(ctypes.c_int,ctypes.c_void_p)
    c.WCMRecycleCopy.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_char_p,ctypes.c_char_p,callback,ctypes.c_void_p]
    c.WCMRecycleCopy.restype=ctypes.c_int
    source=p/'source'; store=p/'recycle'; source.mkdir(); store.mkdir(); clip=source/'fixture.webclip'; clip.mkdir()
    (clip/'Info.plist').write_bytes(b'fixture only')
    with (clip/'big').open('wb') as f:
        for _ in range(128): f.write(b'fixture!' * 65536)  # 64 MiB
    sf=os.open(source,os.O_RDONLY|os.O_DIRECTORY); df=os.open(store,os.O_RDONLY|os.O_DIRECTORY)
    never=callback(lambda _:0); cancelled=callback(lambda _:1)
    def run(identifier, tx, cb=never): return c.WCMRecycleCopy(sf,df,identifier.encode(),tx.encode(),cb,None)
    def digest(f):
        h=hashlib.sha256()
        with f.open('rb') as stream:
            for chunk in iter(lambda:stream.read(65536),b''): h.update(chunk)
        return h.digest()
    assert run('fixture.webclip','ok')==0
    assert digest(clip/'big')==digest(store/'.incomplete-ok/files/big')
    assert (store/'.incomplete-ok/manifest').read_text().endswith('status=backupOnly\n')
    assert run('../fixture.webclip','bad')<0
    assert run('fixture.webclip','cancel',cancelled)<0 and not (store/'.incomplete-cancel').exists()
    calls=[0]
    def cancel_during(_):
        calls[0]+=1
        return calls[0] >= 8
    assert run('fixture.webclip','midcancel',callback(cancel_during))<0
    assert not (store/'.incomplete-midcancel/manifest').exists() and (clip/'big').exists()
    assert run('fixture.webclip','ok')<0 and (clip/'big').exists()
    os.symlink('/etc/passwd',clip/'link')
    assert run('fixture.webclip','symlink')<0 and not (store/'.incomplete-symlink/manifest').exists()
    assert (clip/'big').stat().st_size == 64*1024*1024
    os.close(sf); os.close(df)
    print('PASS: 64 MiB streaming, bytes, invalid id, cancellation, collision, symlink, source preserved')
