#!/usr/bin/env python3
"""Source-bound isolation checks + synthetic call-order model; not a device test."""
import pathlib, plistlib, unittest, copy, re
ROOT=pathlib.Path(__file__).resolve().parents[1]
class SafetyTests(unittest.TestCase):
    def test_production_excludes_all_legacy_hooks(self):
        make=(ROOT/'Makefile').read_text()
        files=re.search(r'^MailRules_FILES\s*=\s*(.*)$',make,re.M)[1].split()
        self.assertEqual(files,['Safety.m','Theme.m'])
        code='\n'.join((ROOT/f).read_text() for f in files)
        for forbidden in ['setMailboxes:', 'setDataSource:', '_reloadDataSource', '_updateFilters', 'prepareSection:', 'applyFilterPredicate:', 'filteredMessageList', 'EMObjectID', 'EMMessage', 'standardUserDefaults', 'setPersistentDomain:', 'CFPreferencesSetValue', 'removePersistentDomain', 'transform =', 'setDataSource:', 'reloadData', 'numberOfItems', 'setHidden:', 'NSURLSession', 'sqlite3', 'NSLog(']:
            self.assertNotIn(forbidden,code,forbidden)
        self.assertEqual(set(re.findall(r'CFSTR\("([^"]+)"\)',code)),{'themeEnabled','dev.mailrules.theme'})
        self.assertEqual(plistlib.loads((ROOT/'MailRules.plist').read_bytes()),{'Filter':{'Bundles':['com.apple.mobilemail']}})
    def test_ui_scope_and_restore(self):
        code=(ROOT/'Theme.m').read_text()
        for name in ['MailboxPickerOutlineController','MessageListViewController','ConversationViewController']:
            self.assertIn(name,code)
        for token in ['weakToWeakObjectsMapTable','weakToStrongObjectsMapTable','NSDirectionalEdgeInsets','preferredFontForTextStyle:','Restore(vc)','return result;','CFPreferencesAppSynchronize(CFSTR("dev.mailrules.theme"))']:
            self.assertIn(token,code)
        self.assertNotIn('method_exchangeImplementations',code)
        self.assertNotIn('UIAppearance',code.replace('// Per-controller appearances, never UIAppearance/global navigation bars.',''))
    def test_legacy_global_restore_is_red_capable(self):
        # Reduced model of actual IPA global apply: all section sources receive p.
        section={'recent':'native-unread','followup':'native-followup'}
        before=copy.deepcopy(section)
        # Old Remember(global) + restore() calls the global original again.
        def global_apply(p):
            for key in section: section[key]=p
        global_apply('old-global')
        self.assertNotEqual(section,before)
        self.assertNotEqual(section['followup'],before['followup'])
    def test_disabled_chain_preserves_home_and_original_calls(self):
        # Synthetic account names/counts, no private screenshot data in public tests.
        home={'all':120,'accounts':[('A',11),('B',2),('C',60)],
              'shortcuts':['flagged','unread','attachments','followup','trash'],
              'folders':[('registration/inbox',47),('archive',0)]}
        before=copy.deepcopy(home); trace=[]
        ds=object(); a=object(); b=object(); args=(object(),object(),object())
        # Production manifest contains NONE of these hooks: direct host invocation.
        def original(owner,name,*values):
            trace.append((owner,name,values)); return ds
        sequence=[(a,'setMailboxes:',(args[0],)),(a,'setMailboxes:forceReload:',(args[0],True)),
            (a,'_setMailboxes:',(args[0],)),(a,'_reloadDataSource',()),
            (a,'setDataSource:',(ds,)),(a,'prepareSection:messageList:',args[:2]),
            (a,'_updateFilters',()),(a,'applyFilterPredicate:ignoreMessagesPredicate:section:',args),
            (b,'setDataSource:',(ds,)),(b,'applyFilterPredicate:ignoreMessagesPredicate:',args[:2])]
        for owner,name,values in sequence:
            self.assertIs(original(owner,name,*values),ds)
        self.assertEqual(trace,sequence)
        for observed,expected in zip(trace,sequence):
            self.assertIs(observed[0],expected[0])
            for x,y in zip(observed[2],expected[2]): self.assertIs(x,y)
        self.assertEqual(home,before)
    def test_multiowner_appearance_restore(self):
        original={'background':'native','tint':'user'}; toolbar=copy.deepcopy(original)
        snapshots={}; owner=None
        def apply(who):
            nonlocal owner
            if owner is not None: toolbar.update(snapshots.pop(owner))
            snapshots[who]=copy.deepcopy(toolbar); owner=who
            toolbar.update(background='grouped',tint='semantic')
        def restore(who):
            nonlocal owner
            if who==owner: toolbar.update(snapshots.pop(who)); owner=None
        apply('A'); apply('B'); restore('A')
        self.assertEqual(toolbar['background'],'grouped')
        restore('B'); self.assertEqual(toolbar,original)
if __name__=='__main__': unittest.main(verbosity=2)
