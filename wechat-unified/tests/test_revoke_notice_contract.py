from pathlib import Path
p = Path(__file__).resolve().parents[1]
s = (p / 'Sources/WURevokeNotice.m').read_text()
assert 'AddLocalMsg:MsgWrap:fixTime:NewMsgArriveNotify:' in s
assert 'session,wrap,YES,NO' in s
assert '@"对方撤回了一条消息"' in s
assert 'SendMsg' not in s and 'm_nsContent"' not in s
assert '[seen addObject:key]' in s and s.index('[seen addObject:key]') < s.index('session,wrap,YES,NO')
assert 'seen.count>=4096' in s and '!valid()' in s
print('revoke notice source contract OK (not a runtime test)')
