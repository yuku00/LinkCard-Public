#!/usr/bin/env python3
"""macOS-only synthetic production-C/Objective-C cross-process storage gate; no XCTest."""
import hashlib, os, pathlib, platform, subprocess, tempfile
P=pathlib.Path(__file__).resolve().parents[1]
os.chdir(P)
assert platform.system()=='Darwin', 'BLOCKED: Apple macOS required'
assert os.geteuid()!=0, 'BLOCKED: permission tests require a non-root user'
out=P/'build/migration'; out.mkdir(parents=True,exist_ok=True)
subprocess.run(['python3','tools/build_codecs.py','macosx'],check=True)
common=['xcrun','--sdk','macosx','clang','-fobjc-arc','-fobjc-arc-exceptions','-fblocks','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-unused-function','-I','Sources','tests/storage_live_process.m']
tail=['Sources/VoiceAudio.m','Sources/VoiceLogic.m','Sources/VoiceSendLogic.m','Sources/MessageConstruction.m','Sources/RepositoryLogic.m','Sources/DraftMediaLogic.m','build/codec-macosx/libWUOffline.a','-framework','Foundation','-framework','AudioToolbox']
for name,voice in [('release','tests/fixtures/voice_c73_release.m'),('current','Sources/VoicePackLogic.m')]:
    subprocess.run(common+[voice]+tail+['-o',str(out/('storage-live-'+name))],check=True)
print('BUILD release c73 + current production logic OK',flush=True)
def run(binary,mode,path,expected=0,contains=None):
    r=subprocess.run([str(out/('storage-live-'+binary)),mode,str(path)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    print(binary,mode,'exit',r.returncode,r.stdout.strip(),flush=True)
    assert r.returncode==expected and (contains is None or contains in r.stdout), (mode,r.returncode,r.stdout)
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory(prefix='wu-release-synthetic-') as td:
    docs=pathlib.Path(td); old=docs/'WeChatUnifiedStorage'; old.mkdir(); (old/'preserve').write_bytes(b'release legacy target')
    for mode in ('create','write1','write2','read2'): run('release',mode,docs)
    assert (old/'preserve').read_bytes()==b'release legacy target'
    print('RELEASE normal create/write/restart/write/restart OK',flush=True)
with tempfile.TemporaryDirectory(prefix='wu-synthetic-') as td:
    docs=pathlib.Path(td); old=docs/'WeChatUnifiedStorage'; old.mkdir(); (old/'preserve').write_bytes(b'unchanged legacy target')
    run('current','create',docs); root=docs/'WeChatUnifiedStorage-New-12345678-ABCD-4ABC-8ABC-123456789ABC'; main=root/'WeChatUnified'
    run('current','write1',docs); pointer=docs/'.WUStorage-selection-v1'; receipt=root/'.wu-storage-v1'; index=main/'VoicePacks/61/index.plist'; repo=main/'Repository/61.plist'
    saved={p:digest(p) for p in (old/'preserve',pointer,receipt,index,repo,main/'config.json')}
    run('current','write2',docs); run('current','read2',docs)
    assert all(digest(p)==saved[p] for p in (old/'preserve',pointer,receipt,main/'config.json'))
    after={p:digest(p) for p in (index,repo)}
    # Missing selection is explicitly absent; never auto-select another library.
    pointer.rename(docs/'pointer.saved'); run('current','absent',docs); (docs/'pointer.saved').rename(pointer)
    # Bad selection and receipt must block and cannot touch the real data.
    for p in (pointer,receipt,main/'config.json'):
        original=p.read_bytes(); p.write_bytes(b'bad')
        if p.name=='config.json': p.unlink()  # selection only checks ordinary-file existence
        run('current','invalid',docs)
        p.write_bytes(original)
        assert all(digest(q)==after[q] for q in after)
    run('current','read2',docs)
    # Loss of import source never overwrites an existing index.
    src=docs/'synthetic.amr'; src.rename(docs/'synthetic.saved'); run('current','source-missing',docs); (docs/'synthetic.saved').rename(src)
    assert all(digest(q)==after[q] for q in after)
    # Real released bug: existing account directory but missing index is mistaken for empty.
    index.rename(index.with_name('preserved-index'))
    run('release','missing',docs,expected=1,contains='[store load:&error]==nil')
    run('current','missing',docs)
    assert not index.exists() and digest(index.with_name('preserved-index'))==after[index]
    index.with_name('preserved-index').rename(index)
    # Empty/corrupt and unreadable index: no replacement. chmod is POSIX only, not iOS Data Protection.
    good=index.read_bytes()
    index.write_bytes(b''); run('current','bad',docs); assert index.read_bytes()==b''
    index.write_bytes(good); index.chmod(0)
    try:
        assert not os.access(index,os.R_OK), 'BLOCKED: cannot simulate POSIX read denial'
        run('current','denied',docs)
    finally: index.chmod(0o600)
    assert all(digest(q)==after[q] for q in after)
    # Existing repository read failures must not be interpreted as an empty account.
    repo_good=repo.read_bytes(); repo.write_bytes(b''); run('current','repo-bad',docs); assert repo.read_bytes()==b''
    repo.write_bytes(repo_good); repo.chmod(0)
    try:
        assert not os.access(repo,os.R_OK), 'BLOCKED: cannot simulate repository read denial'
        run('current','repo-denied',docs)
    finally: repo.chmod(0o600)
    assert all(digest(q)==after[q] for q in after)
    run('current','read2',docs)
    assert (old/'preserve').read_bytes()==b'unchanged legacy target'
print('PASS production cross-process synthetic flow; permission denial is POSIX, not iOS Data Protection',flush=True)
