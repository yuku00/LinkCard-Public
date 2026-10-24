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
    return {'schema': 1, 'version': '0.8.6', 'build': 25,
            'stages': outcomes, 'unit': {'status': unit_status},
            'fullApp': {'status': full_status, 'scope': scope, 'test_counts': counts},
            'native_validation': 'passed' if passed else 'not-validated',
            'artifact_upload': 'not-attested', 'hardware_validation': 'not-performed'}


def compile_failure_kind(path):
    # Never export lines, paths or diagnostic payloads. Only these fixed enums.
    try:
        if path.is_symlink() or path.stat().st_size > 16 * 1024 * 1024:
            return 'unknown'
        text = path.read_text(errors='replace')
    except OSError:
        return 'unknown'
    if 'unable to type-check this expression in reasonable time' in text:
        return 'swift-typecheck-limit'
    if 'generic parameter' in text and 'could not be inferred' in text:
        return 'swift-generic-inference'
    if 'error:' in text and 'is only available in iOS' in text:
        return 'swift-api-availability'
    if 'error:' in text and 'cannot find' in text:
        return 'swift-missing-symbol'
    if 'error:' in text and 'cannot convert' in text:
        return 'swift-type-mismatch'
    if '** BUILD FAILED **' in text:
        return 'xcode-build-failed'
    if '** BUILD SUCCEEDED **' in text:
        return 'xcode-build-succeeded'
    return 'unknown'


def main():
    report = make_report(Path('build/logs'), os.environ)
    destination = Path('build/public')
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['LinkCard 0.8.6 build25: schema-limited build log']
    lines.extend(key + ': ' + value for key, value in report['stages'].items())
    lines += ['unit: ' + report['unit']['status'], 'fullApp: ' + report['fullApp']['status'],
              'native_validation: ' + report['native_validation'],
              'compile_check: ' + compile_failure_kind(Path('build/logs/build-package.log')),
              'Artifact upload and final workflow success must be checked separately.',
              'No raw logs, simulator identifiers, screenshots or attachments are exported.']
    (destination / 'build.log').write_text('\n'.join(lines) + '\n')
    from public_compile_diagnostics import make_diagnostics
    (destination / 'compiler-diagnostics.json').write_text(
        json.dumps(make_diagnostics(Path.cwd(), os.environ), indent=2) + '\n')
    print('Wrote bounded public results and allowlisted compiler diagnostics; raw logs not exported.')


if __name__ == '__main__':
    main()
