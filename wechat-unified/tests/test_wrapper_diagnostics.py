from pathlib import Path
import unittest

source = (Path(__file__).resolve().parents[1] / 'Sources/WUDiagnostics.m').read_text()

class WrapperDiagnostics(unittest.TestCase):
    def test_runtime_only_and_bounded(self):
        body = source.split('static NSString *WUWrapperReport', 1)[1].split('@interface WUDiagnostics', 1)[0]
        for token in ('NSClassFromString(@"MMServiceWrapper")', 'class_getSuperclass',
                      'class_copyMethodList', 'method_getTypeEncoding', 'class_copyPropertyList',
                      'property_getAttributes', 'object_getClass(cls)', 'depth<32',
                      'MIN(count,300u)', 'report.length<250000', '截断', '不能证明语义'):
            self.assertIn(token, body)
        for token in ('objc_msgSend', 'performSelector', 'class_copyIvarList', 'object_getIvar',
                      'valueForKey', 'WUHostService(', 'NSURLSession', 'writeToFile'):
            self.assertNotIn(token, body)

    def test_ui_and_existing_provider_snapshot(self):
        body = source.split('- (void)collectWrapper', 1)[1].split('- (void)collectCandidates', 1)[0]
        for token in ('WUAccountServiceDiagnosticSnapshot()', 'hasSuffix:', 'dispatch_async(self.queue',
                      'WUWrapperReport(provider)', 'text.editable=NO', 'pushViewController:preview',
                      '手动分享服务元数据？', '选择分享方式', 'UIActivityViewController'):
            self.assertIn(token, body)
        for token in ('WUHostService(', 'objc_msgSend', 'valueForKey', 'writeToFile', 'NSURLSession'):
            self.assertNotIn(token, body)
        self.assertIn('indexPath.section==0 && indexPath.row==1', source)

if __name__ == '__main__':
    unittest.main()
