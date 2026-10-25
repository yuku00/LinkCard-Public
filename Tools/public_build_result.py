#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Export bounded results plus separately allowlisted compiler diagnostics.
This report does not replace Tools/require_ui_gates.py or authorize IPA upload.
"""
import json
import os
from pathlib import Path

STATUSES = {'passed', 'failed', 'timeout', 'not-run'}
OUTCOMES = {'success', 'failure', 'cancelled', 'skipped'}
COUNTS = ('passedTests', 'failedTests', 'skippedTests', 'totalTestCount')
EXPECTED = dict(zip(COUNTS, (4, 0, 0, 4)))


def read_result(path):
    try:
        if path.is_symlink() or path.stat().st_size > 65536:
            return {}
        obj = json.loads(path.read_text())
        return obj if type(obj) is dict else {}
    except (OSError, ValueError, UnicodeError):
        return {}


def enum(value, allowed, default):
    return value if type(value) is str and value in allowed else default


def make_report(logs, environment):
    try:
        from native_test_runner import safe_progress, public_methods
    except ModuleNotFoundError:
        from Tools.native_test_runner import safe_progress, public_methods
    unit = read_result(logs / 'mist-uikit-result.json')
    full = read_result(logs / 'full-app-ui-result.json')
    raw = full.get('test_counts')
    counts = {key: (raw.get(key) if type(raw.get(key)) is int
                   and 0 <= raw[key] <= 100000 else None) for key in COUNTS} if type(raw) is dict else dict.fromkeys(COUNTS)
    outcomes = {key: enum(environment.get('PUBLIC_' + key.upper() + '_OUTCOME'), OUTCOMES, 'not-run')
                for key in ('validation', 'build', 'gate')}
    unit_status = enum(unit.get('status'), STATUSES, 'not-run')
    full_status = enum(full.get('status'), STATUSES, 'not-run')
    scope = enum(full.get('scope'), {'fullApp', 'sidebar-diagnostic'}, 'unknown')
    passed = (unit_status == full_status == 'passed' and scope == 'fullApp'
              and counts == EXPECTED and all(v == 'success' for v in outcomes.values()))
    return {'schema': 1, 'version': '0.9.2', 'build': 28,
            'stages': outcomes, 'unit': {'status': unit_status,
                'runner': safe_progress(unit.get('runner'), public_methods(Path(__file__).resolve().parents[1], 'unit'))},
            'fullApp': {'status': full_status, 'scope': scope, 'test_counts': counts,
                'runner': safe_progress(full.get('runner'), public_methods(Path(__file__).resolve().parents[1], 'fullApp'))},
            'native_validation': 'passed' if passed else 'not-validated',
            'artifact_upload': 'not-attested', 'hardware_validation': 'not-performed'}


def compile_failure_kind(path=None, *, diagnostics=None):
    # Classify one structured error at a time. Never infer build status here.
    try:
        from public_compile_diagnostics import extract, public_sources
    except ModuleNotFoundError:
        from Tools.public_compile_diagnostics import extract, public_sources
    if diagnostics is None:
        if path is None:
            return 'unknown'
        root = Path.cwd()
        diagnostics = extract(path, root, public_sources(root), os.environ)
    for item in diagnostics['items']:
        if item['severity'] != 'error':
            continue
        filename, message = item['file'], item['message']
        if not filename.startswith('[') and filename.endswith('.swift'):
            checks = [('swift-typecheck-limit', ('unable to type-check this expression in reasonable time',)),
                      ('swift-generic-inference', ('generic parameter', 'could not be inferred')),
                      ('swift-api-availability', ('is only available in iOS',)),
                      ('swift-missing-symbol', ('cannot find',)),
                      ('swift-type-mismatch', ('cannot convert',))]
            for kind, phrases in checks:
                if all(phrase in message for phrase in phrases):
                    return kind
            return 'swift-error'
        if filename.endswith(('.xcodeproj', '.pbxproj', '.xcworkspace')):
            return 'project-error'
        return {'[tool:xcodebuild]': 'xcodebuild-error', '[tool:clang]': 'clang-error',
                '[tool:clang++]': 'clang-error', '[tool:ld]': 'linker-error',
                '[sdk]': 'sdk-error'}.get(filename, 'tool-error' if filename.startswith('[tool:') else 'compiler-error')
    return 'unknown'


def main():
    from public_compile_diagnostics import make_diagnostics
    diagnostics = make_diagnostics(Path.cwd(), os.environ)
    report = make_report(Path('build/logs'), os.environ)
    fast = read_result(Path('build/logs/ble-fast-result.json'))
    report['ble_regression'] = {
        'baseline_reproduced': fast.get('baseline_reproduced') is True,
        'fixed_passed': fast.get('fixed_passed') is True,
        'scenarios': 3 if fast.get('scenarios') == 3 else 0,
        'host_suite': 'passed' if Path('build/logs/ble-host-passed').is_file() else 'not-validated'}
    import re
    # Only public test source line numbers; never forward assertion text, payloads or raw logs.
    try:
        host_log = Path('build/logs/build-package.log').read_text(errors='replace')[-262144:]
        match = re.search(r'BLESessionChecks\.swift:([0-9]{1,5}): (?:Precondition|Assertion) failed', host_log)
        report['host_assertion_line'] = int(match.group(1)) if match else None
    except OSError:
        report['host_assertion_line'] = None
    report['compile_diagnostic'] = compile_failure_kind(diagnostics=diagnostics['stages']['release'])
    destination = Path('build/public')
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['LinkCard 0.9.2 build28: schema-limited build log']
    lines.extend(key + ': ' + value for key, value in report['stages'].items())
    lines += ['unit: ' + report['unit']['status'], 'fullApp: ' + report['fullApp']['status'],
              'native_validation: ' + report['native_validation'],
              'compile_check: ' + report['compile_diagnostic'],
              'Artifact upload and final workflow success must be checked separately.',
              'No raw logs, simulator identifiers, screenshots or attachments are exported.']
    (destination / 'build.log').write_text('\n'.join(lines) + '\n')
    (destination / 'compiler-diagnostics.json').write_text(
        json.dumps(diagnostics, indent=2) + '\n')
    print('Wrote bounded public results and allowlisted compiler diagnostics; raw logs not exported.')


if __name__ == '__main__':
    main()
