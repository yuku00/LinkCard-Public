"""Wiring assertions only. Executable native semantics are tested separately."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[1]
def source(name):
    return (ROOT / 'Sources' / name).read_text()
class LibraryWiring(unittest.TestCase):
    def test_library_export_uses_checked_original_and_existing_picker(self):
        ui=source('EmoticonLibrary.m'); entry=source('MessageEntries.m')
        export=ui.split('- (void)exportRow:')[1].split('- (void)assign:')[0]
        self.assertIn('resource:row[@"id"]',export)
        self.assertIn('WUExportEmoticonData(self,held[@"data"]',export)
        self.assertIn('[weak current]',export)
        self.assertIn('导出原文件到文件App',ui)
        self.assertIn('发送后可在聊天中长按',ui)
        self.assertIn('此按钮本身不向官方表情库入库',ui)
        self.assertIn('bytes?:WUEmoticonRead(path)',entry)
        self.assertIn('NSString *type=WUEmoticonType(data)',entry)
        self.assertIn('initForExportingURLs:@[file] asCopy:YES',entry)
        self.assertIn('ExportEmoticon(owner,nil,[data copy],current)',entry)
    def test_host_selection_not_file_demo(self):
        binding = source('EmoticonLibraryBindings.inc')
        for item in ('getSelectedMsgs', '[selected count]!=1', '!=47', 'InSession(identity,account,target)', 'pathOfEmoticonForMd5:needUpdateTime:ignoreWxAM:', 'md5,NO,NO', 'selectionCurrent', '[Info(wrap) isEqual:capture[@"identity"]]'):
            self.assertIn(item, binding)
        for forbidden in ('UIImagePNGRepresentation', 'UIImageJPEGRepresentation', 'getAll', 'thumb', 'PHAsset', 'NSURLSession', 'DelMsg:'):
            self.assertNotIn(forbidden, binding)
    def test_selected_gif_action_reaches_store_after_confirmation(self):
        ui=source('EmoticonLibrary.m')
        self.assertIn('保存聊天所选GIF（仅本地库）',ui)
        self.assertIn('[self saveSelectedGIFOnly:YES]',ui)
        self.assertIn('不是微信官方心形表情入库',ui)
        save=ui.split('- (void)saveSelectedGIFOnly:')[1].split('- (void)importMenu')[0]
        self.assertLess(save.index('[self input:'),save.index('[self write:'))
        self.assertIn('dispatch_sync(dispatch_get_main_queue(),check)',save)
        self.assertIn('return selected && valid();',save)
        self.assertIn('current:selectedCurrent error:error',save)
        self.assertIn('importSelectedPath:capture[@"path"] md5:capture[@"md5"] GIFOnly:GIFOnly',save)
        for forbidden in ('UIImage', 'WUSubmit', 'AddEmoticon', 'PHPhoto'):
            self.assertNotIn(forbidden,save)

    def test_selected_gif_original_and_selection_gate(self):
        binding=source('EmoticonLibraryBindings.inc')
        self.assertLess(binding.index('selectedSnapshot=binding.capture()'),binding.index('WUShowEmoticonLibrary(owner,binding)'))
        self.assertIn('return current()?selectedSnapshot:nil',binding)
        method=source('EmoticonLibraryLogic.m').split('- (BOOL)importSelectedPath:')[1].split('- (BOOL)importFile:')[0]
        self.assertLess(method.index('!current || !current()'),method.index('WUEmoticonRead(path)'))
        self.assertIn('[WUEmoticonDigest(original) isEqual:md5]',method)
        self.assertIn('GIFOnly && ![WUEmoticonType(original) isEqual:@"com.compuserve.gif"]',method)
        self.assertIn('importData:original name:name group:group current:current',method)

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
