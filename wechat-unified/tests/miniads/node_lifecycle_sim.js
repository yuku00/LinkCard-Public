'use strict';
// Linux/Node simulation of the production JS, not the native hook or Apple JSC.
const fs = require('fs'), vm = require('vm'), path = require('path'), assert = require('assert');
const root = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(root,'Sources/WUMiniAdsScript.inc'),'utf8').split('\n')
  .filter(line => line.startsWith('"')).map(line => JSON.parse(line)).join('');
const setup = vm.runInThisContext(source, {filename:'WUMiniAdsScript.inc'});
let banner = true, interstitial = true, nativeShows = 0;
function factory() {
  const listeners = new Set();
  const a = {show(){nativeShows++; return Promise.resolve('native');},
    onError(f){listeners.add(f);}, offError(f){if (f === undefined) listeners.clear(); else listeners.delete(f);},
    emit(e){for (const f of listeners) f(e);}};
  for (const k of ['destroy','onLoad','offLoad','hide','onResize','offResize','load','onClose','offClose']) a[k] = function(){};
  return a;
}
globalThis.wx = {createBannerAd:factory, createInterstitialAd:factory, createRewardedVideoAd:factory};
assert.strictEqual(setup(() => banner, () => interstitial), 3);
const heartbeat = globalThis.__wuMiniAds_current_v1__, first = wx.createBannerAd;
for (let i=0; i<100000; i++) heartbeat();
assert.strictEqual(wx.createBannerAd, first);
const tick = () => new Promise(resolve => setImmediate(resolve));
const fails = p => assert.rejects(p, e => e.code === 'WU_MINI_AD_DISABLED' && e.errCode === -100001);
(async () => {
  let old;
  for (const create of [() => wx.createBannerAd(), () => wx.createInterstitialAd()]) {
    const ad = create(); old = ad; let callbacks = 0, promises = [];
    ad.onError(() => { callbacks++; if (callbacks < 20) promises.push(fails(ad.show())); });
    await fails(ad.show()); await tick(); await Promise.all(promises); await tick();
    assert.strictEqual(callbacks,1, 'same object retry must not trigger another error callback');
    await fails(ad.show()); await tick(); assert.strictEqual(callbacks,1);
    assert.strictEqual(nativeShows,0);
    let native = 0; ad.onError(e => { if (e.code === 'native') native++; });
    ad.emit({code:'native'}); assert.strictEqual(native,1, 'native errors remain registered');
    const fresh = create(); let freshCallbacks = 0, secondCallbacks = 0, removed = 0;
    const removedListener = () => removed++;
    fresh.onError(() => freshCallbacks++); fresh.onError(() => secondCallbacks++);
    fresh.onError(removedListener); fresh.offError(removedListener);
    await fails(fresh.show()); await tick();
    assert.deepStrictEqual([freshCallbacks, secondCallbacks, removed],[1,1,0], 'new object and listener removal');
    const late = create(); await fails(late.show()); let lateCallbacks = 0;
    late.onError(() => lateCallbacks++); await fails(late.show()); await tick();
    assert.strictEqual(lateCallbacks,1, 'show without listener does not consume notification');
  }
  // Simulate a promise-catch retry chain on one ad; local failures must not continue forever.
  for (const create of [() => wx.createBannerAd(), () => wx.createInterstitialAd()]) {
    const retry = create(); let localFailures = 0, retryResult;
    const beforeRetry = nativeShows;
    for (let attempt = 0; attempt < 20; attempt++) {
      try { retryResult = await retry.show(); break; }
      catch (e) { assert.strictEqual(e.code, 'WU_MINI_AD_DISABLED'); localFailures++; }
    }
    assert.strictEqual(retryResult, 'native', 'repeated local failures eventually fail open');
    assert.strictEqual(localFailures, 8);
    assert.strictEqual(nativeShows, beforeRetry + 1, 'ninth call reaches original exactly once');
    await fails(create().show()); // fail-open is per object, not global
  }
  let chainAttempts = 0;
  const chainAd = wx.createBannerAd();
  function catchRetry() {
    chainAttempts++;
    if (chainAttempts > 20) throw new Error('retry did not terminate');
    return chainAd.show().catch(catchRetry);
  }
  assert.strictEqual(await catchRetry(), 'native');
  assert.strictEqual(chainAttempts, 9, 'catch/show retry reaches original instead of endless local microtasks');
  nativeShows = 0;
  banner = false; interstitial = false; heartbeat();
  assert.strictEqual(wx.createBannerAd, factory);
  assert.strictEqual(wx.createInterstitialAd, factory);
  assert.strictEqual(wx.createRewardedVideoAd, factory);
  assert.strictEqual(await old.show(),'native');
  const native = wx.createInterstitialAd(); assert.strictEqual(await native.show(),'native');
  assert.strictEqual(nativeShows,2);
  console.log('PASS: production JS retry bound, explicit rejections, native events and off restoration');
})().catch(e => { console.error(e); process.exitCode = 1; });
