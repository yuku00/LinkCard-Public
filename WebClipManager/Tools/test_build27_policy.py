from pathlib import Path
r = Path(__file__).resolve().parents[1]
s = (r/'Sources/BusinessUI.swift').read_text()
clear = s.split('@objc func clearMemory()',1)[1].split('@objc func confirmRead()',1)[0]
assert 'staging = nil' not in clear and 'guard !busy' in clear
export = s.split('private func exportSelected(markdown:',1)[1].split('func documentPickerWasCancelled',1)[0]
assert 'guard !busy, staging == nil' in export and 'exportPicker = picker' in export
cancel = s.split('func documentPickerWasCancelled',1)[1].split('func documentPicker(',1)[0]
assert 'controller === exportPicker' in cancel and 'staging = nil' in cancel
complete = s.split('func documentPicker(_ controller:',1)[1]
assert 'guard controller === exportPicker' in complete and 'staging = nil' in complete
assert '请在所选位置核对文件' in complete
stage = (r/'Sources/ExportStaging.swift').read_text()
assert 'temporaryDirectory' not in stage and 'linkat(dirFD, tmp, dirFD, name, 0)' in stage
assert 'fstatat(dirFD, name' in stage and 'unlinkat(dirFD, name, 0)' in stage
print('PASS export picker lifecycle and no-replace source checks')
