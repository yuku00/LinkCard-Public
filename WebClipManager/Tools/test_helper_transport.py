"""Compile and execute real production C transport against synthetic children only."""
from pathlib import Path
import subprocess, tempfile, ctypes, errno, time, os
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temp:
 p=Path(temp)
 subprocess.run(['cc','-shared','-fPIC',str(root/'Sources/HelperClient.c'),'-o',str(p/'transport.so')],check=True,timeout=30)
 print('Compiled production transport',flush=True)
 lib=ctypes.CDLL(str(p/'transport.so')); libc=ctypes.CDLL(None)
 fn=lib.wcm_helper_run
 fn.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_uint,ctypes.POINTER(ctypes.c_void_p),ctypes.POINTER(ctypes.c_size_t),ctypes.POINTER(ctypes.c_int)]
 def run(body, expected, command=b'webclip-list', timeout=250):
  child=p/'child'
  child.write_text('#!/usr/bin/env python3\n'+body+'\n');child.chmod(0o755)
  out=ctypes.c_void_p();size=ctypes.c_size_t();status=ctypes.c_int()
  start=time.monotonic();error=fn(os.fsencode(child),command,timeout,ctypes.byref(out),ctypes.byref(size),ctypes.byref(status))
  assert error==expected,(error,expected,status.value)
  assert time.monotonic()-start<2
  value=ctypes.string_at(out,size.value) if out else b''
  if out: libc.free(out)
  return value,status.value
 assert run('print("{}",end="")',0)[0]==b'{}'
 assert run('raise SystemExit(7)',errno.ECHILD)[1]==7
 assert run('import os,signal;os.kill(os.getpid(),signal.SIGKILL)',errno.ECHILD)[1]==-9
 run('import time;time.sleep(3)',errno.ETIMEDOUT)
 run('import os;os.write(1,b"a"*(9*1024*1024))',errno.EFBIG,timeout=2000)
 run('print("not-json")',0)
 run('print("no")',errno.EINVAL,command=b'notes-list')
 run('print("no")',errno.EINVAL,command=b'webclip-list /tmp')
 # Symlink executable rejected before spawn.
 (p/'link').symlink_to(p/'child');out=ctypes.c_void_p();size=ctypes.c_size_t();status=ctypes.c_int()
 assert fn(os.fsencode(p/'link'),b'webclip-list',250,ctypes.byref(out),ctypes.byref(size),ctypes.byref(status))==errno.EACCES
 print('PASS: real C transport success, exit, signal, timeout, cap, invalid commands, symlink')
