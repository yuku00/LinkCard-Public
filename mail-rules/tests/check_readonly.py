#!/usr/bin/env python3
"""Release boundary: source allowlist and absence of business/private value access."""
from pathlib import Path
import re
R=Path(__file__).resolve().parents[1]
expected=['readonly/Entry.m','readonly/Session.m','readonly/Graph.m','readonly/Metadata.m','readonly/Observer.m']
m=re.search(r'^MailRules_FILES\s*=\s*(.+)$',(R/'Makefile').read_text(),re.M)
assert m and m[1].split()==expected, 'Production still links non-readonly modules'
src='\n'.join(p.read_text() for p in (R/'readonly').glob('*.[mh]'))
for bad in ['objc_msgSend','valueForKey','object_getIvar','class_copyIvar','method_exchangeImplementations','CFPreferences','NSUserDefaults','NSPredicate','NSExpression','NSURLSession','NSURLConnection','localizedDescription','senderAddress','setSelected','selectItemAt','selectRowAt','performSelector','NSInvocation','NSLog','writeToFile','dataWithContents','MR5','MRD','MRState']:
    assert bad not in src, 'Forbidden production API: '+bad
assert 'strcmp(method_getTypeEncoding(method), "v24@0:8@16")' in src
assert src.count('ROOriginal(owner, command, event);')==1
assert 'production modules:' in src and 'query mutation hooks:none; rule engine absent' in src
assert '开始只读采集' in src and '停止分享' in src and '只读采集0.5.2' in src
assert '[host dismissViewController' not in src
assert 'Version: 0.5.2' in (R/'control').read_text()
postrm=(R/'layout/DEBIAN/postrm').read_text()
assert not re.search(r'\b(rm|defaults|killall|plutil)\b',postrm)
workflow_path=R.parent/'.github/workflows/mail-rules-roothide.yml'
if not workflow_path.exists(): workflow_path=R/'workflow/mail-rules-roothide.yml'
workflow=workflow_path.read_text()
assert 'tests/readonly-host.m' in workflow and 'tests/check_readonly.py' in workflow
assert not any(x in workflow for x in ['NativeCore.m','Trace.m','Theme.m','tests/native-host.m'])
print('PASS: production allowlist; no rules, value getters, networking or preference IO')
