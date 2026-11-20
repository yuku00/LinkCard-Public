#!/usr/bin/env python3
"""Real macOS production-C gate: skips are failures, no simulators or XCTest."""
import pathlib
import platform
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
if sys.platform != 'darwin':
    raise SystemExit('BLOCKED: this gate must execute on Apple macOS')
sys.path.insert(0, str(ROOT / 'tests'))
import test_storage_migration

print('Apple production migration gate:', platform.platform(), flush=True)
suite = unittest.defaultTestLoader.loadTestsFromModule(test_storage_migration)
result = unittest.TextTestRunner(verbosity=2).run(suite)
if result.skipped:
    print('BLOCKED: skipped safety assertions are not an Apple pass', file=sys.stderr)
raise SystemExit(0 if result.wasSuccessful() and not result.skipped else 1)
