import pathlib, plistlib
root=pathlib.Path(__file__).resolve().parents[1]
s=(root/'Probe.m').read_text()
assert plistlib.loads((root/'FilesNativeProbe.plist').read_bytes())=={'Filter':{'Bundles':['com.apple.DocumentsApp']}}
for forbidden in ['objc_msgSend','performSelector:', 'valueForKey:', 'object_getIvar', 'NSFileManager', 'NSUserDefaults', 'NSLog(', 'writeToFile', 'objc_copyClassList']:
    assert forbidden not in s, forbidden
for required in ['[NSThread isMainThread]','UIActivityViewController','UIWindowDidBecomeKeyNotification','v.majorVersion!=16 || v.minorVersion!=6','停止并导出','FPLifecycleReport()','FPLifecycleStop()']:
    assert required in s, required
ctor=s[s.index('__attribute__((constructor))'):]
assert ctor.index('FPLifecycleStart()') < ctor.index('dispatch_async')
m=(root/'Makefile').read_text()
for required in ['FilesNativeProbe_FILES = Probe.m LifecycleTrace.m','Probe.m_CFLAGS = -fobjc-arc','LifecycleTrace.m_CFLAGS = -fno-objc-arc','roothide']:
    assert required in m
assert 'FilesNativeProbe_CFLAGS = -fobjc-arc' not in m
assert 'Version: 0.3.0' in (root/'control').read_text()
assert 'dev.filesdualpane.nativeprobe' in (root/'control').read_text()
print('PASS: synchronous lifecycle integration, MRC translation unit, explicit export, no broad dump, package identity')
