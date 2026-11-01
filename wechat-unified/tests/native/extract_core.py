#!/usr/bin/env python3
"""Extract the actual Core registry, adding only the documented integration call."""
import pathlib, sys
source=pathlib.Path(sys.argv[1]).read_text()
a=source.index('static const char *Unqualified(')
b=source.index('NSArray *WUHookStatus(',a)
code=source[a:b]
if 'WUNativeRecordHook(' not in code:
    needle='    hooks[key]=@"installed"; return YES;'
    if code.count(needle)!=1:
        raise SystemExit('Core WUHook changed; review extraction/integration instead of silently mocking registry')
    code=code.replace(needle,'    WUNativeRecordHook(c,s,replacement,original);\n'+needle)
if 'WUNativeGuardAllowsHooks()' not in code:
    marker='    NSString *key=[NSString stringWithFormat:'
    if code.count(marker)!=1:
        raise SystemExit('Core WUHook entry changed; review guard integration')
    code=code.replace(marker,'    if(!WUNativeGuardAllowsHooks()) return NO;\n'+marker)
pathlib.Path(sys.argv[2]).write_text(code)
