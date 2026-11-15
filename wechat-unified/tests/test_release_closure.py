"""Offline checks for files used by the release build; never performs an upload."""
import ast
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def whitelist():
    tree = ast.parse((ROOT / 'tools/release.py').read_text())
    paths = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AugAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if any(isinstance(t, ast.Name) and t.id == 'allowed' for t in targets):
                paths.update(n.value for n in ast.walk(node.value)
                             if isinstance(n, ast.Constant) and isinstance(n.value, str)
                             and n.value.startswith(('Sources/', 'tests/', 'tools/')))
    return paths


class ReleaseClosure(unittest.TestCase):
    def test_build_and_local_source_closure(self):
        allowed = whitelist()
        missing = {p for p in allowed if not (ROOT / p).is_file()}
        # All production translation units are compiled with Sources/*.m.
        for path in (ROOT / 'Sources').iterdir():
            if path.is_file() and path.relative_to(ROOT).as_posix() not in allowed:
                missing.add(path.relative_to(ROOT).as_posix())
        paths = [ROOT / p for p in allowed if (ROOT / p).is_file()]
        for path in paths:
            if path.suffix not in ('.py', '.sh', '.m', '.h', '.inc', '.c', '.yml'):
                continue
            text = path.read_text()
            for ref in re.findall(r'(?:Sources|tests|tools)/[A-Za-z0-9_.+/-]+', text):
                if (ROOT / ref).is_file() and ref not in allowed:
                    missing.add(ref)
            for name in re.findall(r'[#@]\s*(?:import|include)\s*"([^"/]+)"', text):
                for target in (path.parent / name, ROOT / 'Sources' / name):
                    if target.is_file():
                        ref = target.relative_to(ROOT).as_posix()
                        if ref not in allowed:
                            missing.add(ref)
        self.assertEqual(sorted(missing), [])

    def test_foundation_mocks_do_not_import_uikit(self):
        roots = ['tests/revoke_notice_mock.m', 'Sources/WURevokeNotice.m',
                 'Sources/MessageConstruction.m', 'tests/message_revoke_proxy.m',
                 'tests/message_service_compatibility.m', 'tests/host_service_native.m',
                 'Sources/WUHostService.m', 'tests/voice_display_native.m',
                 'Sources/VoiceDisplay.m', 'Sources/VoiceLogic.m']
        seen = set()
        def visit(path):
            path = path.resolve()
            if path in seen:
                return
            seen.add(path)
            text = path.read_text()
            self.assertNotRegex(text, r'(?m)^\s*#\s*import\s*[<"]UIKit/')
            for name in re.findall(r'(?m)^\s*#\s*(?:import|include)\s*"([^"]+)"', text):
                for target in (path.parent / name, ROOT / 'Sources' / name):
                    if target.is_file():
                        visit(target)
                        break
        for name in roots:
            visit(ROOT / name)


if __name__ == '__main__':
    unittest.main()
