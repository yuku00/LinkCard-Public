"""Source guard for the simulator-observed missing MistBlurStore launch crash."""
from pathlib import Path
import unittest

class RootEnvironmentContract(unittest.TestCase):
    def test_blur_environment_wraps_tab_inset_and_sheet(self):
        source = (Path(__file__).resolve().parents[1] / 'LinkCard/ContentView.swift').read_text()
        root = source.split('    var body: some View {', 1)[1].split('    private var creationPage:', 1)[0]
        self.assertEqual(root.count('.environmentObject(cardBlur)'), 1)
        # Tabs now occupy a real VStack sibling slot, rather than overlaying a NavigationStack inset.
        self.assertGreater(root.index('.environmentObject(cardBlur)'), root.index('renderedContent'))
        # Compile-time opaque boundaries preserve the exact modifier chain.
        shell_content = source.split('    private var shellContent:', 1)[1].split('    private var interactiveContent:', 1)[0]
        interactive = source.split('    private var interactiveContent:', 1)[1].split('    private var renderedContent:', 1)[0]
        rendered = source.split('    private var renderedContent:', 1)[1].split('    var body: some View {', 1)[0]
        self.assertIn('FusionShell(state:', shell_content)
        self.assertIn('shellContent', interactive)
        self.assertIn('interactiveContent', rendered)
        self.assertNotIn('.environmentObject(cardBlur)', shell_content + interactive + rendered)
        shell = (Path(__file__).resolve().parents[1] / 'LinkCard/FusionShell.swift').read_text()
        self.assertIn('recordWorkbenchFrame("tabs")', shell)
        self.assertIn('VStack(spacing: 0)', shell)
        self.assertGreater(root.index('.environmentObject(cardBlur)'), root.index('.sheet('))
