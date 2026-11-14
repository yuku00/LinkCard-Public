#!/usr/bin/env python3
"""Generate a deterministic, versioned manifest from literal source call arguments."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Sources/WUCandidateManifest.inc'
# Strip comments while preserving line positions and quoted literals.
TOKEN = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|@?"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
def uncomment(s):
    return TOKEN.sub(lambda m: re.sub(r'[^\n]', ' ', m.group()) if m.group().startswith(('/',)) else m.group(), s)
LIT = r'@"([A-Za-z_][A-Za-z_0-9:]*)"'
HOOK = re.compile(r'\bWUHook\s*\(\s*'+LIT+r'\s*,\s*'+LIT+r'\s*,\s*(YES|NO)\s*,')
CALL = re.compile(r'\b(NSClassFromString|NSSelectorFromString)\s*\(\s*'+LIT+r'\s*\)')
DIRECT = re.compile(r'\bclass_get(Instance|Class)Method\s*\(\s*NSClassFromString\s*\(\s*'+LIT+r'\s*\)\s*,\s*NSSelectorFromString\s*\(\s*'+LIT+r'\s*\)\s*\)')
def generate(root):
    entries = {}
    def add(cls, sel, kind, source):
        entries.setdefault((cls, sel, kind), set()).add(source)
    sources = root / 'Sources'
    for path in sorted(sources.rglob('*')):
        if path.suffix not in ('.m', '.mm', '.h', '.c', '.inc') or path.name in ('WUCandidateManifest.inc', 'WUDiagnostics.m'):
            continue
        text = uncomment(path.read_text(encoding='utf-8'))
        def loc(match, label):
            return f'{path.relative_to(root).as_posix()}:{text.count(chr(10), 0, match.start()) + 1} {label}'
        for m in HOOK.finditer(text):
            add(m[1], m[2], '+' if m[3] == 'YES' else '-', loc(m, 'WUHook'))
        for m in DIRECT.finditer(text):
            add(m[2], m[3], '-' if m[1] == 'Instance' else '+', loc(m, '直接关联'))
        for m in CALL.finditer(text):
            add(m[2] if m[1] == 'NSClassFromString' else '', m[2] if m[1] == 'NSSelectorFromString' else '', '?', loc(m, m[1]))
    # Account() checks the returned contact but does not establish its concrete class.
    for cls, sel, kind in [('MMServiceCenter','defaultCenter','+'), ('MMServiceCenter','getService:','-'), ('CContactMgr','getSelfContact','-'), ('','m_nsUsrName','?')]:
        add(cls, sel, kind, 'Sources/Messages.m Account（手工证据；返回对象的具体类未假定）')
    # Explicitly documented gap candidates, not a claim that these ABIs or behaviors work.
    gaps = [
        ('EmoticonPickViewController', ['m_image','setM_image:','Confirm','Cancel','AddEmoticonFinishedWithWrap:IsSuccessed:']),
        ('AddEmoticonWrap', ['source','setSource:','fileType','setFileType:','fileSize','setFileSize:','emojiInfoObj','setEmojiInfoObj:','uploadInfoObj','setUploadInfoObj:','initWithMessageWrap:AndSource:']),
        ('EmojiInfoObj', ['md5','setMd5:']),
        ('EmoticonUploadInfoObj', ['uploadImgMd5','setUploadImgMd5:','tempFilePath','setTempFilePath:','uploadFilePath','setUploadFilePath:','dataOfEmoticon']),
        ('EmoticonCustomManageAddLogic', ['startAddEmoticonWithWrap:','cancelAddEmoticonWithWrap:','onAddBackupEmoticonOK:addEmoticonWrap:','onAddBackupEmoticonFailed:reason:remoteErrMsg:']),
        ('CEmoticonMgr', ['AddCustomEmoticonWithData:addEmoticonWrap:isSilently:']),
    ]
    for cls, selectors in gaps:
        for selector in selectors:
            add(cls, selector, '-', 'IMAGE-TO-EMOTICON-GAP.md 2026-11-02 定向补充；第三方8.0.55声明，目标版未验证')
    for selector in ['getRawHDThumbImagePath','getHDThumbImagePath','getMsgHdOrMiddleImgData:','getPathOfMsgImg:', 'onEmoticonUploadSuccessWithEmoji:uploadInfo:', 'onEmoticonUploadFailWithUploadInfo:reason:realMd5:']:
        add('', selector, '?', 'IMAGE-TO-EMOTICON-GAP.md 新确认边界；类或ABI待定，旧插件线索非原图证明')
    for selector in ['likeFlag','likeUsers','setLikeUsers:','setLikeCount:']:
        add('', selector, '?', 'FAKE-LIKES-GAP.md 本轮新增证据；旧库观察，目标模型类型及生命周期待定')
    add('WCDataItem', 'likeFlag', '-', 'FAKE-LIKES-GAP.md 精确剩余契约；暂缓功能仅只读诊断')
    for cls, selectors in [('MMNewSessionMgr',['GetUserNamesOnSessionList','GetSessionByUserName:']), ('CContactMgr',['getAllContactUserName'])]:
        for selector in selectors:
            add(cls, selector, '-', 'REMAINING.md 第11项；第三方8.0.55声明，目标版兼容性未实测')
    for cls, selectors in [('CMessageMgr',['sendMsg:toContactUsrName:','AddMsg:MsgWrap:','GetMsg:LocalID:']), ('CContactMgr',['getContactByName:']), ('ForwardMessageLogicController',['ForwardMsg:ToContact:'])]:
        for selector in selectors:
            add(cls, selector, '-', 'reverse-repository-send.md 已闭合核心发送链；旧插件调用观察，目标ABI待验证')
    for cls, selector in [('CMessageMgr','AddLocalMsg:MsgWrap:'), ('AudioSender','ResendVoiceMsg:MsgWrap:')]:
        add(cls, selector, '-', 'reverse-voice-state.md 第2节及 Sources/VoiceSendLogic.m；旧插件调用观察，目标ABI待验证')
    for cls, selector, kind in [('MessageRevokeMgr','onRevokeMsg:','-'), ('','RevokeMsg:MsgWrap:Counter:revokeTicket:viewController:','?'), ('','RevokeMsg:MsgWrap:Counter:','?')]:
        add(cls, selector, kind, 'reverse-round2-message.md 撤回注册与调用证据；未证明目标版兼容')
    add('WCFacade','filterTimelineItem:','-', 'reverse-round2-moments.md 第150行注册证据；未证明目标版兼容')
    return {'schema': 1, 'generator': 'literal-candidates-v1', 'candidates': [
        {'class': c, 'selector': s, 'kind': k, 'sources': sorted(v)}
        for (c, s, k), v in sorted(entries.items())]}

def render(manifest):
    raw = json.dumps(manifest, ensure_ascii=True, separators=(',', ':'))
    # Adjacent C literals prevent overlong source lines.
    chunks = [raw[i:i+100] for i in range(0, len(raw), 100)]
    return '/* Generated by tools/generate_candidates.py; do not edit. */\nstatic const char WUCandidateJSON[] =\n' + '\n'.join(json.dumps(c) for c in chunks) + ';\n'

if __name__ == '__main__':
    content = render(generate(ROOT))
    if sys.argv[1:] == ['--check']:
        if not OUT.exists() or OUT.read_text() != content:
            sys.exit('candidate manifest stale; run python3 tools/generate_candidates.py')
    else:
        OUT.write_text(content)
