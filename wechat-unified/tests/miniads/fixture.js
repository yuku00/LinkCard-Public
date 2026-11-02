'use strict';
function check(ok, label) { if (!ok) throw new Error(label); }
const jobs = [];
function rejected(p, label) {
  check(p instanceof Promise, label + ' Promise');
  jobs.push(p.then(() => { throw new Error(label + ' resolved'); }, e => {
    check(e.code === 'WU_MINI_AD_DISABLED' && e.errCode === -100001, label + ' local code');
  }));
}
let made = 0, lastOptions, lastReceiver, nativeShows = 0;
const factoryError = new Error('synthetic factory');
const methodError = new Error('synthetic native method');
function make(options = {}) {
  made++; lastOptions = options; lastReceiver = this;
  if (options.throwFactory) throw factoryError;
  const events = new Set(), ad = {}, refs = {};
  let expectedAd = ad;
  ad.show = function () {
    nativeShows++; check(this === expectedAd, 'native show receiver');
    if (options.throwShow) throw methodError;
    return ad.promise;
  };
  ad.promise = Promise.resolve('native-show');
  ad.onError = function (f) { if (options.throwRegister) throw methodError; events.add(f); return 'on-result'; };
  ad.offError = function (f) { if (!arguments.length || f === undefined) events.clear(); else events.delete(f); return 'off-result'; };
  for (const k of ['destroy','hide','load','onLoad','offLoad','onResize','offResize','onClose','offClose']) ad[k] = function () { return k; };
  ad.emit = e => { for (const f of events) f(e); };
  for (const k of Object.keys(ad)) refs[k] = ad[k];
  ad.refs = refs;
  if (options.frozen) Object.freeze(ad);
  if (options.readonly) Object.defineProperty(ad,'offError',{writable:false});
  if (options.accessor) Object.defineProperty(ad,'show',{get() { throw methodError; }});
  if (options.missing) delete ad.load;
  if (options.proxy) expectedAd = new Proxy(ad,{defineProperty() { throw methodError; }});
  return expectedAd;
}
const reward = make();
const rewardFactory = function () { return reward; };
globalThis.wx = {createBannerAd:make,createInterstitialAd:make,createRewardedVideoAd:rewardFactory};
const originalFactory = wx.createBannerAd;
setFlags(true, true);
check(waBridge(17,{sentinel:'synthetic'}) === true,'bridge return');
const firstWrapper = wx.createBannerAd;
waBridge(18,{sentinel:'synthetic'});
check(wx.createBannerAd === firstWrapper && firstWrapper !== originalFactory,'idempotent install');
check(wx.createRewardedVideoAd === rewardFactory && wx.createRewardedVideoAd() === reward,'reward identity');
for (const k of Object.keys(reward.refs)) check(reward[k] === reward.refs[k],'reward untouched '+k);
const options = {adUnitId:'SYNTHETIC_NOT_A_REAL_ID'};
const before = made, b = wx.createBannerAd(options), i = wx.createInterstitialAd(options);
check(made === before + 2 && lastOptions === options && lastReceiver === wx,'factory exactly once/identity');
for (const ad of [b,i]) {
  for (const k of ['load','destroy','hide','onLoad','offLoad','onClose','offClose']) check(ad[k] === ad.refs[k],'preserve '+k);
  const show = ad.show; waBridge(19,{}); check(ad.show === show,'ad not double wrapped');
}
let local = 0, native = 0, removed = 0;
const listener = e => { if (e.code === 'WU_MINI_AD_DISABLED') local++; else native++; };
const removedListener = () => removed++;
check(b.onError(listener) === 'on-result','onError return'); b.onError(listener);
b.onError(removedListener); check(b.offError(removedListener) === 'off-result','offError return');
const count = nativeShows;
rejected(b.show(),'banner'); rejected(i.show(),'interstitial');
check(nativeShows === count,'no native show while blocked');
b.emit({code:'NATIVE'}); check(native === 1,'original onError not swallowed');
const offAll = wx.createBannerAd(); offAll.onError(removedListener); offAll.offError(); rejected(offAll.show(),'off-all');
let laterRan = false;
const throws = wx.createBannerAd(); throws.onError(() => { throw new Error('synthetic listener'); });
throws.onError(() => { laterRan = true; }); rejected(throws.show(),'listener throw');
// No waBridge event between changing the native BOOL and these show calls.
setFlags(false,true);
check(b.show() === b.promise && b.show === b.refs.show,'disable immediately restores/transmits');
rejected(i.show(),'independent interstitial');
setFlags(true,false);
check(i.show() === i.promise,'independent disable');
waBridge(20,{});
const fresh = wx.createBannerAd(); rejected(fresh.show(),'re-enable fresh');
// Once retired/restored, an old object never dynamically captures a third-party method.
check(b.show() === b.promise,'old restored object remains original');
for (const options of [{frozen:true},{readonly:true},{missing:true},{proxy:true}]) {
  const ad = wx.createInterstitialAd(options); // interstitial switch currently off
  check(ad.show === ad.refs.show,'disabled factory not touched');
}
setFlags(true,true); waBridge(21,{});
for (const options of [{frozen:true},{readonly:true},{missing:true},{proxy:true}]) {
  const ad = wx.createInterstitialAd(options);
  check(ad.show === ad.refs.show && ad.onError === ad.refs.onError,'unsupported object rollback');
  check(ad.show() === ad.promise,'unsupported pass-through');
}
const accessor = wx.createBannerAd({accessor:true});
check(typeof Object.getOwnPropertyDescriptor(accessor,'show').get === 'function','getter not invoked');
try { wx.createBannerAd({throwFactory:true}); throw new Error('factory swallowed'); }
catch (e) { check(e === factoryError,'factory exception identity'); }
const registration = wx.createBannerAd({throwRegister:true});
try { registration.onError(listener); throw new Error('register swallowed'); }
catch (e) { check(e === methodError,'register exception identity'); }
const throwingShow = wx.createBannerAd({throwShow:true});
setFlags(false,true);
try { throwingShow.show(); throw new Error('show swallowed'); }
catch (e) { check(e === methodError,'disabled original exception identity'); }
const offCreated = wx.createBannerAd();
check(wx.createBannerAd === originalFactory && offCreated.show === offCreated.refs.show,'factory lazy restoration');
setFlags(true,true); waBridge(22,{});
const thirdAd = wx.createBannerAd(), capturedShow = thirdAd.show;
thirdAd.show = function () { return capturedShow.call(this); };
const thirdShow = thirdAd.show;
check(thirdAd.show() === thirdAd.promise && thirdAd.show === thirdShow,'third-party method no loop/no clobber');
const capturedFactory = wx.createBannerAd;
const thirdFactory = function () { return Reflect.apply(capturedFactory,this,arguments); };
wx.createBannerAd = thirdFactory; waBridge(23,{});
check(wx.createBannerAd === thirdFactory,'third-party factory not stolen');
const thirdCreated = wx.createBannerAd();
check(thirdCreated.show === thirdCreated.refs.show,'third-party factory never dynamically reconnected');
// Exact callback registry bound: the 65th listener is still registered natively, then object retires.
const bounded = wx.createInterstitialAd();
for (let n = 0; n < 65; n++) bounded.onError(() => {});
check(bounded.show === bounded.refs.show,'bounded listener retirement');
waBridge(24,{}); check(nativeDiagnostics() & 4,'unsupported reported without page data');
jobs.push(Promise.resolve().then(() => {
  check(local === 1 && removed === 0 && laterRan,'local onError/offError and throwing listener isolation');
}));
Promise.all(jobs).then(() => finish(true), e => { reportSyntheticFailure(String(e)); finish(false); });
