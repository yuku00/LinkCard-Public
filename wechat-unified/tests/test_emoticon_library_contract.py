"""Wiring assertions only. Executable native semantics are tested separately."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[1]
def source(name):
    return (ROOT / 'Sources' / name).read_text()
class LibraryWiring(unittest.TestCase):
    def test_host_selection_not_file_demo(self):
        binding = source('EmoticonLibraryBindings.inc')
        for item in ('getSelectedMsgs', '[selected count]!=1', '!=47', 'InSession(identity,account,target)', 'pathOfEmoticonForMd5:needUpdateTime:ignoreWxAM:', 'md5,NO,NO', 'selectionCurrent', '[Info(wrap) isEqual:capture[@"identity"]]'):
            self.assertIn(item, binding)
        for forbidden in ('UIImagePNGRepresentation', 'UIImageJPEGRepresentation', 'getAll', 'thumb', 'PHAsset', 'NSURLSession', 'DelMsg:'):
            self.assertNotIn(forbidden, binding)
    def test_one_submit_implementation_shared_by_repeat_and_library(self):
        text='\n'.join(p.read_text() for p in (ROOT / 'Sources').glob('*') if p.is_file())
        calls=re.findall(r'objc_msgSend\)\([^;]+NSSelectorFromString\(@"AddEmoticonMsg:MsgWrap:"\)', text)
        self.assertEqual(len(calls),1)
        self.assertIn('WUSubmitEmoticonCopy(source,Service(@"CMessageMgr")', source('Messages.m'))
        self.assertIn('return WUSubmitEmoticonCopy(source,manager,account,target,current);', source('EmoticonSubmission.m'))
        self.assertIn('WUSubmitEmoticonData(data,Service(@"CMessageMgr")',source('EmoticonLibraryBindings.inc'))
    def test_new_tool_preserves_two_existing_tools(self):
        groups=source('Groups.m'); logic=source('GroupLogic.m'); messages=source('Messages.m')
        for key in ('messageLinks','imageEmoji','emoticonLibrary'):
            self.assertIn('@"'+key+'"', groups)
            self.assertIn('@"'+key+'"', logic)
            self.assertIn('@"'+key+'"', messages)
        self.assertIn('WUIsEmoticonLibraryController(presented)',messages)
        self.assertIn('#include "EmoticonLibraryBindings.inc"', messages)
    def test_data_lifecycle_and_animated_preview(self):
        store=source('EmoticonLibraryLogic.m'); ui=source('EmoticonLibrary.m')
        for item in ('WUEmoticonRead(url.path)', 'NSPropertyListBinaryFormat_v1_0','WUEmojiAtomicCommit','WUDraftMediaReadSource','!Valid(s,self.account)','row[@"group"]=@""'):
            self.assertIn(item,store)
        self.assertNotIn('removeItemAt',store)
        self.assertNotIn('NSKeyedUnarchiver',store)
        for item in ('WUContextGenerationSnapshot()', '[self.cancel cancel]', 'CGImageSourceCreateThumbnailAtIndex', 'kCGImagePropertyGIFUnclampedDelayTime', 'self.binding.submit(held[@"data"])', '[self.submitted addObject:held[@"id"]]', 'selectionCurrent(capture)'):
            self.assertIn(item,ui)
        self.assertIn('emoticonMsgForImageData:errorMsg:',source('EmoticonSubmission.m'))
        self.assertNotIn('saveEmoticonToEmoticonDir',source('EmoticonSubmission.m'))
if __name__ == '__main__':
    unittest.main()
