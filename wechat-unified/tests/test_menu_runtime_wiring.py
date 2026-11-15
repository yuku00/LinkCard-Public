from pathlib import Path

root = Path(__file__).resolve().parents[1]
menu = (root / 'Sources/WULinkMenu.inc').read_text()
image = (root / 'Sources/WUImageEntry.m').read_text()
tests = (root / 'tests/link_menu_native.m').read_text()
assert 'WUMenuActionCell(receiver,cmd,argument)' in menu
assert 'wuOwnerMenuLeaseKey' in menu and 'weakCell' in menu
assert 'WUMenuStoreLease(cell,owner' in menu
assert 'WUMenuAddImage(original,cell)' in menu
assert '图片转表情' in menu and 'm_nsImagePath' in menu
assert 'WUOpenMessageImageEditor(owner,lease[@"wrap"],current)' in menu
assert 'if(self.menuCurrent) return self.menuCurrent();' in image
assert 'Identity(wrap,account,session)' in image and 'Paths(wrap)' in image
assert 'objc_msgSend)(cell,((MMMenuItem *)menu[1]).action,menu[1])' in tests
assert 'objc_msgSend)(testOwner,((MMMenuItem *)menu[1]).action,menu[1])' in tests
print('menu wiring contract passed')
