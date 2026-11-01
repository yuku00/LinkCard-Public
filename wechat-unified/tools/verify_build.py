"""Verify one successful published build and snapshot its exact source allowlist.
Does not install the product, execute it, or claim host compatibility.
"""
import base64, hashlib, json, struct, sys, zipfile
from pathlib import PurePosixPath
from github_native import ROOT, REPO, api, request_bytes

def sha(data): return hashlib.sha256(data).hexdigest()
def blob(data): return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()

def verify(run):
    if not run.isdigit(): raise ValueError('Numeric run ID required')
    state=json.loads((ROOT/'artifacts/release-state.json').read_text()); p='/repos/'+REPO
    build=api('GET',p+'/actions/runs/'+run); commit=state['commit']
    assert build['name']=='WeChat Unified dylib' and build['head_sha']==commit
    assert build['status']=='completed' and build['conclusion']=='success'
    artifacts=api('GET',p+'/actions/runs/'+run+'/artifacts')['artifacts']
    found=[a for a in artifacts if not a['expired'] and a['name']=='WeChatUnified-arm64-iOS16.6-'+commit]
    assert len(found)==1; meta=found[0]
    data=request_bytes('GET',p+'/actions/artifacts/'+str(meta['id'])+'/zip')
    assert len(data)==meta['size_in_bytes'] and 'sha256:'+sha(data)==meta['digest']
    archive=ROOT/('artifacts/WeChatUnified-'+run+'.zip'); archive.write_bytes(data)
    out=ROOT/('artifacts/run-'+run); out.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for info in z.infolist():
            name=PurePosixPath(info.filename)
            assert not name.is_absolute() and '..' not in name.parts and ((info.external_attr>>16)&0o170000)!=0o120000
            dest=out.joinpath(*name.parts)
            if info.is_dir(): dest.mkdir(parents=True,exist_ok=True)
            else: dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(z.read(info))
    library=(out/'WeChatUnified.dylib').read_bytes()
    magic,cpu,subtype,kind=struct.unpack_from('<IIII',library)
    assert (magic,cpu,kind)==(0xfeedfacf,0x100000c,6)
    digest=sha(library); assert digest in (out/'SHA256SUMS').read_text()
    assert 'valid on disk' in (out/'signature.txt').read_text()
    ui=json.loads((out/'uikit-verified-tests.json').read_text())
    assert len(ui)==4 and all(row[1]=='Success' for row in ui)
    assert api('GET',p+'/git/ref/heads/'+state['branch'])['object']['sha']==commit
    treeid=api('GET',p+'/git/commits/'+commit)['tree']['sha']
    tree=api('GET',p+'/git/trees/'+treeid+'?recursive=1'); assert not tree.get('truncated')
    remote={e['path']:e['sha'] for e in tree['tree'] if e['type']=='blob'}
    source=ROOT/('artifacts/WeChatUnified-current-source-'+commit[:7]+'.zip'); rows=[]; note_differences=[]
    with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED) as z:
        for name in state['paths']:
            local=ROOT/('workflow/wechat-unified.yml' if name.startswith('.github/') else name.removeprefix('wechat-unified/'))
            content=local.read_bytes()
            if blob(content)!=remote[name]:
                assert name in ('wechat-unified/STATUS.md','wechat-unified/BUILD-RESULT.md'),name
                raw=api('GET',p+'/git/blobs/'+remote[name]); assert raw['encoding']=='base64'
                content=base64.b64decode(raw['content']); note_differences.append(name)
            assert blob(content)==remote[name],name
            rows.append({'path':name,'sha256':sha(content),'bytes':len(content)})
            z.writestr(name,content)
        z.writestr('SOURCE-MANIFEST.json',json.dumps({'commit':commit,'run':run,'scope':'current source checkpoint, NOT complete retained-feature delivery or real WeChat validation','files':rows},ensure_ascii=False,indent=2))
    result={'run':run,'commit':commit,'artifact':meta['id'],'zip_bytes':len(data),'zip_sha256':sha(data),'dylib_bytes':len(library),'dylib_sha256':digest,'source_files':len(rows),'source_zip':source.name,'source_sha256':sha(source.read_bytes()),'local_result_notes_differ':note_differences,'UIKit':ui,'real_host_tested':False}
    (ROOT/('artifacts/verification-'+run+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__': verify(sys.argv[1])
