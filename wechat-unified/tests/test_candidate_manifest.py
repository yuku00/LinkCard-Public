from pathlib import Path
import importlib.util
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('generator', ROOT / 'tools/generate_candidates.py')
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / 'Sources').mkdir()
    (root / 'Sources/a.m').write_text('''// WUHook(@"Fake", @"bad", NO, x);\nWUHook(@"Target", @"do:", NO, x);\nNSClassFromString(@"OnlyClass");\nNSSelectorFromString(@"loose:");\nclass_getInstanceMethod(NSClassFromString(@"Exact"), NSSelectorFromString(@"known"));\nNSSelectorFromString(variable);\n''')
    m = g.generate(root)
    rows = {(x['class'],x['selector'],x['kind']):x for x in m['candidates']}
    assert ('Target','do:','-') in rows and ('Fake','bad','-') not in rows
    assert ('','loose:','?') in rows and ('OnlyClass','','?') in rows
    assert ('Exact','known','-') in rows
    assert rows[('Target','do:','-')]['sources'] == ['Sources/a.m:2 WUHook']
    assert ('','m_nsUsrName','?') in rows and ('CContactMgr','getSelfContact','-') in rows
    assert ('EmoticonPickViewController','Confirm','-') in rows
    assert g.render(m) == g.render(g.generate(root))
source = (ROOT / 'Sources/WUDiagnostics.m').read_text()
for text in ('开始只读采集','分享候选报告','类名可能暴露其他插件','index+50','10*NSEC_PER_MSEC', 'objc_lookUpClass', 'class_getClassMethod', 'class_getInstanceMethod', 'method_getTypeEncoding', '未知（无记录）', '未关联类', '当前未发现', '绝不启用'):
    assert text in source, text
for forbidden in ('objc_msgSend', 'performSelector:', 'NSURLSession', 'writeToFile:'):
    assert forbidden not in source
assert (ROOT / 'Sources/WUCandidateManifest.inc').read_text() == g.render(g.generate(ROOT))
print('candidate manifest and diagnostics contract: OK')
