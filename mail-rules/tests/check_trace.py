#!/usr/bin/env python3
"""Red-capable source seam: fail when production operations lack breadcrumbs."""
from pathlib import Path
import re, unittest
R=Path(__file__).resolve().parents[1]
class TraceCoverage(unittest.TestCase):
 def test_real_operation_breadcrumbs(self):
  s=(R/'Native.m').read_text()
  for method,stage in [('show','ui.entry'),('manage','rule.manage'),('beginPreview:(NSDictionary *)rule','preview.begin'),('moveLoaded','selection.map'),('createMailbox','create.open')]:
   body=s.split('- (void)'+method+' {',1)[-1].split('\n- (void)',1)[0]
   self.assertIn('@"'+stage+'"',body,method)
  for stage in ['scope.resolve','rule.save','rule.toggle','reload.enter','factory.hit','move.perform','create.commit','install.query']:
   self.assertIn('@"'+stage+'"',s)
 def test_privacy_and_lifecycle(self):
  s=(R/'Native.m').read_text(); t=(R/'Trace.m').read_text() if (R/'Trace.m').exists() else ''
  self.assertTrue(t,'Missing production recorder')
  for forbidden in ['localizedDescription','predicateFormat','NSLog(', 'writeToFile:', 'NSURLSession','UIPasteboard']:
   self.assertNotIn(forbidden,t)
  self.assertIn('MRDCanSubmit()',s)
  self.assertIn('MRDAfterAlert',s)
  self.assertNotIn('[owner dismissViewControllerAnimated:',s)
  self.assertIn('not reached',t)
if __name__=='__main__': unittest.main(verbosity=2)
