"""Execute unmodified production style/scope/hooks on Foundation doubles, not UIKit."""
from pathlib import Path
import sys
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text()
abi=s[s.index('static BOOL ABI('):s.index('static void Set(')]
scope=s[s.index('static BOOL InExperiment('):s.index('#include "ScopedPreview.inc"')]
native=(Path(sys.argv[sys.argv.index('--native-source')+1]) if '--native-source' in sys.argv else r/'NativeCompact.inc').read_text()
compact=(r/'CompactCells.inc').read_text().replace('#include "NativeCompact.inc"',native)
actions=(r/'NativeActions.inc').read_text()
production=actions[:actions.index('static void InstallNativeActions')].replace('#include "CompactCells.inc"',compact)
if '--mutate-margin' in sys.argv:
    production=production.replace('margins.leading=10;', 'margins.leading=0;')
if '--mutate-native-size' in sys.argv:
    production=production.replace('@"value":@20','@"value":@40')
if '--mutate-document-square' in sys.argv:
    production=production.replace('CGSizeMake(20*MIN(1,ratio),20*MIN(1,1/ratio))','CGSizeMake(20,20)')
if '--mutate-native-trailing' in sys.argv:
    production=production.replace('CGFloat target=item==row ? -10 : 0;', 'CGFloat target=item==row ? -28 : -8;')
prefix=(r/'tests/style_doubles.inc').read_text()
cases=(r/'tests/style_public_cases.inc').read_text()+(r/'tests/style_native_cases.inc').read_text()
cases=cases.replace('int main(void)',(r/'tests/style_document_cases.inc').read_text()+'\nint main(void)')
cases=cases.replace('int main(void)',(r/'tests/style_trailing_cases.inc').read_text()+'\nint main(void)')
cases=cases.replace('int main(void)',(r/'tests/style_width_ready_cases.inc').read_text()+'\nint main(void)')
cases=cases.replace('PublicCases(); NativeCases();','PublicCases(); DocumentCases(); NativeCases(); TrailingCases(); WidthReadyCases();')
assert '#include "NativeCompact.inc"' not in production
Path(sys.argv[1]).write_text(prefix+abi+scope+production+cases)
