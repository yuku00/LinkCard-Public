from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); e=(r/'Entry.m').read_text(); m=(r/'Makefile').read_text()
assert plistlib.loads((r/'FilesNativeProbe.plist').read_bytes())=={'Filter':{'Bundles':['com.apple.DocumentsApp']}}
assert 'Entry.m DualPane.m' in m and 'LifecycleTrace.m' not in m and 'NativeExperiment.m' not in m
assert 'Version: 0.7.9' in (r/'control').read_text()
for token in ('FPLifecycle','FPExperiment','NSLog(', 'NSFileManager', 'NSURLSession', 'writeToFile', 'stopObservingSources', 'removeSubscriberForToken:', 'setRootViewController:', 'UIDocumentPickerViewController'):
    assert token not in s+e, token
for token in ('index<2','[config copy]','initWithConfiguration:config sourceObserver:observer','identities containsObject:identity','fullDocumentManagerDelegate','uiBrowserDelegate','pane.nativeSplit=nil','pane.sourceObserver=nil','pane.configuration=nil','modalInPresentation=YES','UIUserInterfaceSizeClassCompact'):
    assert token in s, token
assert 'addChildViewController:pane' in s and 'addChildViewController:child' in s
assert 'rightBarButtonItems=items' in e and 'UIButton' not in e
assert s.index('InstallStateIsolation())') < s.index('initWithConfiguration:config sourceObserver:observer')
assert 'if(!OwnState(config))' in s
print('PASS: independent native factories, original root, transient state and no diagnostic recorder')
print('LIMIT: source checks are not device UI, back-stack isolation, or leak tests')
