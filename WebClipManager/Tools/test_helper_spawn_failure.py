"""Regression: execute production transport with posix_spawn returning EPERM."""
from pathlib import Path
import ctypes, errno, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as td:
    p = Path(td)
    (p/'deny.c').write_text('#include <spawn.h>\n#include <errno.h>\nint denied_spawn(pid_t *p,const char *s,const posix_spawn_file_actions_t *f,const posix_spawnattr_t *a,char *const v[],char *const e[]){return EPERM;}\n')
    subprocess.run(['cc','-shared','-fPIC','-Dposix_spawn=denied_spawn',str(root/'Sources/HelperClient.c'),str(p/'deny.c'),'-o',str(p/'deny.so')],check=True)
    lib=ctypes.CDLL(str(p/'deny.so'))
    class Diagnostic(ctypes.Structure):
        _fields_=[('stage',ctypes.c_char_p),('spawned',ctypes.c_int),('statusValid',ctypes.c_int),('waitError',ctypes.c_int)]
    out=ctypes.c_void_p(); length=ctypes.c_size_t(); status=ctypes.c_int(); diag=Diagnostic()
    code=lib.wcm_helper_run(str(Path('/bin/sh').resolve()).encode(),b'webclip-list',250,ctypes.byref(out),ctypes.byref(length),ctypes.byref(status),ctypes.byref(diag))
    assert code == errno.EPERM
    assert status.value == -255, 'BUG: rejected posix_spawn reported valid child exit'
    assert diag.stage == b'spawn' and diag.spawned == 0 and diag.statusValid == 0 and diag.waitError == 0
    assert not out.value and length.value == 0
    print('PASS: production spawn EPERM -> stage=spawn errno=1 spawned=0 statusValid=0 exit=unavailable')
    # Exercise real transport wait failure without creating or killing any process.
    (p/'wait.c').write_text('#include <spawn.h>\n#include <sys/wait.h>\n#include <errno.h>\nint fake_spawn(pid_t *p,const char *s,const posix_spawn_file_actions_t *f,const posix_spawnattr_t *a,char *const v[],char *const e[]){*p=12345;return 0;}\npid_t failed_wait(pid_t p,int *s,int o){errno=ECHILD;return -1;}\n')
    subprocess.run(['cc','-shared','-fPIC','-Dposix_spawn=fake_spawn','-Dwaitpid=failed_wait',str(root/'Sources/HelperClient.c'),str(p/'wait.c'),'-o',str(p/'wait.so')],check=True)
    waiter=ctypes.CDLL(str(p/'wait.so'))
    code=waiter.wcm_helper_run(str(Path('/bin/sh').resolve()).encode(),b'webclip-list',250,ctypes.byref(out),ctypes.byref(length),ctypes.byref(status),ctypes.byref(diag))
    assert code == errno.ECHILD and diag.waitError == errno.ECHILD
    assert diag.stage == b'waitpid' and diag.spawned == 1 and diag.statusValid == 0 and status.value == -255
    print('PASS: waitpid ECHILD -> spawned=1 statusValid=0 exit=unavailable')
