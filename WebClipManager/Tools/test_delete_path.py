import ctypes, os, pathlib, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temp:
    temp = pathlib.Path(os.path.realpath(temp))
    lib = temp / 'path.dylib'
    subprocess.run(['cc','-D_GNU_SOURCE','-shared','-fPIC',str(root/'Sources/DeletePath.c'),'-o',str(lib)],check=True)
    c = ctypes.CDLL(str(lib)); c.wcm_path_valid.argtypes=[ctypes.c_char_p]; c.wcm_path_valid.restype=ctypes.c_int
    c.wcm_path_equal_alias.argtypes=[ctypes.c_char_p,ctypes.c_char_p]; c.wcm_path_equal_alias.restype=ctypes.c_int
    c.wcm_open_directory.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.POINTER(ctypes.c_char_p),ctypes.POINTER(ctypes.c_int)]; c.wcm_open_directory.restype=ctypes.c_int
    for s in [b'',b'/',b'/a//b',b'/a/./b',b'/a/../b',b'/a/']: assert not c.wcm_path_valid(s)
    for s in [b'/a/b',b'/private/var/x',b'/var/x']: assert c.wcm_path_valid(s)
    assert c.wcm_path_equal_alias(b'/var/x',b'/private/var/x')
    for s in [b'/various/x',b'/var/../x',b'/var//x',b'/var/x/']:
        assert not c.wcm_path_equal_alias(s,b'/private/var/x')
    d=temp/'parent'; d.mkdir(); (d/'good.webclip').mkdir(); (d/'link.webclip').symlink_to(d/'good.webclip',target_is_directory=True)
    (temp/'ancestor').symlink_to(d,target_is_directory=True)
    def op(path, leaf):
        stage=ctypes.c_char_p(); err=ctypes.c_int(); fd=c.wcm_open_directory(os.fsencode(path),leaf,ctypes.byref(stage),ctypes.byref(err))
        if fd>=0: os.close(fd)
        return fd,stage.value,err.value
    assert op(d,b'good.webclip')[0]>=0
    fd,stage,err=op(d,b'link.webclip'); assert fd<0 and stage==b'leafOpen' and err
    fd,stage,err=op(temp/'ancestor',b'good.webclip'); assert fd<0 and stage==b'ancestorOpen' and err
    fd,stage,err=op(d,b'missing.webclip'); assert fd<0 and stage==b'leafOpen' and err
    assert op(d,b'..')[1]==b'pathValidation'
print('Synthetic lexical, alias, no-follow, missing and errno checks passed')
