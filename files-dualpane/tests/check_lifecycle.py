from pathlib import Path
import re
s=Path(__file__).resolve().parents[1].joinpath('LifecycleTrace.m').read_text()
wrappers=[x for x in s.splitlines() if 'imp=imp_implementationWithBlock(' in x]
assert len(wrappers)==12
for line in wrappers:
    assert line.count(')orig)(')==1, line
    assert 'enter(h,' in line and 'leave(h,' in line
for forbidden in ('objc_msgSend', 'object_getIvar', 'ivar_getOffset', 'valueForKey:', 'NSLog(', 'NSFileManager', 'NSUserDefaults', 'dispatch_after', 'layoutSubviews', 'viewDidLayoutSubviews', 'retain]', 'release]', 'autorelease]', 'dlopen('):
    assert forbidden not in s, forbidden
for required in ('#if __has_feature(objc_arc)', 'SKIPPED_ABI', 'SKIPPED_INHERITED', 'NOT_LOADED', 'MISSING_SELECTOR', 'UNHIT', 'ECAP 8192', 'OCAP 2048', '180.0', 'protocol_copyMethodDescriptionList', 'protocol_copyProtocolList', 'class_getSuperclass', '20G75'):
    assert required in s, required
# Post-call recording must never dereference the old initializer self.
for line in wrappers:
    if '^id(' in line:
        assert 'leave(h,n,v); return v;' in line
print('PASS 12 typed wrappers: one original call each; MRC guard; cap, stop, ABI, privacy and targeted metadata checks')
print('NOTE static checks do not validate Objective-C compilation, runtime hooks, init ownership or device behavior')
