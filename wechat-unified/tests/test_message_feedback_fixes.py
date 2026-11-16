import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class MessageFixContracts(unittest.TestCase):
    def test_emoticon_subclass_menu_is_hooked_without_replacing_link_handler(self):
        source = (ROOT / 'Sources/WULinkMenu.inc').read_text()
        self.assertIn('WUHook(@"EmoticonMessageCellView",@"operationMenuItems",NO,"@",@[]', source)
        self.assertIn('if(objc_getAssociatedObject(item,&wuLinkMenuItemKey)) return original;', source)
        self.assertIn('WUHook(@"TextMessageCellView",@"onLinkClicked:withRect:"', source)

    def test_repository_persists_before_dismissing_input(self):
        source = (ROOT / 'Sources/Repository.m').read_text()
        self.assertIn('if([self addParts:@[@{@"kind":@"text",@"text":text?:@""}] name:name]) [a dismissViewControllerAnimated:YES completion:nil]', source)
        self.assertIn('if([self addParts:parts name:name]) [a dismissViewControllerAnimated:YES completion:nil]', source)
        self.assertIn('return [self save:next]', source)
        self.assertIn('if(alert) [alert dismissViewControllerAnimated:YES completion:^{ [self notice:message]; }]', source)

if __name__ == '__main__':
    unittest.main()
