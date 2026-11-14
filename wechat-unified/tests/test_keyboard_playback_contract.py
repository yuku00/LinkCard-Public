import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class PlaybackKeyboardContract(unittest.TestCase):
    def test_narrow_playback_scope_and_expiration(self):
        interaction = (ROOT / 'Sources/WUNativeInteractions.m').read_text()
        voice = (ROOT / 'Sources/Voice.m').read_text()
        callback = interaction.split('void WUNativePlaybackCall(', 1)[1].split('static void Touches(', 1)[0]
        touch = interaction.split('static void Touches(', 1)[1].split('static BOOL PatIdentity(', 1)[0]
        for marker in ('model==lease.model', 'Get(model,@"messageWrap")==lease.message',
                       'WUCurrentAccount()', 'WUChatSession(owner)',
                       'WUContextGenerationSnapshot()', 'editor.isFirstResponder',
                       'UIApplicationStateActive', 'scopeDepth=1', '@finally'):
            self.assertIn(marker, callback)
        for marker in ('PatIdentity(identity,account,session)', 'unsignedIntegerValue]==34',
                       'dispatch_async(dispatch_get_main_queue()', 'playbackLease==lease',
                       'if(!finished && playbackLease==lease)'):
            self.assertIn(marker, touch)
        self.assertIn('WUNativePlaybackCall(vm,value,^{', voice)
        self.assertNotIn(' becomeFirstResponder]', callback + touch)


if __name__ == '__main__':
    unittest.main()
