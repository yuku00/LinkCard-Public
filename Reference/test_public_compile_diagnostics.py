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
            sources = {'LinkCard/ContentView.swift': None, 'LinkCard.xcodeproj': None}
            (root / 'LinkCard').mkdir()
            (root / 'LinkCard/ContentView.swift').write_text('public fixture\n')
            return module.extract(path, root, sources, environment or {})

    def test_real_compiler_error_preserves_public_location_and_explanation(self):
        result = self.extract("$ROOT/LinkCard/ContentView.swift:12:9: error: cannot find 'body' in scope\n 12 | private snippet\n    | ^\n")
        self.assertEqual(result['items'], [{'file': 'LinkCard/ContentView.swift', 'line': 12, 'column': 9, 'severity': 'error', 'message': "cannot find 'body' in scope"}])
        self.assertNotIn('snippet', json.dumps(result))
        self.assertNotIn('$ROOT', json.dumps(result))

    def test_credentials_and_external_paths_are_redacted_not_dropped(self):
        values = ['github_pat_SYNTHETIC', 'ghp_SYNTHETIC', 'https://user:pass@example.invalid?q=hidden',
                  '/Users/example/private', 'file:///private/example', 'Bearer SYNTHETIC',
                  'API_KEY=synthetic-key', 'person@example.invalid',
                  '00000000-1111-2222-3333-444444444444']
        for value in values:
            with self.subTest(value=value):
                result = self.extract('error: failed to load "' + value + '"\n')
                self.assertEqual(len(result['items']), 1)
                self.assertNotIn(value, json.dumps(result))
                self.assertEqual(result['reasons']['redacted'], 1)

    def test_environment_sensitive_keys_only(self):
        text = "LinkCard/ContentView.swift:1:1: error: cannot find 'body' in scope\n"
        result = self.extract(text, {'MY_TOKEN': 'body'})
        self.assertEqual(result['items'][0]['message'], "cannot find '[redacted]' in scope")
        self.assertIn("'body'", self.extract(text, {'TERM': 'body', 'MONKEY': 'body'})['items'][0]['message'])

    def test_unapproved_locations_cannot_escape_root(self):
        for name in ['/Users/person/LinkCard/ContentView.swift', '/home/person/private.swift',
                     '$ROOT/../LinkCard/ContentView.swift', 'Unknown.swift', '$ROOT/LinkCard/Secret.swift']:
            result = self.extract(name + ":1:1: error: cannot find 'body' in scope\n")
            self.assertEqual(result['items'][0]['file'], '[external-path]')
            self.assertEqual(result['reasons']['external-location'], 1)

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

    def test_tool_formats_and_no_column_regression(self):
        cases = [
            ('xcodebuild:error: invalid scheme', '[tool:xcodebuild]'),
            ('error: module emission failed', '[compiler]'),
            ('LinkCard/ContentView.swift:2: error: new diagnostic wording', 'LinkCard/ContentView.swift'),
            ('./LinkCard/../LinkCard/ContentView.swift:2:1: error: unexpected SDK type', 'LinkCard/ContentView.swift'),
            ('clang: error: no input files', '[tool:clang]'),
            ('ld: library not found for -lMissing', '[tool:ld]'),
        ]
        for text, filename in cases:
            with self.subTest(text=text):
                result = self.extract(text + '\n')
                self.assertEqual(len(result['items']), 1)
                self.assertEqual(result['items'][0]['file'], filename)

    def test_public_identifiers_need_not_exist_in_source(self):
        text = "LinkCard/ContentView.swift:1:1: error: cannot find 'BrandNewSDKType' in scope\n"
        result = self.extract(text, {'TERM': 'BrandNewSDKType', 'PUBLIC_LABEL': 'cannot find'})
        self.assertEqual(result['items'][0]['message'], "cannot find 'BrandNewSDKType' in scope")

    def test_project_sdk_and_real_tool_envelopes(self):
        cases = [
            ('LinkCard.xcodeproj: error: Signing requires a development team.', 'LinkCard.xcodeproj'),
            ('/Applications/Xcode.app/Contents/Developer/SDKs/iPhoneOS.sdk/usr/include/header.h:10:2: fatal error: module not found', '[sdk]'),
            ('/usr/bin/clang: error: linker command failed with exit code 1 (use -v to see invocation)', '[tool:clang]'),
            ('ld: framework \'UnavailableKit\' not found', '[tool:ld]'),
            ('actool: error: No matching simulator runtime', '[tool:actool]'),
            ('ibtool: warning: document version is unsupported', '[tool:ibtool]'),
            ('codesign: error: signing failed', '[tool:codesign]'),
        ]
        for text, filename in cases:
            with self.subTest(text=text):
                result = self.extract(text + '\n')
                self.assertEqual(result['items'][0]['file'], filename)
                self.assertEqual(sum(result['candidates'].values()), 1)

    def test_symlinked_source_parents_are_resolved(self):
        with tempfile.TemporaryDirectory() as folder, tempfile.TemporaryDirectory() as other:
            root = Path(folder).resolve()
            (root / 'Public').mkdir()
            (root / 'Public/Main.swift').write_text('fixture')
            (root / 'Inside').symlink_to(root / 'Public', target_is_directory=True)
            (root / 'Outside').symlink_to(Path(other), target_is_directory=True)
            (Path(other) / 'Main.swift').write_text('private fixture')
            sources = {'Public/Main.swift': None, 'Outside/Main.swift': None}
            path = root / 'compile.log'
            path.write_text('Inside/Main.swift:1: error: new message\nOutside/Main.swift:1: error: new message\n')
            result = module.extract(path, root, sources, {})
            self.assertEqual([x['file'] for x in result['items']], ['Public/Main.swift', '[external-path]'])
            path.write_text('error: cannot open "' + str(root / 'Outside/Main.swift') + '"\n')
            self.assertEqual(module.extract(path, root, sources, {})['items'][0]['message'], 'cannot open "[external-path]"')
            (root / 'logs').symlink_to(Path(other), target_is_directory=True)
            self.assertEqual(module.extract(root / 'logs/Main.swift', root, sources, {})['read_status'], 'rejected')

    def test_path_mapping_precedes_secret_matching(self):
        result = self.extract('error: cannot open "$ROOT/LinkCard/../LinkCard/ContentView.swift"\n', {'ACCESS_TOKEN': 'ContentView'})
        self.assertEqual(result['items'][0]['message'], 'cannot open "LinkCard/[redacted].swift"')

    def test_redaction_before_truncation_and_final_dedup(self):
        secret = 'SYNTHETIC_SECRET_SUFFIX'
        message = 'a' * 625 + secret + 'z' * 100
        result = self.extract('error: ' + message + '1\nerror: ' + message + '2\n', {'API_KEY': secret})
        self.assertEqual(len(result['items']), 1)
        self.assertEqual(len(result['items'][0]['message']), 640)
        self.assertNotIn('SYNTHETIC', json.dumps(result))
        self.assertEqual(result['reasons']['truncated'], 2)
        self.assertEqual(result['reasons']['duplicate'], 1)

    def test_unsafe_payloads_have_fixed_rejection_reasons(self):
        messages = ['command: swiftc -o private-output', 'environment: HOME=private',
                    'let privateValue = "private"', 'snippet: private source',
                    'profile: private person', 'username=private', 'User: private',
                    '/usr/bin/clang -o private-output', 'bad\x1btext']
        for message in messages:
            result = self.extract('error: ' + message + '\n')
            self.assertEqual(result['items'], [])
            self.assertEqual(result['reasons']['unsafe-payload'], 1)
        result = self.extract('mystery: error: private\nerror: ' + 'x' * 5000 + '\n')
        self.assertEqual(result['candidates']['error'], 2)
        self.assertEqual(result['reasons']['unrecognized-location'], 1)
        self.assertEqual(result['reasons']['line-limit'], 1)
        self.assertEqual(result['omitted'], 2)
        self.assertNotIn('private', json.dumps(result))

    def test_continuations_source_and_commands_are_not_exported(self):
        result = self.extract('xcodebuild: error: Unable to find a destination matching the provided destination specifier:\n'
                              '\t{ platform:iOS, id:PRIVATE_DEVICE }\n'
                              ' 12 | let secret = "PRIVATE_SOURCE"\n'
                              ' /usr/bin/swiftc -DPRIVATE_COMMAND\n HOME=PRIVATE_ENV\n')
        self.assertEqual(len(result['items']), 1)
        self.assertNotIn('PRIVATE', json.dumps(result))

    def test_redaction_rules_do_not_expose_credential_suffixes(self):
        for text in ['Authorization: Bearer SYNTHETIC_PAYLOAD', 'Authorization: Basic SYNTHETIC_PAYLOAD',
                     'ghp_SYNTHETIC_PAYLOAD', 'token="SYNTHETIC_PAYLOAD"']:
            result = self.extract('error: failed ' + text + '\n', {'API_SECRET': 'ghp_'})
            self.assertEqual(len(result['items']), 1)
            self.assertNotIn('SYNTHETIC_PAYLOAD', json.dumps(result))

    def test_overlapping_environment_and_field_redactions(self):
        cases = [('password=two words', {'PASSWORD': 'two words'}, 'words'),
                 ('failed prefix/path suffix', {'API_KEY': 'prefix/path suffix'}, 'suffix'),
                 ('Authorization: Bearer "SYNTHETIC_PAYLOAD"', {}, 'SYNTHETIC_PAYLOAD'),
                 ('{"password": "SYNTHETIC_PAYLOAD"}', {}, 'SYNTHETIC_PAYLOAD')]
        for text, environment, marker in cases:
            result = self.extract('error: ' + text + '\n', environment)
            self.assertNotIn(marker, json.dumps(result))

    def test_verbose_linker_lines_are_not_errors(self):
        result = self.extract('ld: version 1000\nld: warning: ignoring duplicate libraries\n')
        self.assertEqual(result['candidates'], {'error': 0, 'warning': 1})

    def test_known_typecheck_diagnostic_is_readable(self):
        message = 'the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions'
        result = self.extract('LinkCard/ContentView.swift:2:3: error: ' + message + '\n')
        self.assertEqual(result['items'][0]['message'], message)


if __name__ == '__main__':
    unittest.main()
