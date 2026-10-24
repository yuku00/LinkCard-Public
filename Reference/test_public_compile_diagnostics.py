# SPDX-License-Identifier: GPL-3.0-or-later
"""Host fixtures only: publication safety, not native application validation."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('diagnostics', Path(__file__).resolve().parents[1] / 'Tools/public_compile_diagnostics.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CompilerDiagnosticsTests(unittest.TestCase):
    def extract(self, lines, environment=None):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            path = root / 'compile.log'
            path.write_text(lines.replace('$ROOT', str(root)))
            sources = {'LinkCard/ContentView.swift': 'struct ContentView { var body: some View }\n' * 30}
            return module.extract(path, root, sources, environment or {})

    def test_real_compiler_error_preserves_public_location_and_explanation(self):
        result = self.extract("$ROOT/LinkCard/ContentView.swift:12:9: error: cannot find 'body' in scope\n 12 | private snippet\n    | ^\n")
        self.assertEqual(result['items'], [{'file': 'LinkCard/ContentView.swift', 'line': 12, 'column': 9, 'severity': 'error', 'message': "cannot find 'body' in scope"}])
        self.assertNotIn('snippet', json.dumps(result))
        self.assertNotIn('$ROOT', json.dumps(result))

    def test_token_credentials_personal_paths_and_unknown_text_are_omitted(self):
        bad = ["cannot find 'github_pat_ATTACK' in scope", "cannot find 'ghp_ATTACK' in scope",
               "cannot find 'SECRET_MARKER' in scope", "cannot find 'https://user:password@host' in scope",
               "cannot find '/Users/person/private' in scope", "cannot find 'file:///private/name' in scope",
               'something unknown body', "cannot find 'body' in scope https://host",
               "cannot find 'body\x1b' in scope", "cannot find 'body' in scope" + 'x' * 5000]
        for message in bad:
            result = self.extract('$ROOT/LinkCard/ContentView.swift:1:1: error: ' + message + '\n')
            self.assertEqual(result['items'], [], message)
            self.assertEqual(result['omitted'], 1)

    def test_environment_values_rejected_even_if_public_identifier(self):
        result = self.extract("$ROOT/LinkCard/ContentView.swift:1:1: error: cannot find 'body' in scope\n", {'MY_TOKEN': 'body'})
        self.assertEqual(result['items'], [])

    def test_unapproved_locations_cannot_escape_root(self):
        for name in ['/Users/person/LinkCard/ContentView.swift', '/home/person/private.swift',
                     '$ROOT/../LinkCard/ContentView.swift', 'Unknown.swift', '$ROOT/LinkCard/Secret.swift']:
            result = self.extract(name + ":1:1: error: cannot find 'body' in scope\n")
            self.assertEqual(result['items'], [])

    def test_count_limit_dedup_and_error_priority(self):
        lines = ''.join("LinkCard/ContentView.swift:%s:1: warning: result of call to 'body' is unused\n" % n for n in range(1, 25))
        error = "LinkCard/ContentView.swift:25:1: error: cannot find 'body' in scope\n"
        result = self.extract(lines + error + error)
        self.assertEqual(len(result['items']), 12)
        self.assertEqual(result['items'][0]['severity'], 'error')
        self.assertEqual(result['omitted'], 13)

    def test_symlinks_missing_and_oversized_logs_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / 'log'
            self.assertEqual(module.extract(path, root, {}, {})['read_status'], 'missing')
            path.write_text('x')
            link = root / 'link'
            link.symlink_to(path)
            self.assertEqual(module.extract(link, root, {}, {})['read_status'], 'rejected')
            with path.open('wb') as out:
                out.truncate(module.MAX_LOG + 1)
            self.assertEqual(module.extract(path, root, {}, {})['read_status'], 'rejected')

    def test_known_typecheck_diagnostic_is_readable(self):
        message = 'the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions'
        result = self.extract('LinkCard/ContentView.swift:2:3: error: ' + message + '\n')
        self.assertEqual(result['items'][0]['message'], message)


if __name__ == '__main__':
    unittest.main()
