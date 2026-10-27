import pathlib, plistlib, re
root=pathlib.Path(__file__).resolve().parents[1]
s=(root/'Probe.m').read_text()
f=plistlib.loads((root/'FilesNativeProbe.plist').read_bytes())
assert f=={'Filter':{'Bundles':['com.apple.DocumentsApp']}}
for forbidden in ['objc_msgSend','performSelector:', 'valueForKey:', 'object_getIvar', 'ivar_getOffset', 'NSFileManager', 'NSFileCoordinator', 'NSURL', 'NSUserDefaults', 'NSLog(', 'printf(', 'writeToFile', 'initWithConfiguration:', 'sourceObserver:', 'dlopen(', 'method_exchangeImplementations']:
    assert forbidden not in s, forbidden
for required in ['NSPointerFunctionsObjectPointerPersonality','[NSThread isMainThread]','NOT CONSTRUCTED/NOT DISPLAYED','protocol_copyPropertyList2','class_copyMethodList','UIActivityViewController','UIWindowDidBecomeKeyNotification','v.majorVersion!=16 || v.minorVersion!=6']:
    assert required in s, required
assert 'dev.filesdualpane.nativeprobe' in (root/'control').read_text()
assert 'roothide' in (root/'Makefile').read_text()
# Every receiver getter used to traverse objects is public UIKit.
edges=re.findall(r'label:@"([^"]+)"',s)
assert set(edges)<= {'windows','windowScene','rootViewController','parent','presented','presenting','child','splitControllers','tabControllers'}
assert 'firefly' not in (root/'Makefile').read_text().lower()
print('PASS: scope, prohibited operations, metadata-only reflection, main-thread and stage assertions')
