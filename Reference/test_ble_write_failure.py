"""Source guards only. Swift fault-injected persistence paths execute in BLESessionChecks."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
class BLEWriteFailureContracts(unittest.TestCase):
    def test_no_ignored_coordinator_save_result(self):
        source=(R/'LinkCard/PCRBluetooth.swift').read_text()
        self.assertNotIn('preferences.save()',source)
        self.assertIn('guard preferencesStore.save(draft) else',source)
        self.assertNotIn('UserDefaults',source)
        host=(R/'Reference/BLESessionChecks.swift').read_text()
        self.assertIn('        persistenceFailureChecks()',host)
        self.assertIn('RejectingPreferencesDefaults',host)
        self.assertIn('preferences = draft',source)
    def test_failed_persistence_cannot_resume_automatically(self):
        source=(R/'LinkCard/PCRBluetooth.swift').read_text()
        self.assertIn('preferencesWriteFailed = true',source)
        auto=source.split('private func scanAutomatically()',1)[1].split('func finishDiscovery',1)[0]
        self.assertIn('!preferencesWriteFailed',auto)
        confirm=source.split('func confirmConnection',1)[1].split('func resumeDiscovery',1)[0]
        self.assertLess(confirm.index('updatePreferences'),confirm.index('dismissConnectionPrompt()'))
    def test_panel_wait_retains_identity_state_and_original_budget(self):
        source=(R/'LinkCardUITests/LinkCardFullAppTouchTests.swift').read_text()
        panel=source.split('private func panel(',1)[1].split('private func open()',1)[0]
        self.assertIn('identifier == %@ AND value == %@',panel)
        self.assertIn('expected.waitForExistence(timeout: 6)',panel)
        self.assertIn('XCTAssertTrue(result',panel)
