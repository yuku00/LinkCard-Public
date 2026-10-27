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
  self.assertEqual(t.count('void MRDShareError('),1,'Duplicate recorder tail')
  self.assertEqual(t.count('void MRDControl('),1)
  for forbidden in ['localizedDescription','predicateFormat','NSLog(', 'writeToFile:', 'NSURLSession','UIPasteboard']:
   self.assertNotIn(forbidden,t)
  self.assertIn('MRDCanSubmit()',s)
  self.assertIn('MRDAfterAlert',s)
  self.assertNotIn('[owner dismissViewControllerAnimated:',s)
  self.assertIn('not reached',t)
 def test_final_submit_guards_precede_native_calls(self):
  s=(R/'Native.m').read_text()
  move=s.split('static void MoveHook(',1)[1].split('static void (*Create)',1)[0]
  create=s.split('static void CreateHook(',1)[1].split('__attribute__((constructor))',1)[0]
  self.assertIn('MRDRequireSubmit(@"move.perform",interaction,NO)',move)
  self.assertLess(move.index('MRDRequireSubmit(@"move.perform",interaction,[stamp[@"dryRun"] boolValue])'),move.index('MR5Perform(valid,interaction'))
  self.assertLess(create.index('MRDRequireSubmit(@"create.commit"'),create.index('Create(editor,cmd)'))
  opened=s.split('- (void)moveLoaded {',1)[1].split('- (void)createMailbox {',1)[0]
  self.assertIn('if(!MoveReady)',opened)
  self.assertIn('allIDs.count>3',opened)
  self.assertIn('DiagnosticGuardKey',create)
 def test_all_targeted_boundaries_and_skip_reasons(self):
  sources=''.join((R/f).read_text() for f in ['Native.m','NativeCore.m','Theme.m'])
  stages=['ui.entry','ui.click','ui.transition','ui.lifecycle','scope.resolve','sender.factory','sender.ast','sender.selftest','rule.edit','rule.manage','rule.save','rule.toggle','rule.delete','reload.request','reload.enter','reload.local','reload.exit','thread.path','factory.hit','factory.transform','query.generated','list.refresh','selection.map','selection.item','preview.begin','preview.end','move.open','move.delegate','move.validate','move.perform','move.completion','create.open','create.commit','create.completion','theme.toggle','theme.apply','theme.section']
  for stage in stages:
   self.assertTrue('@"'+stage+'"' in sources or (stage=='sender.ast' and 'MRDAST(' in sources),stage)
  for reason in ['abi_mismatch','method_missing','scope_invalid','scope_changed','search','off_main','subclass','no_tls','context_mismatch','no_rules','disabled','future_pending','sync_failed','readback_mismatch','presentation_busy','not_visible']:
   self.assertIn('@"'+reason+'"',sources,reason)
  trace=(R/'Trace.m').read_text()
  self.assertIn('blocked_by_diagnostic',trace)
  self.assertIn('CommonCrypto/CommonDigest.h',trace)
  self.assertIn('CCHmac(',trace)
  self.assertIn('Init();@synchronized(Lock)',trace.split('void MRDDeclare(',1)[1].split('static NSArray',1)[0])
 def test_buttons_use_fixed_codes_not_private_titles(self):
  s=(R/'Native.m').read_text()
  action=s.split('static UIAlertAction *MRDAction(',1)[1].split('static void MRDAfterAlert',1)[0]
  self.assertIn('@"action":code',action)
  self.assertNotIn('@"title":title',action)
  for code in ['selected_sender','input_sender','manage','hide_off','hide_on','move_loaded','create','preview','save_mailbox','save_account','theme_on','theme_off','rule_off','rule_on']:
   self.assertIn('@"'+code+'"',action)
if __name__=='__main__': unittest.main(verbosity=2)
