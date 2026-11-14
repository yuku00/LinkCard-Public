from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/WUDiagnostics.m').read_text()
settings = (root / 'Sources/Settings.m').read_text()
assert 'WUShowDiagnostics(self)' in settings
assert 'self.hooks=WUHookStatus()' in source
assert 'objc_copyClassList(&count)' in source
assert 'class_copyMethodList' in source
assert 'MIN(count,2000u)' in source and 'MIN(n,100u)' in source
assert 'matches.count<100' in source and 'generation==self.generation' in source
assert 'dispatch_async(self.queue' in source
assert 'q.length<2 || q.length>80' in source
assert 'self.visibleHooks=filtered' in source
assert '不额外附带搜索词或运行时搜索结果' in source
assert '账号状态：未知' in source and '应用签名：未验证' in source
for forbidden in ('NSURLSession', 'NSURLConnection', 'writeToFile:', 'NSUserDefaults', 'performSelector:', 'objc_msgSend'):
    assert forbidden not in source, forbidden
print('diagnostics static contract: OK')
