from pathlib import Path
import sys
r=Path(sys.argv[1]) if __name__ == '__main__' and len(sys.argv)>1 else Path(__file__).resolve().parents[1]
s=(r/'LinkCard/FusionShell.swift').read_text(); g=(r/'LinkCard/FusionGeometry.swift').read_text()
o=(r/'LinkCard/DrawerRenderOwner.swift').read_text()
checks={
 'visible drawer isolates AX siblings without changing UIKit hit path': 'view.accessibilityViewIsModal = q > 0' in o,
 'detached drawer clears AX modal boundary': 'owner.view.accessibilityViewIsModal = false' in o,
 'no mode controls': 'private var modes:' not in s and 'state.desktop' not in s,
 'native layout animation, not published display tick': 'FusionProgress()' not in s,
 'actual notch background mask': 'FusionNotch().fill(style: FillStyle(eoFill: true))' in s,
 'no whole-panel rounded clip': '.clipShape(RoundedRectangle(cornerRadius: 28' not in s,
 'wallpaper not clipped to safe root': '\n            .clipped()' not in s,
 'light sidebar': '留一点空间' not in s and 'textFieldStyle(.plain)' in s,
 'no mode state': '@Published var desktop' not in g,
 'broad curve': 'let reach' in g,
 'drawer avoids presentation-body dispatch': 'DispatchQueue.main.async' not in g,
}
import unittest
class FullscreenContracts(unittest.TestCase):
    def test_source_contracts(self):
        for name, passed in checks.items():
            with self.subTest(name=name): self.assertTrue(passed)

if __name__ == '__main__':
    for k,v in checks.items(): print(('PASS ' if v else 'FAIL ')+k)
    raise SystemExit(not all(checks.values()))
