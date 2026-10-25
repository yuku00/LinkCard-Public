"""Synthetic runner contract checks; never a replacement for native XCTest."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native_runner', ROOT / 'Tools/native_test_runner.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class NativeRunnerTests(unittest.TestCase):
    def test_public_methods_are_exact_source_identifiers(self):
        unit = m.public_methods(ROOT, 'unit')
        full = m.public_methods(ROOT, 'fullApp')
        self.assertEqual(len(full), 4)
        self.assertEqual(len(unit), 44)
        self.assertEqual(len([s for s in unit if s.startswith('PN532IdentifyTests/')]), 6)

    def test_runner_progress_cannot_leak_values(self):
        marker = '/private/path UUID SECRET unexpected-method'
        raw = dict.fromkeys(['phase', 'timeout_at', 'simulator_boot_phase', 'runner_process_state',
                             'cleanup', 'last_public_test', 'elapsed_seconds', 'tests_started',
                             'tests_completed', 'simulator_startup_seconds'], marker)
        raw['unknown'] = marker
        result = m.safe_progress(raw, set())
        self.assertNotIn(marker, json.dumps(result))
        for v in [True, -1, float('nan'), float('inf'), 100001, {}, []]:
            self.assertIsNone(m.safe_progress({'tests_started': v}, set())['tests_started'])
        for v in [True, -1, float('nan'), float('inf'), 3601, {}, []]:
            self.assertIsNone(m.safe_progress({'elapsed_seconds': v}, set())['elapsed_seconds'])

    def test_progress_observes_real_xctest_formats_not_arbitrary_text(self):
        ident = 'PN532IdentifyTests/testEveryNotificationSplitAndCoalescedACK'
        p = m.Progress({ident})
        p.consume("Test Case '-[LinkCardTests.PN532IdentifyTests testEveryNotificationSplitAndCoalescedACK]' started.")
        self.assertEqual(p.data['tests_started'], 1)
        self.assertEqual(p.data['tests_completed'], 0)
        p.consume("Test Case '-[LinkCardTests.PN532IdentifyTests testEveryNotificationSplitAndCoalescedACK]' passed (0.1 seconds).")
        p.consume("Test case 'PN532IdentifyTests.testEveryNotificationSplitAndCoalescedACK()' passed on 'PRIVATE UUID'")
        p.consume("Test Case '-[UnknownTests testPrivate]' started.")
        self.assertEqual(p.data['tests_completed'], 1)
        self.assertEqual(p.data['last_public_test'], ident)
        self.assertNotIn('PRIVATE', json.dumps(p.data))

    def test_boot_requires_native_launch_bootstatus_and_readiness(self):
        old = Path.cwd()
        with tempfile.TemporaryDirectory() as folder:
            try:
                os.chdir(folder)
                runner = m.NativeRunner('unit', 420, 'unit.json')
                calls = []
                udid = '12345678-1234-1234-1234-123456789012'
                runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-18-6'
                def command(args, *a, **kw):
                    calls.append(args)
                    if args[1:4] == ['simctl', 'list', '--json']:
                        return json.dumps({'devices': {runtime: [{'name': 'iPhone 16', 'isAvailable': True, 'deviceTypeIdentifier': 'type'}]}}).encode()
                    if args[1:3] == ['simctl', 'create']:
                        return udid.encode()
                    if args[1:4] == ['simctl', 'list', 'devices']:
                        return json.dumps({'devices': {runtime: [{'udid': udid, 'state': 'Booted', 'isAvailable': True}]}}).encode()
                    return b''
                runner.command = command
                runner.boot()
                self.assertFalse(any(c[0] == 'open' for c in calls))
                self.assertIn(['xcrun', 'simctl', 'boot', udid], calls)
                self.assertIn(['xcrun', 'simctl', 'bootstatus', udid, '-b'], calls)
                self.assertIn(['xcrun', 'simctl', 'spawn', udid, 'launchctl', 'print', 'system'], calls)
                self.assertEqual(runner.result['runner']['simulator_boot_phase'], 'ready')
                self.assertNotIn(udid, runner.path.read_text())
            finally:
                os.chdir(old)

    def test_timeout_phase_is_preserved_and_cleanup_is_mandatory(self):
        old = Path.cwd()
        with tempfile.TemporaryDirectory() as folder:
            try:
                os.chdir(folder)
                runner = m.NativeRunner('unit', 420, 'unit.json')
                def boot():
                    runner.progress.data['phase'] = 'bootstatus'
                    raise m.BudgetExceeded()
                runner.boot = boot
                with patch('builtins.print'):
                    result = runner.run([], 'none', 'test.log', 'derived')
                self.assertEqual(result['status'], 'timeout')
                self.assertEqual(result['runner']['timeout_at'], 'bootstatus')
                self.assertEqual(result['runner']['cleanup'], 'complete')
            finally:
                os.chdir(old)

    def test_bootstatus_phrases_return_only_fixed_enums(self):
        for text, expected in [
            ('PRIVATE UUID /path', 'waiting-boot'),
            ('Waiting on BackBoard /PRIVATE', 'waiting-backboard'),
            ('Waiting on Data Migration PRIVATE', 'waiting-data-migration'),
            ('Waiting on Data Migration\nWaiting on System App PRIVATE', 'waiting-system-app'),
        ]:
            self.assertEqual(m.boot_wait_phase(text.encode()), expected)
            self.assertIn(expected, m.BOOT_PHASES)

    def test_process_is_reaped_on_timeout(self):
        p = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.assertIn(m.reap_group(p), {'terminated', 'killed'})
        self.assertIsNotNone(p.poll())

    def test_budgets_and_resource_isolation(self):
        unit = (ROOT / 'Tools/test_mist_uikit.py').read_text()
        full = (ROOT / 'Tools/test_full_app_ui.py').read_text()
        self.assertIn("NativeRunner('unit', 420", unit)
        self.assertIn("NativeRunner('fullApp', 1200", full)
        self.assertIn('build/UnitDerivedData', unit)
        self.assertIn('build/FullAppDerivedData', full)
        self.assertIn("'-only-testing:LinkCardTests/PN532IdentifyTests'", unit)
        self.assertIn("'-only-testing:LinkCardUITests'", full)
        workflow = (ROOT / '.github/workflows/build-ipa.yml').read_text()
        for forbidden in ['build/logs/', '*.xcresult', '*.png']:
            self.assertNotIn(forbidden, workflow.split('name: Upload schema-limited results only')[1])


if __name__ == '__main__':
    unittest.main()
