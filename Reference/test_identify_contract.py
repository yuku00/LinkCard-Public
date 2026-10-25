from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
class IdentifyWiring(unittest.TestCase):
 def test_real_click_has_transport_and_cancel(self):
  b=(R/'LinkCard/PCRBluetooth.swift').read_text();v=(R/'LinkCard/LocalDeviceViews.swift').read_text()
  self.assertIn('func identifyCard()',b)
  self.assertIn('ble.identifyCard()',v)
  self.assertIn('NFCProIdentify.permits(',b)
  self.assertIn('identifyStep = .poll',b)
  self.assertIn('func cancelIdentification()',b)
  self.assertIn('identifyGeneration',b)
  self.assertIn('"device.identify"',v)
 def test_protocol_has_no_arbitrary_card_io(self):
  p=(R/'LinkCard/PN532Identify.swift').read_text()
  for forbidden in ['URLSession','UserDefaults','print(', 'InDataExchange','0x40','0x42','PCRPANDA']:
   self.assertNotIn(forbidden,p)
  self.assertIn('case .poll: return [0x01, 0x00]',p)
  self.assertIn('case .retries: return [0x05, 0x00, 0x00, 0x01]',p)
