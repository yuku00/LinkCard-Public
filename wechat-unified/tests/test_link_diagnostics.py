from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
flow = (root/'Sources/MessageEntries.m').read_text()
diag = (root/'Sources/WUDiagnostics.m').read_text()
binding = (root/'Sources/MessageEntryBindings.inc').read_text()
header = (root/'Sources/WUDiagnosticRing.h').read_text()
# UIAlertController owns its presentation-controller delegate; only non-alert sheets may use ours.
assert 'if(![controller isKindOfClass:UIAlertController.class]) controller.presentationController.delegate=weak;' in flow
# Only enum constants or the boolean completion mapping may reach the recorder.
calls = re.findall(r'WURecordDiagnosticEvent\(([^;]+?)\);', flow)
assert len(calls) >= 15
assert all(re.fullmatch(r'WUDiag\w+|ok\?WUDiagSystemAccepted:WUDiagSystemRejected', c) for c in calls), calls
for name in ('EntrySelected','EntryManual','RejectNoAccount','RejectBegin','RejectNoCandidates','RejectDestination','TransitionRejected','TransitionStarted','TransitionCompleted','TransitionCancelled','PresentRejected','PresentException','SystemRequested','SystemAccepted','SystemRejected'):
    assert 'WUDiag'+name in flow+binding and 'WUDiag'+name in header
assert flow.index('WURecordDiagnosticEvent(ok?WUDiagSystemAccepted:WUDiagSystemRejected)') < flow.index('if(![flow valid]) { [flow finish]; return; }', flow.index('completionHandler:^(BOOL ok)'))
assert '@synchronized (WUDiagnosticsLock.class)' in diag
assert 'self.events=WUEventSnapshot()' in diag and '[self.events componentsJoinedByString:@"\\n"]' in diag
assert 'self.results[indexPath.row] copy' in diag and '类名和方法名可能包含敏感' in diag
assert 'UIActivityViewController' in diag and 'NSURLSession' not in diag
print('link diagnostic contract: OK')
