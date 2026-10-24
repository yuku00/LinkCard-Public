# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic tests of the public result schema, not native UI execution."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('public_build_result', Path(__file__).resolve().parents[1] / 'Tools/public_build_result.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublicBuildResultTests(unittest.TestCase):
    def report(self, unit=None, full=None, environment=None):
        with tempfile.TemporaryDirectory() as folder:
            logs = Path(folder)
            for name, value in [('mist-uikit-result.json', unit), ('full-app-ui-result.json', full)]:
                if value is not None:
                    (logs / name).write_text(json.dumps(value))
            return module.make_report(logs, environment or {})

    def success(self, **updates):
        value = {'status': 'passed', 'scope': 'fullApp', 'test_counts': dict(module.EXPECTED)}
        value.update(updates)
        return value

    def environment(self):
        return {key: 'success' for key in ('PUBLIC_VALIDATION_OUTCOME', 'PUBLIC_BUILD_OUTCOME', 'PUBLIC_GATE_OUTCOME')}

    def test_compile_classifier_never_exports_diagnostic_text(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'build.log'
            cases = {
                'SYNTHETIC_PRIVATE_MARKER': 'unknown',
                'SYNTHETIC_PRIVATE_MARKER error: unable to type-check this expression in reasonable time': 'swift-typecheck-limit',
                'error: generic parameter T could not be inferred': 'swift-generic-inference',
                'error: API is only available in iOS 17': 'swift-api-availability',
                'error: cannot find SYNTHETIC_PRIVATE_MARKER': 'swift-missing-symbol',
                'error: cannot convert SYNTHETIC_PRIVATE_MARKER': 'swift-type-mismatch',
                '** BUILD FAILED **': 'xcode-build-failed',
                '** BUILD SUCCEEDED **': 'xcode-build-succeeded',
            }
            for text, expected in cases.items():
                path.write_text(text)
                self.assertEqual(module.compile_failure_kind(path), expected)
            link = Path(folder) / 'link.log'
            link.symlink_to(path)
            self.assertEqual(module.compile_failure_kind(link), 'unknown')

    def test_missing_results_cannot_validate(self):
        self.assertEqual(self.report()['native_validation'], 'not-validated')

    def test_arbitrary_values_are_not_exported(self):
        marker = 'SYNTHETIC_UNTRUSTED_MARKER'
        result = self.report({'status': marker, 'reason': marker},
                             {'status': [marker], 'scope': marker, 'udid': marker,
                              'test_counts': {key: marker for key in module.COUNTS}},
                             {'PUBLIC_GATE_OUTCOME': marker})
        self.assertNotIn(marker, json.dumps(result))
        self.assertEqual(result['native_validation'], 'not-validated')

    def test_exact_pass_requires_all_stages(self):
        result = self.report({'status': 'passed'}, self.success(), self.environment())
        self.assertEqual(result['native_validation'], 'passed')
        self.assertEqual(result['artifact_upload'], 'not-attested')
        self.assertEqual(self.report({'status': 'passed'}, self.success())['native_validation'], 'not-validated')

    def test_sidebar_skips_and_boolean_counts_fail(self):
        for full in [self.success(scope='sidebar-diagnostic'),
                     self.success(test_counts=dict(module.EXPECTED, skippedTests=1)),
                     self.success(test_counts=dict(module.EXPECTED, failedTests=False))]:
            self.assertEqual(self.report({'status': 'passed'}, full, self.environment())['native_validation'], 'not-validated')

    def test_malformed_and_oversized_files_are_ignored(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'result.json'
            for text in ['{', '[]', 'x' * 65537]:
                path.write_text(text)
                self.assertEqual(module.read_result(path), {})

    def test_symlinks_are_ignored(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'target.json'
            target.write_text('{"status":"passed"}')
            link = Path(folder) / 'link.json'
            link.symlink_to(target)
            self.assertEqual(module.read_result(link), {})


if __name__ == '__main__':
    unittest.main()
