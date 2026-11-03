from pathlib import Path
r = Path(__file__).resolve().parents[1]
s = (r/'Sources/BusinessUI.swift').read_text()
confirm = s.split('@objc func confirmExport()', 1)[1].split('func prepareExport', 1)[0]
assert '[true, false]' in confirm and '导出 Obsidian Markdown' in confirm and '备份 WebClip 原文件' in confirm
assert 'hiddenSelectionCount' in confirm
prep = s.split('func prepareExport(', 1)[1].split('private func exportSelected(', 1)[0]
assert 'clips.filter { selected.contains($0.id) }' in prep
assert 'notes.filter { selected.contains($0.id.uuidString) }' in prep
assert prep.count('targets.count == selected.count') == 2
assert 'Data(note.text.utf8)' in prep and 'repository.backup(ids: Array(selected))' in prep
assert 'WebClips.webclipbackup' in prep and 'WebClips.md' in prep
cancel = s.split('func documentPickerWasCancelled', 1)[1].split('func documentPicker(', 1)[0]
assert 'staging = nil' in cancel and 'selected' not in cancel and 'notes =' not in cancel and 'clips =' not in cancel
print('PASS selection scope, hidden counts, backups, verbatim notes and cancel source preservation')
