from pathlib import Path
r=Path(__file__).resolve().parents[1]
b=(r/'BridgeSnapshot.inc').read_text()
assert '[container dismissViewControllerAnimated:' not in b, 'BUG: dismiss targets entire dual-pane container'
assert 'alert.viewIfLoaded.window || alert.presentingViewController' in b and 'dispatch_async(dispatch_get_main_queue()' in b
assert 'host.viewIfLoaded.window' in b
assert 'textView.editable=NO' in b
assert 'share.popoverPresentationController.barButtonItem' in b
assert b.index('FPBridgeCaptured=YES') > b.index('report.text=text')
assert 'FPBridgeSnapshot(container)' not in b[b.index('static void FPOfferBridgeCapture'):], 'snapshot must run after disappearance'
assert 'Snapshot unavailable' not in b
assert b.count('UIPasteboard.generalPasteboard.string=') == 1
assert '- (void)copyReport' in b
assert '@catch' in b and '采集失败' in b
print('PASS: 0.6.1 dismissal target, disappearance gate, attached host, readonly report, explicit copy, success-only consumption source contracts')
