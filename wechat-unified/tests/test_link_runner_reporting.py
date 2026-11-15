#!/usr/bin/env python3
"""Synthetic checks for link XCTest failure reporting; no Apple SDK required."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('link_runner', ROOT / 'tools/test_link_flow_ios.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

class ReportingTests(unittest.TestCase):
    def test_first_exception_before_long_tail(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / 'log'
            log.write_text('Test Case started\n' + "*** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: 'synthetic reason'\n" + '*** First throw call stack:\n0 CoreFoundation synthetic_frame\n' + 'noise\n' * 200 + "uncaught exception 'SECOND'\n")
            out = io.StringIO()
            with contextlib.redirect_stdout(out): runner.failure_context(log)
            text = out.getvalue()
            for part in ('Test Case started', 'NSInvalidArgumentException', 'synthetic reason', 'synthetic_frame'):
                self.assertIn(part, text)
            self.assertNotIn("exception 'SECOND'", text)

    def test_missing_exception_shows_failure_tail(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / 'log'
            log.write_text('build failed\n')
            out = io.StringIO()
            with contextlib.redirect_stdout(out): runner.failure_context(log)
            self.assertIn('build failed', out.getvalue())
            self.assertIn('No NSException', out.getvalue())

    def test_failed_build_is_not_masked_by_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'result'
            device = {'state': 'Shutdown', 'udid': 'synthetic'}
            def run(args, **kwargs):
                if args[0] == 'xcodebuild':
                    self.assertNotIn('SYNTHETIC_SECRET', kwargs['env'])
                    kwargs['stdout'].write(b"uncaught exception 'NSInvalidArgumentException', reason: 'synthetic'\n0 synthetic_frame\n")
                    raise subprocess.CalledProcessError(65, args)
                raise subprocess.TimeoutExpired(args, 60)
            output = io.StringIO()
            with patch.object(sys, 'argv', ['runner', str(out)]), patch.object(runner.platform, 'system', return_value='Darwin'), patch.object(runner, 'capture', return_value=json.dumps({}).encode()), patch.object(runner, 'choose_device', return_value=({}, device)), patch.object(runner, 'generate', return_value=out / 'project'), patch.object(runner.subprocess, 'run', side_effect=run), patch.dict(runner.os.environ, {'SYNTHETIC_SECRET': 'do-not-log'}), contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(subprocess.CalledProcessError) as error: runner.main()
            self.assertEqual(error.exception.returncode, 65)
            self.assertIn('synthetic_frame', output.getvalue())
            self.assertIn("reason: 'synthetic'", (out / 'xcodebuild.log').read_text())

if __name__ == '__main__': unittest.main()
