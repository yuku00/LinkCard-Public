"""Restricted GitHub transport. Verified system TLS; credentials never follow redirects."""
import json, os, ssl, urllib.request, urllib.error, urllib.parse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REPO='yuku00/LinkCard-Public'
class HTTPSOnlyRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlsplit(newurl).scheme!='https':
            raise RuntimeError('Refused non-HTTPS redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)

def request_bytes(method, path, data=None, limit=128*1024*1024):
    base='/repos/'+REPO
    if not (path==base or path.startswith(base+'/') or (method=='GET' and path=='/user')):
        raise ValueError('API path outside the authorized repository')
    name=os.environ.get('WU_GITHUB_TOKEN_NAME','LINKCARD_PUBLIC_GITHUB_TOKEN')
    token=(os.environ.get(name) or '').strip()
    if not token: raise RuntimeError(name+' is not set')
    body=None if data is None else json.dumps(data,ensure_ascii=False).encode('utf-8')
    request=urllib.request.Request('https://api.github.com'+path,data=body,method=method,
        headers={'Accept':'application/vnd.github+json','Content-Type':'application/json',
                 'User-Agent':'WeChatUnified-Build','X-GitHub-Api-Version':'2022-11-28','Cache-Control':'no-cache'})
    # Standard redirect handling copies regular headers; an unredirected header is
    # sent only to this initial api.github.com request, never artifact storage hosts.
    request.add_unredirected_header('Authorization','Bearer '+token)
    opener=urllib.request.build_opener(HTTPSOnlyRedirect(),urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    try:
        with opener.open(request,timeout=90) as response:
            payload=response.read(limit+1)
            if len(payload)>limit: raise RuntimeError('API response exceeds allowed size')
            return payload
    except urllib.error.HTTPError as error:
        raise RuntimeError('GitHub HTTP '+str(error.code)) from None
    except urllib.error.URLError as error:
        # Suppress request internals and signed redirect URLs.
        raise RuntimeError('Verified HTTPS transport failed: '+type(error.reason).__name__) from None

def api(method,path,data=None):
    payload=request_bytes(method,path,data)
    return json.loads(payload) if payload else None

if __name__=='__main__':
    value=api('GET','/repos/'+REPO)
    print(json.dumps({k:value.get(k) for k in ('full_name','private','default_branch','permissions')}))
