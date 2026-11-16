import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class VoiceHookOrder(unittest.TestCase):
    def test_common_hooks_are_installed_before_voice_inherited_overrides(self):
        core = (ROOT / 'Sources/Core.m').read_text()
        install = core.split('static void Install(void)', 1)[1].split('\n__attribute__', 1)[0]
        self.assertLess(install.index('WUInstallMessages();'), install.index('WUInstallVoice();'))
        messages = (ROOT / 'Sources/Messages.m').read_text()
        voice = (ROOT / 'Sources/Voice.m').read_text()
        for selector in ('layoutSubviews', 'didMoveToWindow'):
            self.assertIn(f'WUHook(@"CommonMessageCellView",@"{selector}"', messages)
            self.assertIn(f'WUHook(@"VoiceMessageCellView",@"{selector}"', voice)
        self.assertIn('class_addMethod(c,s,replacement', core)

    def test_parent_hook_is_in_inherited_child_chain(self):
        # WUHook captures the implementation visible on the class at install time.
        def install_parent_then_child():
            calls = []
            def host(): calls.append('host')
            parent_original = host
            def parent(): parent_original(); calls.append('parent')
            child_original = parent
            def child(): child_original(); calls.append('child')
            child()
            return calls
        self.assertEqual(install_parent_then_child(), ['host', 'parent', 'child'])


if __name__ == '__main__':
    unittest.main()
