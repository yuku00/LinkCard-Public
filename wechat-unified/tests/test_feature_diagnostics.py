from pathlib import Path
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('candidates', ROOT / 'tools/generate_candidates.py')
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)

class FeatureDiagnostics(unittest.TestCase):
    def test_evidence_and_unassociated(self):
        m = g.generate(ROOT)
        rows = m['candidates']
        for category in ('账号','聊天搜索与撤回','多选','语音','表情','朋友圈','链接','小程序'):
            self.assertTrue(any(category in x['categories'] for x in rows), category)
        selected = next(x for x in rows if x['class']=='BaseMsgContentViewController' and x['selector']=='getSelectedMsgs' and x['kind']=='-')
        self.assertIn('多选', selected['categories'])
        self.assertIn('链接', selected['categories'])
        self.assertTrue(any(not x['class'] and x['selector'] for x in rows))
        self.assertEqual([], g.categories(['unrelated evidence']))
        self.assertEqual(g.render(m), g.render(g.generate(ROOT)))

    def test_read_only_ui_and_batch(self):
        s=(ROOT/'Sources/WUDiagnostics.m').read_text()
        for marker in ('按功能诊断','collectByCategory','候选报告预览','真实代理实例签名：未采集','运行时类声明（含继承）','未关联类','index+50','10*NSEC_PER_MSEC'):
            self.assertIn(marker,s)
        for forbidden in ('objc_msgSend', 'performSelector:', 'NSURLSession', 'writeToFile:'):
            self.assertNotIn(forbidden,s)
        self.assertIn('tests/test_feature_diagnostics.py',(ROOT/'tools/build.sh').read_text())
        self.assertIn('tests/test_feature_diagnostics.py',(ROOT/'tools/release.py').read_text())

if __name__ == '__main__': unittest.main()
