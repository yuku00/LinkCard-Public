'use strict';
// Node simulation only: exercise fresh-object retries across both factories.
// Node executes the production JS; this is not an Apple JSC or real-WeChat test.
const fs = require('fs'), vm = require('vm'), path = require('path'), assert = require('assert');
const file = path.resolve(__dirname, '../../Sources/WUMiniAdsScript.inc');
const source = fs.readFileSync(file, 'utf8').split('\n').filter(s => s.startsWith('"')).map(JSON.parse).join('');
let nativeShows = 0;
function factory() {
  const ad = {show() { nativeShows++; return Promise.resolve(); }, onError() {}, offError() {}};
  for (const k of ['destroy','onLoad','offLoad','hide','onResize','offResize','load','onClose','offClose']) ad[k] = () => {};
  return ad;
}
globalThis.wx = {createBannerAd:factory, createInterstitialAd:factory};
vm.runInThisContext(source)(() => true, () => true);
(async () => {
  let failures = 0;
  for (let i = 0; i < 80; i++) {
    const name = i % 2 ? 'createInterstitialAd' : 'createBannerAd';
    try { await wx[name]().show(); }
    catch (e) { assert.strictEqual(e.code, 'WU_MINI_AD_DISABLED'); failures++; }
  }
  assert.strictEqual(failures, 64);
  assert.strictEqual(nativeShows, 16);
  console.log('PASS: fresh-object retries share one bound and then use native show');
})().catch(e => { console.error(e); process.exitCode = 1; });
