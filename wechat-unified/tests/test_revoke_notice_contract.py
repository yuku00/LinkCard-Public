from pathlib import Path
p = Path(__file__).resolve().parents[1]
s = (p / 'Sources/WURevokeNotice.m').read_text()
assert 'AddLocalMsg:MsgWrap:fixTime:NewMsgArriveNotify:' in s
assert 'session,wrap,YES,NO' in s
assert '@"对方撤回了一条消息"' in s
assert 'SendMsg' not in s and 'm_nsContent"' not in s
assert '[seen addObject:key]' in s and s.index('[seen addObject:key]') < s.index('session,wrap,YES,NO')
assert 'seen.count>=4096' in s and '!valid()' in s
assert 'objc_getClass("NSProxy")' in s and 'Signature(instance?cls:host,sel)' in s
assert '[manager methodSignatureForSelector:sel]' in s and 'class_getInstanceMethod(cls,sel)' in s
assert 'antiRevokeNotice' in s
core = (p / 'Sources/Core.m').read_text()
settings = (p / 'Sources/Settings.m').read_text()
assert core.count('@"antiRevokeNotice"') >= 2 and '@"antiRevokeNotice"' in settings
assert '[key isEqual:@"antiRevokeNotice"]' in settings
print('revoke notice source contract OK (not a runtime test)')
