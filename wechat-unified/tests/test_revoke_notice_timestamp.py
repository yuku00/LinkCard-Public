from pathlib import Path

root = Path(__file__).resolve().parents[1]
messages = (root / 'Sources/Messages.m').read_text()
notice = (root / 'Sources/WURevokeNotice.m').read_text()
# The sync notice's time, not the much older original message's time, orders the local tip.
assert 'Num(notice,@"m_uiCreateTime")' in messages
assert 'setM_uiCreateTime:",createTime)' in notice
assert 'setM_uiCreateTime:",createTime+1)' not in notice
print('revoke notice timestamp wiring: OK (static)')
