from pathlib import Path
import unittest
S=(Path(__file__).resolve().parents[1]/'Sources/Messages.m').read_text()
class Regression(unittest.TestCase):
 def test_search_uses_traced_host_relay(self):
  self.assertIn('initMsgSearchHelper:',S); self.assertIn('onEditAndSearch',S); self.assertIn('setM_contact:',S)
  self.assertNotIn('Has(v,@"onSearchItem"',S)
 def test_repeat_display_not_gated_by_send_readiness(self):
  line=next(x for x in S.splitlines() if 'BOOL show=cell.window' in x)
  self.assertNotIn('RepeatReady(',line)
 def test_mixed_model_fallback_is_message_identity_only(self):
  self.assertIn('indexOfObjectIdenticalTo:model',S)
  self.assertIn('Obj(candidate,@"messageWrap")==wrap',S)
  self.assertIn('if(index!=NSNotFound) return',S)
 def test_group_never_uses_room_id_as_sender(self):
  self.assertIn('group?([m[@"from"] isEqual:account]?account:m[@"real"]):m[@"from"]',S)
 def test_send_still_checks_ready_and_session(self):
  body=S.split('- (void)repeatMessage {',1)[1].split('\n@end',1)[0]
  self.assertIn('!InSession(frozen,account,session)',body)
  self.assertIn('!RepeatReady(source)',body)
  self.assertIn('WUSubmitEmoticonCopy',body)
 def test_search_relay_validates_contact_and_did_appear(self):
  self.assertIn('[Str(contact,@"m_nsUsrName") isEqual:session]',S)
  self.assertIn('SearchRelayAppeared,&searchRelayAppearOriginal',S)
  self.assertIn('initMsgSearchHelper:"),0',S)
if __name__=='__main__': unittest.main()
