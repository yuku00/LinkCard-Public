"""Compile and execute real production C transport against synthetic children only."""
from pathlib import Path
import subprocess, tempfile, ctypes, errno, time, os
root=Path(__file__).resolve().parents[1]
class Diagnostic(ctypes.Structure):
 _fields_=[('stage',ctypes.c_char_p),('spawned',ctypes.c_int),('statusValid',ctypes.c_int),('waitError',ctypes.c_int)]
with tempfile.TemporaryDirectory() as temp:
 p=Path(temp)
 subprocess.run(['cc','-shared','-fPIC',str(root/'Sources/HelperClient.c'),'-o',str(p/'transport.so')],check=True,timeout=30)
 print('Compiled production transport',flush=True)
 lib=ctypes.CDLL(str(p/'transport.so')); libc=ctypes.CDLL(None)
 fn=lib.wcm_helper_run
 fn.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_uint,ctypes.POINTER(ctypes.c_void_p),ctypes.POINTER(ctypes.c_size_t),ctypes.POINTER(ctypes.c_int),ctypes.POINTER(Diagnostic)]
 def run(body, expected, command=b'webclip-list', timeout=250):
  print('CASE:', body, flush=True)
  child=p/'child'
  fixture = {
   'print("{}",end="")': 'write(1,"{}",2);',
   'raise SystemExit(7)': 'return 7;',
   'import os,signal;os.kill(os.getpid(),signal.SIGKILL)': 'kill(getpid(),SIGKILL);',
   'import time;time.sleep(3)': 'sleep(3);',
   'import os;os.write(1,b"a"*(9*1024*1024))': 'char data[4096]={0}; for(int i=0;i<2304;i++) write(1,data,sizeof(data));',
   'print("not-json")': 'write(1,"not-json",8);',
   'print("no")': 'return 0;'
  }[body]
  (p/'fixture.c').write_text('#include <unistd.h>\n#include <signal.h>\nint main(void){'+fixture+'return 0;}')
  subprocess.run(['cc',str(p/'fixture.c'),'-o',str(child)],check=True,timeout=30)
  out=ctypes.c_void_p();size=ctypes.c_size_t();status=ctypes.c_int();diag=Diagnostic()
  start=time.monotonic();error=fn(os.fsencode(child),command,timeout,ctypes.byref(out),ctypes.byref(size),ctypes.byref(status),ctypes.byref(diag))
  assert error==expected,(error,expected,status.value)
  if error == errno.EINVAL:
   assert diag.stage == b'validate' and not diag.spawned and not diag.statusValid and status.value == -255
  else:
   assert diag.spawned and diag.statusValid, (diag.stage,diag.statusValid)
  if error == 0: assert diag.stage == b'complete'
  if error == errno.ECHILD: assert diag.stage == b'childExit'
  if error == errno.ETIMEDOUT: assert diag.stage == b'timeout'
  if error == errno.EFBIG: assert diag.stage == b'outputLimit'
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
 (p/'link').symlink_to(p/'child');out=ctypes.c_void_p();size=ctypes.c_size_t();status=ctypes.c_int();diag=Diagnostic()
 assert fn(os.fsencode(p/'link'),b'webclip-list',250,ctypes.byref(out),ctypes.byref(size),ctypes.byref(status),ctypes.byref(diag))==errno.EACCES
 print('PASS: real C transport success, exit, signal, timeout, cap, invalid commands, symlink')
 malformed=p/'invalid-executable'; malformed.write_bytes(b'not an executable\n'); malformed.chmod(0o755)
 out=ctypes.c_void_p();size=ctypes.c_size_t();status=ctypes.c_int();diag=Diagnostic()
 code=fn(os.fsencode(malformed),b'webclip-list',250,ctypes.byref(out),ctypes.byref(size),ctypes.byref(status),ctypes.byref(diag))
 assert code == errno.ENOEXEC, code
 assert diag.stage == b'spawn' and not diag.spawned and not diag.statusValid and status.value == -255
 print('PASS: real posix_spawn ENOEXEC -> stage=spawn statusValid=0 exit=unavailable')
