#!/usr/bin/env python3
"""Synthetic descriptor-bound recycle tests; no iOS system API is exercised."""
import ctypes, errno, os, pathlib, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as td:
    p=pathlib.Path(td); lib=p/'copy.so'
    subprocess.run(['cc','-std=c11','-D_GNU_SOURCE','-shared','-fPIC','-O2',str(ROOT/'Sources/RecycleCopy.c'),'-o',str(lib)],check=True)
    c=ctypes.CDLL(str(lib),use_errno=True); callback=ctypes.CFUNCTYPE(ctypes.c_int,ctypes.c_void_p)
    c.WCMRecycleCopy.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_char_p,ctypes.c_char_p,callback,ctypes.c_void_p]
    c.WCMRecycleInspect.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_char_p,ctypes.c_ulong]
    c.WCMRecycleRestore.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_char_p,callback,ctypes.c_void_p]
    c.WCMRecycleRemove.argtypes=[ctypes.c_int,ctypes.c_char_p]
    src=p/'source'; trash=p/'trash'; dst=p/'dest'; outside=p/'outside'
    for d in (src,trash,dst,outside): d.mkdir()
    clip=src/'fixture.webclip'; clip.mkdir(); (clip/'Info.plist').write_bytes(b'fixture'); (clip/'nested').mkdir(); (clip/'nested/data').write_bytes(b'content')
    (outside/'keep').write_bytes(b'keep')
    s,t,d=[os.open(x,os.O_RDONLY|os.O_DIRECTORY) for x in (src,trash,dst)]
    never=callback(lambda _:0)
    assert c.WCMRecycleCopy(s,t,b'fixture.webclip',b'good',never,None)==0
    buf=ctypes.create_string_buffer(201)
    assert c.WCMRecycleInspect(t,b'.incomplete-good',buf,len(buf))==0 and buf.value==b'fixture.webclip'
    assert c.WCMRecycleRestore(t,d,b'.incomplete-good',never,None)==0
    assert (dst/'fixture.webclip/nested/data').read_bytes()==b'content'
    assert c.WCMRecycleRestore(t,d,b'.incomplete-good',never,None)<0 and ctypes.get_errno()==errno.EEXIST
    assert (dst/'fixture.webclip/nested/data').read_bytes()==b'content'
    manifest=trash/'.incomplete-good/manifest'; original=manifest.read_bytes()
    for bad in (original+b'garbage',original.replace(b'fixture.webclip',b'../evil.webclip'),original.replace(b'backupOnly',b'deleted'),original.replace(b'fixture',b'fi\x00ture')):
        manifest.write_bytes(bad)
        assert c.WCMRecycleInspect(t,b'.incomplete-good',buf,len(buf))<0
    manifest.write_bytes(original)
    for name in (b'../outside',b'.incomplete-../../outside',b'outside',b'.incomplete-.'):
        assert c.WCMRecycleRemove(t,name)<0
    os.symlink(outside,trash/'.incomplete-escape')
    assert c.WCMRecycleRemove(t,b'.incomplete-escape')<0
    os.symlink(outside,trash/'.incomplete-good/files/link')
    dst2=p/'dest2'; dst2.mkdir(); d2=os.open(dst2,os.O_RDONLY|os.O_DIRECTORY)
    assert c.WCMRecycleRestore(t,d2,b'.incomplete-good',never,None)<0
    assert (outside/'keep').read_bytes()==b'keep' and (clip/'Info.plist').read_bytes()==b'fixture'
    os.close(d2)
    assert c.WCMRecycleRemove(t,b'.incomplete-good')==0
    assert (outside/'keep').read_bytes()==b'keep'
    assert not (trash/'.incomplete-good').exists()
    os.mkdir(trash/'.incomplete-partial'); (trash/'.incomplete-partial/junk').write_bytes(b'x')
    assert c.WCMRecycleInspect(t,b'.incomplete-partial',buf,len(buf))<0
    assert c.WCMRecycleRemove(t,b'.incomplete-partial')==0
    for fd in s,t,d: os.close(fd)
    print('PASS: manifest schema, restore bytes/conflict, traversal and symlinks, scoped incomplete cleanup')
