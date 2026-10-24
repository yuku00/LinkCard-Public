# SPDX-License-Identifier: GPL-3.0-or-later
"""Source-contract regression checks, not Swift execution or a real-card test."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'LinkCard/NFCService.swift').read_text()

class NFCReadOnlyContractTests(unittest.TestCase):
    def test_custom_command_is_non_addressed(self):
        self.assertIn('tag.customCommand(requestFlags: .highDataRate,', SOURCE)
        self.assertNotIn('addressed: Bool = true', SOURCE)

    def test_identity_is_published_before_optional_mailbox_probe(self):
        method = SOURCE.split('private func inspectMailbox', 1)[1].split('private func command', 1)[0]
        self.assertLess(method.index('self.identity = partial'), method.index('readStatus'))
        self.assertIn('self.identity = found', SOURCE)
        self.assertNotIn('if clearIdentity { self.identity = nil }', SOURCE)

    def test_missing_memory_does_not_reject_family(self):
        self.assertIn('case 0x26: model = "ST25DV16K/64K', SOURCE)
        self.assertIn('ICRef=%d (0x%02X)', SOURCE)
        self.assertIn('容量字段未返回（不是读取失败）', SOURCE)

    def test_errors_have_underlying_diagnostics(self):
        self.assertIn('ns.domain', SOURCE)
        self.assertIn('ns.code', SOURCE)
        self.assertIn('NSUnderlyingErrorKey', SOURCE)
        self.assertIn('NFCISO15693TagResponseErrorKey', SOURCE)

    def test_send_preflights_in_same_session(self):
        ui = (ROOT / 'LinkCard/ContentView.swift').read_text()
        self.assertIn('nfc.send(frame: frame)', ui)
        self.assertNotIn('nfc.identity?.mailboxReady != true', ui)
        self.assertIn('func send(frame: Data) { begin(frame: frame) }', SOURCE)
        method = SOURCE.split('private func inspectMailbox', 1)[1].split('private func command', 1)[0]
        self.assertLess(method.index('guard model != nil'), method.index('readStatus'))
        self.assertLess(method.index('guard mb.enabled'), method.index('self.approvedUID = found.uid'))
        self.assertIn('!mb.hostPending, !mb.rfPending, !mb.missed', method)
        send = SOURCE.split('private func sendNext()', 1)[1].split('private func awaitConsumed', 1)[0]
        self.assertLess(send.index('approvedUID == tag.identifier'), send.index('self.command(0xAA'))
        self.assertIn('self.approvedUID = nil', SOURCE)

    def test_templates_are_local_static_and_ios16(self):
        ui = (ROOT / 'LinkCard/ContentView.swift').read_text()
        renderer = (ROOT / 'LinkCard/CardRenderer.swift').read_text()
        self.assertIn('calendar.timeZone = .current', renderer)
        self.assertIn('Calendar(identifier: .gregorian)', renderer)
        self.assertIn('calendar.range(of: .day, in: .month', renderer)
        self.assertIn('只有每次手机发送才会更新', ui)
        self.assertIn('case 5: image = CardRenderer.checklist(tasks)', ui)
        self.assertNotIn('Timer', renderer)
        for api in ['ContentUnavailableView', '.symbolEffect', '.sensoryFeedback', '.snappy', '.containerRelativeFrame']:
            self.assertNotIn(api, ui)
        self.assertIn('新设备检测', ui)
        self.assertIn('nfc.identify()', ui)

    def test_readonly_path_has_no_write_command(self):
        methods = SOURCE.split('private func readIdentity',1)[1].split('private func command',1)[0]
        for forbidden in ['0xAA', '0xAE', 'sendNext()']:
            # sendNext is allowed ONLY in the explicit nonempty packets branch.
            if forbidden != 'sendNext()': self.assertNotIn(forbidden, methods)
        self.assertIn('if self.packets.isEmpty', methods)
        self.assertIn('self.sendNext()', methods)

if __name__ == '__main__': unittest.main()
