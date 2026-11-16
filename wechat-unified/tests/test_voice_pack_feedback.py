from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'Sources' / 'VoicePacks.m').read_text()

class VoicePackFeedbackTests(unittest.TestCase):
    def test_send_result_dismisses_alert_not_pack_controller(self):
        start = SOURCE.index('__weak UIAlertController *sendAlert=a;')
        end = SOURCE.index('- (void)audioPlayerDidFinishPlaying:', start)
        body = SOURCE[start:end]
        self.assertIn('[sendAlert dismissViewControllerAnimated:YES completion:', body)
        self.assertNotIn('[self dismissViewControllerAnimated:YES completion:^{ [self notice:result]', body)
        self.assertIn('发送接口未返回结果', body)

    def test_incompatible_row_still_explains_send(self):
        start = SOURCE.index('- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:')
        body = SOURCE[start:]
        self.assertIn('语音包版本、格式或配对校验不匹配', body)
        self.assertIn('UIAlertActionStyleCancel', body)
        self.assertIn('[menu dismissViewControllerAnimated:YES completion:', body)

    def test_voice_extension_precedes_fields_and_submission(self):
        voice=(Path(__file__).resolve().parents[1] / 'Sources' / 'VoiceSendLogic.m').read_text()
        start=voice.index('id message=WUCreateVoiceMessage')
        attach=voice.index('NSSelectorFromString(@"setM_extendInfoWithMsgType:")',start)
        fields=voice.index('NSArray *objects=',attach)
        insert=voice.index('VoiceServiceInvoke(manager',fields)
        self.assertLess(start,attach); self.assertLess(attach,fields); self.assertLess(fields,insert)
        self.assertIn('WUVoiceExactSignature(allocated,@"init","@",@[])',voice)
        self.assertIn('m_refMessageWrap"))!=message',voice)
        self.assertIn('语音扩展未绑定，未提交',voice)

    def test_actions_dismiss_only_the_row_menu(self):
        body = SOURCE[SOURCE.index('- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:'):]
        for call in ('[self pairRow:row]', '[self exportRow:row]', '[self edit:row deleting:NO]', '[self edit:row deleting:YES]'):
            self.assertIn('[menu dismissViewControllerAnimated:YES completion:^{ ' + call, body)
            self.assertNotIn('[self dismissViewControllerAnimated:YES completion:^{ ' + call, body)

if __name__ == '__main__':
    unittest.main()
