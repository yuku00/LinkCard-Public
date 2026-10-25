"""Fast source regression; the CI additionally runs the real Swift coordinator."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
B=(R/'LinkCard/PCRBluetooth.swift').read_text()
P=(R/'LinkCard/PN532Identify.swift').read_text()
H=(R/'LinkCard/BLEPreferencesView.swift').read_text().split('private struct BLEConnectionConfirmation: View {',1)[1].split('struct BLEPreferencesView:',1)[0]
class ImmediateChannelContracts(unittest.TestCase):
 def test_actual_channel_uses_canonical_uuid_gate(self):
  self.assertNotIn('channel == ["FF00", "FF02", "FF01"]',P)
  self.assertIn('BLEProfile.canonicalUUID',P)
  self.assertIn('actualFF00ChannelIsValid',B)
 def test_first_discovery_arbitrates_without_scan_end(self):
  body=B.split('didDiscover peripheral:',1)[1].split('didConnect peripheral:',1)[0]
  self.assertIn('arbitrateDiscovery()',body)
  flush=B.split('private func flushDeferredConnectionPrompt()',1)[1].split('func connectionPromptDidAppear',1)[0]
  self.assertNotIn('!scanning',flush)
 def test_compact_pairing_not_form(self):
  self.assertNotIn('Form {',H)
  self.assertIn('selectedID = device.id',H)
  self.assertIn('xmark',H)
 def test_actual_gatt_and_rejection_visible(self):
  self.assertIn('ble.channelSummary',(R/'LinkCard/LocalDeviceViews.swift').read_text())
  self.assertIn('channelAdmissionFailure',B)
if __name__=='__main__': unittest.main()
