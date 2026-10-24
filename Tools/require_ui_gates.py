#!/usr/bin/env python3
"""Fail closed: an IPA is publishable only after both native test gates pass."""
import json
from pathlib import Path
results = {}
for suite, filename in [('unit', 'mist-uikit-result.json'), ('fullApp', 'full-app-ui-result.json')]:
    path = Path('build/logs') / filename
    results[suite] = json.loads(path.read_text()) if path.exists() else {'status': 'not-run'}
    print(suite, results[suite])
failed = [suite for suite, result in results.items() if result.get('status') != 'passed']
full = results['fullApp']
if full.get('scope') != 'fullApp' or full.get('test_counts') != {'passedTests':4,'failedTests':0,'skippedTests':0,'totalTestCount':4}:
    failed.append('fullApp requires exactly four passed, zero failed, zero skipped (not sidebar diagnostic)')
if failed:
    raise SystemExit('::error::IPA publication blocked: ' + ', '.join(failed))
print('PASS: unit and fullApp native UI gates')
