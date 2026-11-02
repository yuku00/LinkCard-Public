'use strict';
// Executes production code, but the synthetic DOM is not a WebKit conformance test.
const vm=require('node:vm'), fs=require('node:fs'), assert=require('node:assert/strict');
const source=fs.readFileSync(0,'utf8'); let checks=0;
function fixture() {
  const c={mode:'select',token:'native-gesture-1',article:'https://mp.weixin.qq.com/s/synthetic',x:60,y:80,width:320,height:500,offsetX:0,offsetY:120,
    scrollX:0,scrollY:120,innerWidth:320,innerHeight:500,visualViewport:{scale:1,offsetLeft:0,offsetTop:0,width:320,height:500},
    location:{protocol:'https:',hostname:'mp.weixin.qq.com'},performance:{timeOrigin:1,now:()=>100},calls:0};
  c.window=c; c.top=c; c.listeners={}; c.mutations=[];
  c.addEventListener=(name,callback)=>{c.listeners[name]=callback;};
  c.removeEventListener=(name,callback)=>{if(c.listeners[name]===callback)delete c.listeners[name];};
  c.MutationObserver=class { constructor(callback){this.callback=callback;c.mutations.push(this);} observe(){} disconnect(){this.disconnected=true;} };
  c.document={URL:c.article,elementFromPoint(x,y){ c.calls++; assert.equal(x,60); assert.equal(y,80); return c.hit; }};
  c.HTMLImageElement=class {
    constructor(){ this.currentSrc='https://mmbiz.qpic.cn/synthetic.png'; this.complete=true; this.naturalWidth=2;this.naturalHeight=2;this.isConnected=true;this.parentElement=null; }
    addEventListener(){} removeEventListener(){}
    getRootNode(){return c.document;}
    getBoundingClientRect(){return {x:10,y:20,width:100,height:100,left:10,top:20,right:110,bottom:120};}
  };
  c.hit=new c.HTMLImageElement();
  c.getComputedStyle=()=>({transform:'none',perspective:'none',zoom:'1',visibility:'visible',opacity:'1',filter:'none',translate:'none',rotate:'none',scale:'none'});
  vm.createContext(c); return c;
}
function run(c,mode='select'){c.mode=mode;return vm.runInContext('(function(){'+source+'})()',c);}
function check(x){checks++;assert.ok(x);}
let c=fixture(), r=run(c); check(r.source===c.hit.currentSrc&&r.bytes===null); check(c.calls===1); check(run(c,'verify').token===c.token);
for(const mutate of [c=>c.hit={},c=>c.hit.complete=false,c=>c.hit.isConnected=false,c=>c.hit.getRootNode=()=>({}),c=>c.top={},c=>c.visualViewport.scale=2,c=>c.visualViewport.offsetLeft=1,c=>c.width=321,c=>c.offsetY=0,c=>c.x=NaN,c=>c.x=400,c=>c.document.URL+='changed',c=>c.location.hostname='example.invalid',c=>c.hit.naturalWidth=16000001,c=>c.hit.currentSrc='file:///tmp/a',c=>c.hit.currentSrc='blob:abc',c=>c.hit.currentSrc='http://mmbiz.qpic.cn/a',c=>c.hit.currentSrc='data:image/gif;base64,R0lGODlh',c=>{let p=c.hit;for(let i=0;i<65;i++){p.parentElement={parentElement:null};p=p.parentElement;}},c=>c.getComputedStyle=()=>({transform:'matrix(1,0,0,1,1,0)'})]) {
  c=fixture();mutate(c);check(run(c)===null);
}
for(const mutate of [c=>c.hit=new c.HTMLImageElement(),c=>c.hit.currentSrc+='?new',c=>c.token='page-forged-token',c=>c.document.URL+='?nav',c=>c.scrollY+=1,c=>c.visualViewport.height-=1,c=>c.performance.timeOrigin+=1,c=>c.performance.now=()=>90200,c=>c.hit.naturalHeight=3,c=>c.hit.getBoundingClientRect=()=>({x:11,y:20,width:100,height:100,left:11,right:111,top:20,bottom:120})]) {
  c=fixture();check(run(c)!==null);mutate(c);check(run(c,'verify')===null);check(run(c,'read')===null);
}
c=fixture();check(run(c,'read')===null); // No prior native selection token.
c=fixture();c.hit.currentSrc='data:image/png;base64,c3ludGhldGlj';r=run(c);check(r.direct&&r.source==='embedded'&&r.bytes===null);
check(run(c,'verify').bytes===null);check(run(c,'read').bytes===c.hit.currentSrc);
run(c,'clear');check(run(c,'read')===null);
c=fixture();run(c);c.token='different';run(c,'clear');c.token='native-gesture-1';check(run(c,'verify')!==null);
// No page-wide lookup, no request, and clearing a stale token cannot clear a newer one.
c=fixture();c.document.querySelectorAll=()=>{throw Error('enumeration forbidden');};c.fetch=()=>{throw Error('network forbidden');};check(run(c)!==null);
for(const event of ['scroll','resize','pagehide','hashchange','popstate']) { c=fixture();run(c);c.listeners[event]();check(run(c,'read')===null); }
c=fixture();run(c);c.mutations[0].callback();check(run(c,'verify')===null); // Attribute changed and restored still invalid.
c=fixture();run(c);run(c,'clear');check(c.mutations[0].disconnected && Object.keys(c.listeners).length===0);
console.log('article DOM: '+checks+' synthetic assertions; production fixed script, no network');
