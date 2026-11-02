#!/usr/bin/env python3
"""Source-only checks. These are deliberately NOT an Apple JSC runtime result."""
from pathlib import Path
import ast, json, re
root=Path(__file__).resolve().parents[2]
native=(root/'Sources/WUMiniAds.m').read_text()
script=''.join(json.loads(s) for s in (root/'Sources/WUMiniAdsScript.inc').read_text().splitlines() if s.startswith('"'))
assert len(script.encode())<8192
assert '[JSContext currentContext]' in native and 'currentArguments' not in native
invoke=native[native.index('static id Invoke('):native.index('void WUInstallMiniAds(')]
assert invoke.count('invokeOriginal)(')==1 and 'opaqueArgument)' in invoke
assert 'opaqueArgument.' not in invoke and '@catch' not in invoke
assert 'object_getClass(object)==invokerClass' in invoke
assert 'class_copyMethodList' in native and 'method_getNumberOfArguments(own)==3' in native
assert 'context.exception=savedException;' in native and 'context.exceptionHandler=savedHandler;' in native
assert 'JSObjectCallAsFunction' in native and 'JSEvaluateScript' in native
for forbidden in ['dispatch_', 'currentArguments', 'NSURL', 'evaluateScript:', 'setTimeout', 'setInterval', 'fetch(', 'XMLHttpRequest', 'console.', 'createRewardedVideoAd']:
    assert forbidden not in native+script, forbidden
assert script.count("factory('createBannerAd'")==1 and script.count("factory('createInterstitialAd'")==1
assert "WU_MINI_AD_DISABLED" in script and 'apply(reject,P,[error])' in script
assert 'listeners.size >= 64' in script and 'n < 8' in script
assert 's.own' in script and 'if (!owns(s)) return;' in script
assert "const show = slots[0].original" in script
assert "const ad = apply(f.original,this,arguments);" in script
core=(root/'Sources/Core.m').read_text()
settings=(root/'Sources/Settings.m').read_text()
for key in ('miniBannerAds','miniInterstitialAds'):
    assert core.count('@"'+key+'"')==2 and key in settings and key in native
ads=(root/'Sources/Ads.m').read_text()
assert 'WUInstallMiniAds();' in ads and 'return WUMiniAdsAvailable(key);' in ads
build=(root/'tools/build.sh').read_text()
assert 'WU_REQUIRE_APPLE_TESTS=1 python3 tests/miniads/run.py' in build
assert build.count('-framework JavaScriptCore')==2
release=(root/'tools/release.py').read_text(); ast.parse(release)
for name in ('Sources/WUMiniAds.h','Sources/WUMiniAds.m','Sources/WUMiniAdsScript.inc','tests/miniads/bridge.m','tests/miniads/fixture.js','tests/miniads/run.py','tests/miniads/contract.py'):
    assert repr(name) in release
ast.parse((root/'tests/miniads/run.py').read_text())
print('PASS source-only: current context/opaque bridge/bounded fixed script/config/build/allowlist')
