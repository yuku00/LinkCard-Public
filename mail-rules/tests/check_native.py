#!/usr/bin/env python3
"""Production manifest/boundary checks; executable behavior lives in native-host.m."""
import pathlib,re,plistlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class NativeBoundaryTests(unittest.TestCase):
    def test_shipping_sources(self):
        files=re.search(r'^MailRules_FILES\s*=\s*(.*)$',(ROOT/'Makefile').read_text(),re.M)[1].split()
        self.assertEqual(files,['Native.m','NativeCore.m','Theme.m','Trace.m'])
        self.assertEqual(plistlib.loads((ROOT/'MailRules.plist').read_bytes()),{'Filter':{'Bundles':['com.apple.mobilemail']}})
        self.assertIn('Version: 0.5.1',(ROOT/'control').read_text())
    def test_no_old_replay_or_global_routes(self):
        code=(ROOT/'Native.m').read_text()+(ROOT/'NativeCore.m').read_text()
        for token in ['applyFilterPredicate:', 'filteredMessageListWithPredicate:', 'prepareSection:', 'setDataSource:', 'setMailboxes:', 'setThreaded:', 'setPersistentDomain:', 'standardUserDefaults', 'CFPreferencesSetValue', 'EMMessageTransferAction', 'EMCreateMailboxChangeAction', 'EMMessageTransferAllAction', 'copyMessages:', 'NSURLSession', 'NSLog(', 'beginSearchWith', '@"result"']:
            self.assertNotIn(token,code,token)
        self.assertEqual(set(re.findall(r'CFSTR\("([^"]+)"\)',code)),{'configuration'})
        self.assertIn('dev.mailrules.native5',code)
        self.assertIn('id previous=ReloadOwner;ReloadOwner=vc;',code)
        self.assertIn('ReloadFrame=previousFrame;',code)
        self.assertIn('ReloadOwner=previous;',code)
        self.assertIn('MR5InvokeFactory(Simple,cls,cmd,boxes,repository,oldest,display,sort,transform,ignore,local)',code)
        self.assertIn('MR5PredicateTransform original=[transform copy]',code)
        self.assertIn('MR5Transform(base,original,local)',code)
        self.assertIn('@finally',code)
        self.assertIn('StartedKey',code)
        self.assertIn('if(finished) return;finished=YES;',code)
        self.assertIn('s->preview!=reportRule',code)
        self.assertIn('itemIDsPendingConfiguration',code)
        self.assertIn('itemIDsMissingMessageListItem',code)
    def test_move_create_use_native_interactions(self):
        code=(ROOT/'Native.m').read_text()
        for token in ['MR5Perform(valid,interaction', 'selectionWithMessageListItems:mailboxes:', 'object_getClass(explicitSelection)==object_getClass(selection)', '_showTransferPickerForNonPredictiveMoveOfMessages:', 'resultIfAvailable', 'MoveDelegateHook', 'nonretainedObjectValue]!=vc', 'stamp[@"context"]', 'initWithMailbox:account:validAccounts:', 'nil,account,@[account]', 'Get(editor,@"account")!=account']:
            self.assertIn(token,code)
        self.assertNotIn('setWillTransferMessages',code)
        self.assertNotIn('performMailboxChangeAction',code)
        self.assertIn('!BoxKeys(owner).count || Flag(owner,@"isSearchViewController")',code)
        create=code.split('- (void)createMailbox {',1)[1].split('- (void)mailboxEditingControllerDidFinish:',1)[0]
        self.assertIn('!MR5Context(owner,owner,BoxKeys(owner),previewContext)',create)
        self.assertIn('!preview || !local',create)
    def test_theme_stays_visual(self):
        code=(ROOT/'Theme.m').read_text()
        for token in ['MailboxPickerOutlineController','MessageListViewController','ConversationViewController','Restore(vc)','weakToWeakObjectsMapTable']:
            self.assertIn(token,code)
        for token in ['setDataSource:', 'numberOfItems', 'setMailboxes:', 'applyFilterPredicate:', 'setHidden:', 'HTML']:
            self.assertNotIn(token,code)
if __name__=='__main__':unittest.main(verbosity=2)
