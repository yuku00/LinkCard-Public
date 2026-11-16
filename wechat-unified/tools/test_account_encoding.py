#!/usr/bin/env python3
"""Run actual production signature matcher and class-method lookup on Apple runtime."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
core = (root / 'Sources/Core.m').read_text()
messages = (root / 'Sources/Messages.m').read_text()
start = core.index('static const char *Unqualified(')
end = core.index('BOOL WUHook(', start)
helper_start = messages.index('static BOOL Has(')
helper_end = messages.index('\n', helper_start)
service = (root / 'Sources/WUHostService.m').read_text()
assert 'Class legacy=NSClassFromString(@"MMServiceCenter")' in service
assert 'Has(legacy,@"defaultCenter","@",@[])' in service
assert 'Object(legacy,@"defaultCenter")' in service
assert 'Object(context,@"activeUserContext")' in service
assert 'Object(context,@"currentContext")' in service
if not shutil.which('xcrun'):
    print('SKIP Apple Objective-C runtime encoding regression: xcrun unavailable')
    raise SystemExit(77)
with tempfile.TemporaryDirectory(prefix='wu-account-encoding-') as tmp:
    work = Path(tmp)
    (work / 'account_match.inc').write_text(core[start:end] + messages[helper_start:helper_end] + '\n')
    binary = work / 'account-encoding'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                    '-I', str(work), str(root / 'tests/account_encoding_native.m'),
                    '-framework', 'Foundation', '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
