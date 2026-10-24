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
                'SYNTHETIC_PRIVATE_MARKER error: unable to type-check this expression in reasonable time': 'unknown',
                'error: generic parameter T could not be inferred': 'compiler-error',
                'error: API is only available in iOS 17': 'compiler-error',
                'error: cannot find SYNTHETIC_PRIVATE_MARKER': 'compiler-error',
                'error: cannot convert SYNTHETIC_PRIVATE_MARKER': 'compiler-error',
                '** BUILD FAILED **': 'unknown',
                '** BUILD SUCCEEDED **': 'unknown',
            }
            for text, expected in cases.items():
                path.write_text(text)
                self.assertEqual(module.compile_failure_kind(path), expected)
            link = Path(folder) / 'link.log'
            link.symlink_to(path)
            self.assertEqual(module.compile_failure_kind(link), 'unknown')

    def test_warning_and_cross_line_regression(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'build.log'
            path.write_text('warning: unable to type-check this expression in reasonable time\n** BUILD SUCCEEDED **\n')
            self.assertEqual(module.compile_failure_kind(path), 'unknown')

    def test_unrelated_warning_cannot_classify_error(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'build.log'
            path.write_text('xcodebuild: error: invalid scheme\nwarning: cannot convert sample\n')
            self.assertEqual(module.compile_failure_kind(path), 'xcodebuild-error')

    def test_structured_errors_only_and_status_independent(self):
        def item(message, severity='error', filename='LinkCard/ContentView.swift'):
            return {'file': filename, 'line': 1, 'column': None, 'severity': severity, 'message': message}
        cases = [
            ([item('generic parameter T'), item('could not be inferred', 'warning')], 'swift-error'),
            ([item('cannot convert value', 'warning')], 'unknown'),
            ([item('generic parameter T could not be inferred')], 'swift-generic-inference'),
            ([item('new SDK diagnostic')], 'swift-error'),
            ([item('cannot convert value')], 'swift-type-mismatch'),
            ([item('cannot find type')], 'swift-missing-symbol'),
            ([item('API is only available in iOS 17')], 'swift-api-availability'),
            ([item('unable to type-check this expression in reasonable time')], 'swift-typecheck-limit'),
            ([item('failure', filename='[sdk]')], 'sdk-error'),
            ([item('failure', filename='[tool:ld]')], 'linker-error'),
            ([item('failure', filename='[tool:clang]')], 'clang-error'),
            ([item('failure', filename='LinkCard.xcodeproj')], 'project-error'),
        ]
        for items, expected in cases:
            self.assertEqual(module.compile_failure_kind(diagnostics={'items': items}), expected)
        # The authoritative workflow outcome remains success even with diagnostics.
        self.assertEqual(self.report(environment=self.environment())['stages']['build'], 'success')
        self.assertEqual(self.report(environment={'PUBLIC_BUILD_OUTCOME': 'failure'})['stages']['build'], 'failure')

    def test_script_keeps_workflow_status_separate_from_messages(self):
        import subprocess
        import sys
        script = Path(__file__).resolve().parents[1] / 'Tools/public_build_result.py'
        cases = [('warning: unable to type-check this expression in reasonable time\n** BUILD SUCCEEDED **', 'success', 'unknown'),
                 ('xcodebuild: error: invalid scheme\nwarning: cannot convert sample', 'failure', 'xcodebuild-error'),
                 ('** BUILD FAILED **', 'success', 'unknown')]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            logs = root / 'build/logs'
            logs.mkdir(parents=True)
            for text, outcome, kind in cases:
                (logs / 'build-package.log').write_text(text + '\n')
                subprocess.run([sys.executable, str(script)], cwd=root, check=True,
                               capture_output=True, env={'PUBLIC_BUILD_OUTCOME': outcome, 'PYTHONDONTWRITEBYTECODE': '1'})
                report = json.loads((root / 'build/public/result.json').read_text())
                self.assertEqual(report['stages']['build'], outcome)
                self.assertEqual(report['compile_diagnostic'], kind)
                diagnostics = json.loads((root / 'build/public/compiler-diagnostics.json').read_text())
                self.assertEqual(diagnostics['stages']['unit']['read_status'], 'missing')
                self.assertEqual(diagnostics['stages']['fullApp']['read_status'], 'missing')

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
