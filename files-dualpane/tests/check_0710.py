from pathlib import Path
import hashlib,json,re,subprocess,sys,tempfile
r=Path(__file__).resolve().parents[1]
s=(r/'LayoutSnapshot.inc').read_text(); native=(r/'NativeCompact.inc').read_text(); x=(r/'CrossPane.inc').read_text()
assert 'Version: 0.7.10' in (r/'control').read_text()
assert '#include "LayoutSnapshot.inc"' in (r/'DualPane.m').read_text()
assert '采集当前列表布局' in x and '重开最近布局报告' in x
for bad in ('layoutIfNeeded','layoutSubviews','setNeedsLayout','object_getIvar','ivar_getOffset','valueForKey:', 'contentsOfDirectory','enumeratorAt','dataWithContents','image.image','UIImagePNGRepresentation','NSLog(', 'writeToFile:', 'NSURLSession','removeItemAtURL:','setContentConfiguration:', 'selectItemAtIndexPath:', 'setDataSource:', 'absoluteString', 'lastPathComponent', 'localizedDescription'):
    assert bad not in s,bad
assert '[self.navigationController dismissViewControllerAnimated:YES completion:nil]' in s
assert '[container dismissViewControllerAnimated:' not in s
assert s.index('alert.viewIfLoaded.window || alert.presentingViewController') < s.index('FPLCapture(container,index)')
start=s.index('static void FPLCapture('); body=s[start:s.index('// Same dismissal boundary')]
assert body.index('FPLCell(cell,item[@"kind"])') < body.index('NSDictionary *snapshot=') < body.index('dataWithJSONObject:snapshot') < body.index('FPLayoutLastReport=text; FPLShow(container)')
assert body.index('dispatch_get_global_queue') < body.index('resourceValuesForKeys:') < body.index('dispatch_get_main_queue') < body.index('FPLCell(cell,item[@"kind"])')
assert 'if(FPLayoutLastReport) { FPLShow(container); return; }' in s
assert s.count('UIPasteboard.generalPasteboard.string=')==1
for token in ('graph.views.count>=100','self.constraints.count>=500','self.inspected>=2000','candidates.count>=24','chosen.count>=3','@"truncated"','@"frameInCell"','@"wrong_runtime_type"','@"abi_mismatch"','@"containsEllipsis"','@"customSpacingAfter"','@"compression"','@"textSlot"'):
    assert token in s,token
assert 'FPNativeIdentity(cell)' not in s and 'FPCompactNative(' not in s and 'FPPlanTrailing(' not in s
# Observation deltas are the only NativeCompact changes from pinned 0.7.9.
delta=json.loads((r/'tests/layout_observation_delta.json').read_text()); restored=native
for op in reversed(delta['operations']):
    assert op['new'] and restored.count(op['new'])==1, 'nonunique observation hunk'
    restored=restored.replace(op['new'],op['old'],1)
assert hashlib.sha256(restored.encode()).hexdigest()==delta['baselineSHA256']
reasons=json.loads((r/'tests/layout_reason_sites.json').read_text())
assert set(reasons)==set(re.findall(r'FPLayoutReject\(@"[^"]+",@"([^"]+)"\)',native))
for reason,info in reasons.items(): assert '@"'+reason+'":@"'+info['meaning']+'"' in s
with tempfile.TemporaryDirectory() as d:
    host=Path(d)/'snapshot.m'; subprocess.run([sys.executable,str(r/'tests/layout_host.py'),str(host)],check=True)
    assert 'static NSDictionary *FPLCell' in host.read_text() and 'SnapshotCases();' in host.read_text()
print('PASS 0.7.10 source contract: explicit one-shot capture, background metadata/JSON, capture before report sheet, safe dismissal/reopen, fixed reasons, no content/network/I/O or layout setters')
print('PASS NativeCompact observation-only reverse delta matches pinned 0.7.9 SHA256',delta['baselineSHA256'])
print('LIMIT schema host must run on macOS; actual device constraints and report dismissal still need manual verification')
