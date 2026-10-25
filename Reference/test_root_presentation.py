"""Root presentation wiring contracts; runtime behavior is in BLESessionChecks."""
from pathlib import Path
import unittest
R = Path(__file__).resolve().parents[1]
class RootPresentationContracts(unittest.TestCase):
    def test_root_modal_arbitration_is_explicit_and_event_driven(self):
        b = (R/'LinkCard/PCRBluetooth.swift').read_text()
        self.assertIn('func setPresentationBlocker', b)
        self.assertIn('func flushDeferredConnectionPrompt', b)
        for p, names in {
            'ContentView.swift':['root.photos','root.nfc','root.logs'],
            'FusionShell.swift':['root.profile'],
            'LocalDeviceViews.swift':['device.settings','device.version','library.modal'],
            'BLEPreferencesView.swift':['device.profile'],
            'MistDesign.swift':['wallpaper.photos']}.items():
            source=(R/'LinkCard'/p).read_text()
            for name in names: self.assertIn('"'+name+'"',source)
        host=(R/'LinkCard/BLEPreferencesView.swift').read_text()
        self.assertNotIn('connectedScenes',host)
        self.assertNotIn('CADisplayLink',host)
    def test_native_runner_selects_existing_host_and_pn532_checks(self):
        runner=(R/'Tools/build_ipa.sh').read_text()
        for target in ['ble-session-checks','ble-profile-checks']:
            self.assertIn('build/'+target+' | tee',runner)
        self.assertIn('-only-testing:LinkCardTests/PN532IdentifyTests',(R/'Tools/test_mist_uikit.py').read_text())
        self.assertIn('presentationChecks()', (R/'Reference/BLESessionChecks.swift').read_text())
