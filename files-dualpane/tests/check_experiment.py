from pathlib import Path
root=Path(__file__).resolve().parents[1]
s=(root/'NativeExperiment.m').read_text()
p=(root/'Probe.m').read_text()
for forbidden in ('NSFileManager','NSUserDefaults','NSLog(', 'writeToFile', 'object_getIvar','valueForKey:', 'stopObservingSources]', 'removeSubscriberForToken:', 'setRootViewController:', 'openURL:', 'forwardInvocation:'):
    assert forbidden not in s, forbidden
for required in ('initWithConfiguration:config sourceObserver:observer', '[config copy]', 'setStateIdentifier:', 'setCollectionSupportsDragAndDrop:', 'UIDocumentBrowserViewControllerDelegate','uiBrowserDelegate','allowsDocumentCreation=NO','didPickDocumentsAtURLs:','commitPreviewOfDocumentAtURL:','performPreview:', 'PreviewABI()', 'RequiredMethods(', '20G75', 'addChildViewController:child', 'didMoveToParentViewController:self', 'willMoveToParentViewController:nil', 'removeFromParentViewController', 'weakObjectsPointerArray', 'stillAlive', 'GraphPreserved()', 'self.nativeSplit=nil', 'self.sourceObserver=nil', 'self.configuration=nil', 'modalInPresentation=YES'):
    assert required in s, required
assert s.index('NSString *failure=Preflight(') < s.index('initWithConfiguration:config')
assert s.index('PreviewABI()) return') < s.index('initWithConfiguration:config')
assert 'oldFull).delegate=' not in s
assert 'fullDocumentManagerDelegate")!=split' in s
assert 'FPLifecycleSetEventObserver(Observe)' in s
assert 'FPExperimentPresent(host)' in p and 'FPExperimentReport()' in p
assert 'NativeExperiment.m_CFLAGS = -fobjc-arc' in (root/'Makefile').read_text()
print('PASS native experiment: real initializer, ABI preflight, isolated delegate/preview guards, containment, weak cleanup, no file/network API or original-tree transplant')
print('NOTE source checks do not prove private native navigation, presentation, or eventual release on device')
