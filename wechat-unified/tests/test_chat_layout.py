from pathlib import Path
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

if __name__ == '__main__': unittest.main()
