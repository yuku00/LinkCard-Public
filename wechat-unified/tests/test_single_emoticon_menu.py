import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class SingleEmoticonContract(unittest.TestCase):
    def test_menu_lease_and_fail_open(self):
        menu=(ROOT/'Sources/WULinkMenu.inc').read_text()
        self.assertEqual(menu.count('WUHook(@"BaseMessageCellView",@"filteredMenuItems:"'),1)
        for s in ['wu_saveEmoticonToPhotos_%lu:', 'WUMenuEmoticonEnabled()', 'unsignedIntegerValue]!=47', 'WUValidMD5(md5)', 'WULinkMessageReady(wrap)', 'wuEmoticonMenuTokenKey', 'Obj(c,@"viewModel")==m', 'Obj(m,@"messageWrap")==w', '[md5 isEqual:WUMenuEmoticonMD5(w)]', 'gen==generation', 'WUSaveEmoticonForWrap(owner,wrap,current,YES)', 'if(withEmoticon!=original) return withEmoticon', 'if(!objc_getAssociatedObject(item,&wuLinkMenuItemKey))']:
            self.assertIn(s,menu)
    def test_original_bytes_and_permission(self):
        src=(ROOT/'Sources/Messages.m').read_text()
        for s in ['WUSaveEmoticonForWrap(owner,wrap,current,NO)', 'if(!context()) return NO;', 'if(!verifyDigest) return YES;', 'WUEmoticonRead(path)', 'CC_MD5(data.bytes,(CC_LONG)data.length,digest)', 'if(![hex isEqualToString:md5.lowercaseString]) data=nil', 'data:original options:options', 'added && success && !error', 'requestAuthorizationForAccessLevel:PHAccessLevelAddOnly', 'Permission only. User must explicitly invoke the tool again.', 'if((verifyDigest && !context()) || !owner.viewIfLoaded.window']:
            self.assertIn(s,src)
    def test_native_and_whitelist(self):
        native=(ROOT/'tests/link_menu_native.m').read_text(); release=(ROOT/'tools/release.py').read_text()
        for s in ['msg.m_uiMessageType=47', 'Activate(testOwner,old,cell); assert(!saved)', 'generation++; Activate(testOwner,menu[1],cell); assert(!saved)', 'msg.m_nsEmoticonMD5=@"bad"']:
            self.assertIn(s,native)
        self.assertIn('tests/test_single_emoticon_menu.py',release)
if __name__=='__main__': unittest.main()
