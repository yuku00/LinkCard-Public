from pathlib import Path
import re
import unittest
R = Path(__file__).resolve().parents[1]

class ChatLayoutContract(unittest.TestCase):
    def test_account_storage_and_legacy_default(self):
        logic = (R/'Sources/GroupLogic.m').read_text()
        groups = (R/'Sources/Groups.m').read_text()
        for value in ('menu', 'grid2', 'grid3', 'grid4'):
            self.assertIn('@"'+value+'"', logic)
            self.assertIn('@"'+value+'"', groups)
        self.assertIn('WUSaveAccountOption(self.account,@"toolbarLayout"', groups)
        self.assertIn('?:@"menu"', groups)
    def test_shared_actions_and_invalidation(self):
        src = (R/'Sources/Messages.m').read_text()
        panel = (R/'Sources/ChatGrid.inc').read_text()
        self.assertIn('void (^run)(void)=^{', src)
        self.assertIn('@"run":[run copy]', src)
        self.assertIn('handler:^(UIAction *action){ run(); }', src)
        for guard in ('[account isEqual:Account()]', 'gen!=generation', '[session isEqual:Session(owner)]', 'containsObject:key'):
            self.assertIn(guard, src)
        self.assertIn('if(!ownGrid && !WUImageEntryOwnsNavigation', src)
        self.assertIn('dismissViewControllerAnimated:YES completion:^{ if(run) run(); }', panel)
        self.assertNotIn('MMInputToolView', panel)
        self.assertNotIn('inputAccessoryView', panel)

    def test_all_registered_actions_have_selection_and_dispatch(self):
        groups = (R/'Sources/Groups.m').read_text()
        logic = (R/'Sources/GroupLogic.m').read_text()
        messages = (R/'Sources/Messages.m').read_text()
        keys = lambda text: re.findall(r'@"([A-Za-z]+)"', text)
        choices = keys(re.search(r'WUChatToolKeys\(void\)\s*\{(.*?)\}', groups, re.S).group(1))
        allowed = keys(re.search(r'for\(id a in value\) if\(\[@\[(.*?)\] containsObject:a\]', logic, re.S).group(1))
        self.assertEqual(choices, allowed)
        self.assertEqual(len(choices), len(set(choices)))
        self.assertIn('WUChatToolKeys().count', groups)
        self.assertEqual(groups.count('WUChatToolKeys()[p.row]'), 2)
        self.assertIn('WUChatToolKeys()[path.row]', groups)
        labels = re.search(r'cell.textLabel.text=@\[([^\[\]]*)\]\[p.row\]; if\(\[WUToolbarActions', groups).group(1)
        self.assertEqual(len(re.findall(r'@"[^"]*"', labels)), len(choices))
        dispatch = messages.split('NSArray *selected=WUToolbarActions', 1)[1].split('if(menu.count)', 1)[0]
        titles = re.search(r'NSString \*title=@\{(.*?)\}\[key\]', dispatch, re.S).group(1)
        title_keys = re.findall(r'@"([A-Za-z]+)":', titles)
        branches = re.findall(r'\[key isEqual:@"([A-Za-z]+)"\]', dispatch.split('void (^run)(void)=^{', 1)[1])
        self.assertCountEqual(choices, title_keys)
        self.assertCountEqual(choices, branches)
        self.assertIn('for(NSString *key in selected)', dispatch)
        self.assertLess(dispatch.index('[grid addObject:'), dispatch.index('[menu addObject:'))

if __name__ == '__main__': unittest.main()
