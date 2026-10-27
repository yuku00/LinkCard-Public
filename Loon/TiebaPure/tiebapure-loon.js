/* Loon http-request script. No uploads, storage, cookies or URL logging. */
(function () {
  function param(query, key) {
    var parts = query.split('&');
    for (var i = 0; i < parts.length; i++) {
      var at = parts[i].indexOf('=');
      var k = at < 0 ? parts[i] : parts[i].slice(0, at);
      if (decodeURIComponent(k.replace(/\+/g, ' ')) === key)
        return decodeURIComponent((at < 0 ? '' : parts[i].slice(at + 1)).replace(/\+/g, ' '));
    }
    return '';
  }
  function escape(s) { return s.replace(/[&<>"']/g, function(c) { return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]; }); }
  try {
    var url = String($request.url || '');
    var match = url.match(/^https:\/\/tieba\.baidu\.com\/mo\/q\/activityDiversion\/download\?([^#]*)/i);
    if (!match || ($request.method && $request.method.toUpperCase() !== 'GET')) { $done({}); return; }
    var page = param(match[1], 'page');
    var kw = param(match[1], 'kw').trim();
    var tid = param(match[1], 'tid').trim();
    var pid = param(match[1], 'pid').trim();
    var target, title;
    if (page === 'pb' && /^\d{1,20}$/.test(tid)) {
      target = 'tiebapure://thread/' + tid;
      if (/^\d{1,20}$/.test(pid)) target += '?pid=' + pid;
      title = '打开这篇帖子';
    } else if (page === 'frs' && kw && kw.length <= 200) {
      target = 'tiebapure://forum?kw=' + encodeURIComponent(kw);
      title = kw + '吧';
    } else {
      console.log('TiebaPure v3: unsupported page or missing destination');
      $done({}); return;
    }
    var body = '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>用 TiebaPure 打开</title><style>body{font:17px -apple-system,sans-serif;background:#f2f2f7;color:#17171a;margin:0;padding:70px 24px}main{max-width:460px;margin:auto;background:white;padding:28px;border-radius:24px}small{color:#277948}h1{font-size:25px;margin:18px 0}p{color:#64646b;line-height:1.7}a{display:block;text-align:center;background:#1769e0;color:white;text-decoration:none;padding:16px;border-radius:14px;margin-top:24px}</style></head><body><main><small>Loon 已接管 · TiebaPure v3</small><h1>' + escape(title) + '</h1><p>正在尝试打开 TiebaPure。如果没有打开，请点击下方按钮并允许 Safari 打开 App。</p><a id="open" href="' + escape(target) + '">打开 TiebaPure</a><p>此页面不会跳转到 App Store。</p></main><script>window.addEventListener("load",function(){setTimeout(function(){window.location.href=document.getElementById("open").href},180)});</script></body></html>';
    console.log('TiebaPure v3: local landing response');
    $done({response:{status:200,headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','Referrer-Policy':'no-referrer'},body:body}});
  } catch (_) {
    console.log('TiebaPure v3: invalid query; unchanged');
    $done({});
  }
})();
