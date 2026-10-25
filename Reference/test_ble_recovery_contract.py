"""Source-contract loop; not a Swift runtime/radio test. Host state tests live in BLESessionChecks."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
B=(R/'LinkCard/PCRBluetooth.swift').read_text()
P=(R/'LinkCard/BLEProfiles.swift').read_text()
def body(name, following): return B.split(name,1)[1].split(following,1)[0]
class RecoveryContracts(unittest.TestCase):
 def test_frontground_starts_new_discovery_cycle(self):
  self.assertIn('beginDiscoveryCycle()',body('func setForeground','func enterDeviceFlow'))
 def test_power_on_resets_only_for_state_transition(self):
  s=body('func centralManagerDidUpdateState','func centralManager(_ central: CBCentralManager, didDiscover')
  self.assertIn('previousState != .poweredOn',s)
  self.assertIn('beginDiscoveryCycle()',s)
 def test_manual_trusted_selection_bypasses_prompt(self):
  self.assertIn('connectTrusted(device)',body('func requestConnection','func cancelConnectionPrompt'))
 def test_discovery_prompt_excludes_saved_identity(self):
  self.assertIn('!preferences.trusted.contains',body('func finishDiscovery','func scheduleRetry'))
 def test_identify_exposes_reason_and_phase(self):
  self.assertIn('var identifyUnavailableReason: String?',B)
  self.assertIn('var identifyPhase',B)
  start=body('func identifyCard()','func cancelIdentification')
  self.assertIn('status = identifyMessage',start)
  self.assertLess(start.index('status = identifyMessage'),start.index('sendIdentifyBytes'))
 def test_restore_failure_not_silent_or_overwritten(self):
  self.assertIn('restorationWarning',P)
  self.assertIn('guard restorationWarning == nil',P)
  decoded_validation=P.split('value.trusted.allSatisfy',1)[1].split('return value',1)[0]
  self.assertNotIn('else { return Self() }',decoded_validation)
  self.assertIn('return restoreFailed()',decoded_validation)
 def test_explicit_remember_off_revokes_but_cancel_does_not(self):
  confirm=body('func confirmConnection','func resumeDiscovery')
  self.assertIn('else if preferences.restorationWarning == nil',confirm)
  self.assertIn('guard updatePreferences({ $0.trusted.removeAll { $0.id == device.id } }) else { return }',confirm)
 def test_retry_budget_guards_scan_itself(self):
  self.assertIn('attempts < 3',body('func scanAutomatically','func finishDiscovery'))
 def test_identify_error_retains_safe_failure_phase(self):
  self.assertIn('identifyFailurePhase = identifyPhase',body('func disconnect(', 'func readDeviceInformation'))
  for phase in ['starting','synchronizing','configuring','limiting','polling','finishing','completed']:
   self.assertIn('"'+phase+'"',B)
 def test_no_card_business_in_new_recovery_helpers(self):
  for name,end in [('func beginDiscoveryCycle','private var automaticAttempt'),('func connectTrusted','func cancelConnectionPrompt')]:
   for forbidden in ['identifyCard(', 'readVersion(', 'readDeviceInformation(', 'writeValue(', 'readValue(']:
    self.assertNotIn(forbidden,body(name,end))
 def test_close_does_not_forget_identity(self):
  self.assertNotIn('preferences.trusted',body('func cancelConnectionPrompt','func confirmConnection'))
if __name__=='__main__': unittest.main()
