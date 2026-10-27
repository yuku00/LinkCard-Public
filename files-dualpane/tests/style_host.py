"""Execute unmodified production style/scope/hooks on Foundation doubles, not UIKit."""
from pathlib import Path
import sys
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text()
abi=s[s.index('static BOOL ABI('):s.index('static void Set(')]
scope=s[s.index('static BOOL InExperiment('):s.index('#include "ScopedPreview.inc"')]
compact=(r/'CompactCells.inc').read_text().replace('#include "NativeCompact.inc"',(r/'NativeCompact.inc').read_text())
actions=(r/'NativeActions.inc').read_text()
production=actions[:actions.index('static void InstallNativeActions')].replace('#include "CompactCells.inc"',compact)
if '--mutate-margin' in sys.argv:
    production=production.replace('margins.leading=10;', 'margins.leading=0;')
if '--mutate-native-size' in sys.argv:
    production=production.replace('@"value":@20','@"value":@40')
prefix=(r/'tests/style_doubles.inc').read_text()
cases=(r/'tests/style_public_cases.inc').read_text()+(r/'tests/style_native_cases.inc').read_text()
assert '#include "NativeCompact.inc"' not in production
Path(sys.argv[1]).write_text(prefix+abi+scope+production+cases)
